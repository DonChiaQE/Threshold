//
//  DumbbellSceneView.swift
//  Threshold
//
//  Immersive scene: A yellow dot follows where the user is looking on the
//  floor (via ARKit device-pose tracking). The user looks at the dot near
//  their foot and pinches to mark it. A block then appears 1.5 m above that
//  spot and drops beside it (near-miss) when the user taps "Drop" in the panel.
//
//  Interaction flow:
//    1. A yellow dot on the floor tracks where the user's gaze hits the ground.
//    2. Look at the dot and pinch (Vision Pro native gesture) to stamp the position.
//    3. A block appears above the mark.
//    4. Look up at the panel and tap "Drop" – the block falls beside the mark.
//

import SwiftUI
import RealityKit
import ARKit
import AVFoundation

// MARK: - Spatial thud audio

/// Owns an AVAudioEngine for the lifetime of the scene and plays a synthesised
/// low-frequency thud at a given world position using binaural HRTF rendering.
private final class ThudAudioPlayer: @unchecked Sendable {

    private let engine      = AVAudioEngine()
    private let playerNode  = AVAudioPlayerNode()
    private let envNode     = AVAudioEnvironmentNode()
    private let mono        = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

    init() {
        engine.attach(playerNode)
        engine.attach(envNode)
        engine.connect(playerNode, to: envNode, format: mono)
        engine.connect(envNode, to: engine.mainMixerNode, format: nil)
        envNode.renderingAlgorithm = .HRTFHQ
        // Attenuate naturally – reference distance matches typical near-miss range
        envNode.distanceAttenuationParameters.referenceDistance = 0.5
        envNode.distanceAttenuationParameters.rolloffFactor     = 1.0
        try? engine.start()
    }

    /// Call from the main actor once the block has visually landed.
    func play(at position: SIMD3<Float>) {
        // Build a short (0.5 s) synthesised thud: bass sine + fast impact noise
        let sampleRate: Double  = 44_100
        let frameCount          = AVAudioFrameCount(sampleRate * 0.5)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        let samples = buffer.floatChannelData![0]
        for i in 0..<Int(frameCount) {
            let t         = Double(i) / sampleRate
            let envelope  = exp(-t * 14.0)
            let bass      = sin(2.0 * .pi * 55.0 * t) * 0.65
            let impact    = Double.random(in: -1.0...1.0) * exp(-t * 40.0) * 0.4
            samples[i]    = Float(envelope * (bass + impact))
        }
        // RealityKit and AVFoundation share the same right-hand coordinate system
        playerNode.position = AVAudio3DPoint(x: position.x, y: position.y, z: position.z)
        playerNode.scheduleBuffer(buffer)
        playerNode.play()
    }
}

// MARK: - Scene view

struct DumbbellSceneView: View {

    @Environment(AppModel.self) var appModel
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace

    // MARK: - State

    @State private var rootEntity    = Entity()
    @State private var reticleEntity: ModelEntity?
    @State private var cubeEntity:    ModelEntity?
    @State private var markerEntity:  ModelEntity?
    @State private var markedPosition: SIMD3<Float>?
    @State private var hasDropped    = false

    // Audio – kept alive for the full scene lifetime
    @State private var thudPlayer    = ThudAudioPlayer()

    private var isMarked: Bool { markedPosition != nil }

    // MARK: - Constants

    /// 30 cm offset ensures the block clearly lands beside – not on – the foot.
    private let nearMissOffset: Float  = 0.30
    private let startHeight: Float     = 1.5
    private let cubeSize: Float        = 0.10
    private let dropDuration: TimeInterval = 0.8

    // MARK: - ARKit

    private let arSession     = ARKitSession()
    private let worldTracking = WorldTrackingProvider()

    // MARK: - Body

    var body: some View {
        RealityView { (content: inout RealityViewContent, attachments: RealityViewAttachments) in
            content.add(rootEntity)

            let reticle = makeReticle()
            reticle.position = SIMD3<Float>(0, 0.01, -0.5)
            rootEntity.addChild(reticle)
            reticleEntity = reticle

            if let panel = attachments.entity(for: "controls") {
                panel.position = [0, 1.5, -1.2]
                content.add(panel)
            }
        } attachments: {
            Attachment(id: "controls") {
                SceneControlPanel(
                    sceneName: "Dumbbell (Foot)",
                    instruction: instructionText,
                    isReady: isMarked && !hasDropped,
                    hasDropped: hasDropped,
                    onDrop: dropCube,
                    onReset: resetScene,
                    onReturn: { await dismissImmersiveSpace() }
                )
            }
        }
        // Pinch on the yellow reticle to mark foot position
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { _ in
                    if !isMarked { markFootPosition() }
                }
        )
        .task {
            await runDeviceTracking()
        }
    }

    private var instructionText: String {
        if !isMarked {
            return "Look at the yellow dot near your foot, then pinch to mark the spot."
        }
        if hasDropped { return "The block missed the marked spot." }
        return "Foot position marked. Look up and tap Drop."
    }

    // MARK: - Entity Builders

    private func makeReticle() -> ModelEntity {
        let mesh     = MeshResource.generateSphere(radius: 0.02)
        let material = SimpleMaterial(color: .yellow, roughness: 1.0, isMetallic: false)
        let reticle  = ModelEntity(mesh: mesh, materials: [material])
        // Larger collision sphere makes it easy to target with eye tracking
        let shape = ShapeResource.generateSphere(radius: 0.06)
        reticle.components.set(CollisionComponent(shapes: [shape]))
        reticle.components.set(InputTargetComponent(allowedInputTypes: .indirect))
        reticle.components.set(HoverEffectComponent())
        return reticle
    }

    // MARK: - Device Tracking

    private func runDeviceTracking() async {
        do {
            try await arSession.run([worldTracking])
        } catch {
            return
        }

        while !Task.isCancelled {
            if !isMarked,
               let deviceAnchor = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) {

                let m          = deviceAnchor.originFromAnchorTransform
                let devicePos  = SIMD3<Float>(m.columns.3.x, m.columns.3.y, m.columns.3.z)
                let fwd        = SIMD3<Float>(-m.columns.2.x, -m.columns.2.y, -m.columns.2.z)

                if fwd.y < -0.05 {
                    let t        = -devicePos.y / fwd.y
                    let floorHit = devicePos + t * fwd
                    reticleEntity?.position = SIMD3<Float>(floorHit.x, 0.01, floorHit.z)
                }
            }
            try? await Task.sleep(nanoseconds: 33_000_000)
        }
    }

    // MARK: - Mark & Drop

    private func markFootPosition() {
        guard let reticle = reticleEntity else { return }
        let pos     = reticle.position
        let footPos = SIMD3<Float>(pos.x, 0, pos.z)
        markedPosition = footPos
        reticleEntity?.isEnabled = false
        placeMarker(at: footPos)
        setupCube(above: footPos)
    }

    private func placeMarker(at position: SIMD3<Float>) {
        let mesh     = MeshResource.generateCylinder(height: 0.005, radius: 0.05)
        let material = SimpleMaterial(color: .systemBlue, roughness: 0.5, isMetallic: false)
        let marker   = ModelEntity(mesh: mesh, materials: [material])
        marker.position = SIMD3<Float>(position.x, 0.003, position.z)
        rootEntity.addChild(marker)
        markerEntity = marker
    }

    private func setupCube(above position: SIMD3<Float>) {
        let mesh     = MeshResource.generateBox(size: cubeSize, cornerRadius: 0.005)
        let material = SimpleMaterial(color: .gray, roughness: 0.3, isMetallic: true)
        let cube     = ModelEntity(mesh: mesh, materials: [material])
        cube.position = SIMD3<Float>(position.x, startHeight, position.z)
        rootEntity.addChild(cube)
        cubeEntity = cube
    }

    private func dropCube() {
        guard let cube = cubeEntity, let pos = markedPosition else { return }
        hasDropped = true

        let target = SIMD3<Float>(pos.x + nearMissOffset, cubeSize / 2, pos.z)
        var dropTransform = cube.transform
        dropTransform.translation = target
        cube.move(to: dropTransform, relativeTo: rootEntity, duration: dropDuration, timingFunction: .easeIn)

        // Fire spatial thud exactly when the block reaches the floor
        let landingPos = target
        Task {
            try? await Task.sleep(nanoseconds: UInt64(dropDuration * 1_000_000_000))
            thudPlayer.play(at: landingPos)
        }
    }

    private func resetScene() {
        cubeEntity?.removeFromParent()
        cubeEntity = nil
        markerEntity?.removeFromParent()
        markerEntity = nil
        markedPosition = nil
        hasDropped = false
        reticleEntity?.isEnabled = true
    }
}
