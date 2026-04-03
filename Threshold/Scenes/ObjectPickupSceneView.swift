//
//  ObjectPickupSceneView.swift
//  Threshold
//
//  Immersive scene: "Object Pickup" — Patient picks up 5 colored cubes
//  from the floor using a pinch grip (thumb + index finger) and places
//  them into a box. Audio encouragement after each placement.
//

import SwiftUI
import RealityKit
import ARKit
import RealityKitContent
import AVFoundation

// MARK: - Chime synthesiser

private final class ChimeSoundPlayer: @unchecked Sendable {

    private let engine     = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let envNode    = AVAudioEnvironmentNode()
    private let mono       = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

    init() {
        engine.attach(playerNode)
        engine.attach(envNode)
        engine.connect(playerNode, to: envNode, format: mono)
        engine.connect(envNode, to: engine.mainMixerNode, format: nil)
        envNode.renderingAlgorithm = .HRTFHQ
        envNode.distanceAttenuationParameters.referenceDistance = 0.5
        envNode.distanceAttenuationParameters.rolloffFactor     = 1.0
        try? engine.start()
    }

    /// Play a pleasant chime at `position` in world space.
    func play(at position: SIMD3<Float>) {
        let sampleRate: Double = 44_100
        let frameCount = AVAudioFrameCount(sampleRate * 0.2) // 200 ms
        guard let buffer = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        let samples = buffer.floatChannelData![0]
        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            let envelope = exp(-t * 15.0) // gentle decay
            let tone = sin(2.0 * .pi * 800.0 * t) * 0.5 // 800 Hz sine
            let harmonic = sin(2.0 * .pi * 1200.0 * t) * 0.2 // soft overtone
            samples[i] = Float(envelope * (tone + harmonic))
        }
        playerNode.position = AVAudio3DPoint(x: position.x, y: position.y, z: position.z)
        playerNode.scheduleBuffer(buffer)
        playerNode.play()
    }
}

// MARK: - Scene View

struct ObjectPickupSceneView: View {

    @Environment(AppModel.self) var appModel
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace

    // MARK: - Scene State

    enum SceneState {
        case setup
        case active
        case complete
    }

    @State private var sceneState: SceneState = .setup

    // MARK: - Entity References

    @State private var rootEntity = Entity()
    @State private var boxEntity: Entity?
    @State private var cubeEntities: [ModelEntity] = []

    // MARK: - Pickup State

    @State private var placedCount = 0
    @State private var heldCubeIndex: Int?
    @State private var isPinching = false

    // MARK: - Tracking State

    @State private var trackingError: String?

    // MARK: - Audio

    @State private var chimePlayer = ChimeSoundPlayer()
    @State private var speechSynthesizer = AVSpeechSynthesizer()

    // MARK: - ARKit (declared as `let` — not @State)

    private let arSession = ARKitSession()
    private let handTracking = HandTrackingProvider()

    // MARK: - Constants

    private let cubeSize: Float = 0.05
    private let cubeColors: [UIColor] = [.systemRed, .systemBlue, .systemGreen, .systemYellow, .systemOrange]

    /// Thumb-to-index distance below which a pinch is detected (metres).
    private let pinchThreshold: Float = 0.025
    /// Thumb-to-index distance above which a pinch is released (metres) — hysteresis.
    private let releaseThreshold: Float = 0.04
    /// Max distance from pinch midpoint to cube center to pick it up (metres).
    private let grabRadius: Float = 0.08
    /// Max distance from cube to box opening to count as placed (metres).
    private let dropZoneRadius: Float = 0.15

    /// Box placement position.
    private let boxPosition: SIMD3<Float> = [0.6, 0, -0.4]

    /// Encouragement phrases keyed by placement count (1-indexed).
    private let encouragements = ["Well done!", "Great job!", "Keep it up!", "Almost there!", "You did it!"]

    // MARK: - Body

    var body: some View {
        RealityView { (content: inout RealityViewContent, attachments: RealityViewAttachments) in
            content.add(rootEntity)

            // Load and place the box
            do {
                let box = try await Entity(named: "Box", in: realityKitContentBundle)
                box.position = boxPosition
                // Adjust so box base sits on the floor
                let bounds = box.visualBounds(relativeTo: nil)
                let boundsHeight = bounds.max.y - bounds.min.y
                if boundsHeight > 0.01 {
                    box.position.y += boxPosition.y - bounds.min.y
                }
                rootEntity.addChild(box)
                boxEntity = box
            } catch {
                trackingError = "Failed to load box model: \(error.localizedDescription)"
            }

            guard boxEntity != nil else { return }

            // Spawn cubes
            spawnCubes()

            sceneState = .active

            if let panel = attachments.entity(for: "controls") {
                panel.position = [0, 1.5, -1.2]
                content.add(panel)
            }
        } attachments: {
            Attachment(id: "controls") {
                SceneControlPanel(
                    sceneName: "Object Pickup",
                    instruction: instructionText,
                    isReady: false,
                    hasDropped: sceneState == .complete,
                    onDrop: { },
                    onReset: resetScene,
                    onReturn: { await dismissImmersiveSpace() }
                )
            }
        }
        .task {
            await runHandTracking()
        }
    }

    // MARK: - Instruction Text

    private var instructionText: String {
        if let error = trackingError { return error }
        switch sceneState {
        case .setup:
            return "Setting up…"
        case .active:
            return "Pinch objects with your right hand and place them in the box. (\(placedCount)/5)"
        case .complete:
            return "All objects collected! Check the main window."
        }
    }

    // MARK: - Cube Spawning

    private func spawnCubes() {
        let mesh = MeshResource.generateBox(size: cubeSize)
        var positions: [SIMD3<Float>] = []

        for i in 0..<5 {
            let material = SimpleMaterial(
                color: cubeColors[i],
                roughness: 0.3,
                isMetallic: false
            )
            let cube = ModelEntity(mesh: mesh, materials: [material])

            // Generate random floor position with minimum spacing
            var position: SIMD3<Float>
            var attempts = 0
            repeat {
                position = SIMD3<Float>(
                    Float.random(in: -0.75...0.75),
                    cubeSize / 2.0, // half height so cube sits on floor
                    Float.random(in: -1.5...(-0.5))
                )
                attempts += 1
            } while positions.contains(where: { simd_distance($0, position) < 0.3 }) && attempts < 50

            positions.append(position)
            cube.position = position
            rootEntity.addChild(cube)
            cubeEntities.append(cube)
        }
    }

    // MARK: - Hand Tracking

    private func runHandTracking() async {
        let auth = await arSession.requestAuthorization(for: [.handTracking])
        guard auth[.handTracking] == .allowed else {
            trackingError = "Hand tracking permission was denied. Please enable it in Settings."
            return
        }

        do {
            try await arSession.run([handTracking])
        } catch {
            trackingError = "Hand tracking unavailable: \(error.localizedDescription)"
            return
        }

        for await update in handTracking.anchorUpdates {
            let anchor = update.anchor
            guard anchor.chirality == .right, anchor.isTracked else { continue }
            guard let skeleton = anchor.handSkeleton else { continue }
            guard sceneState == .active else { continue }

            let thumbTip = skeleton.joint(.thumbTip)
            let indexTip = skeleton.joint(.indexFingerTip)
            guard thumbTip.isTracked, indexTip.isTracked else { continue }

            let thumbWorld = anchor.originFromAnchorTransform * thumbTip.anchorFromJointTransform
            let indexWorld = anchor.originFromAnchorTransform * indexTip.anchorFromJointTransform

            let thumbPos = SIMD3<Float>(thumbWorld.columns.3.x, thumbWorld.columns.3.y, thumbWorld.columns.3.z)
            let indexPos = SIMD3<Float>(indexWorld.columns.3.x, indexWorld.columns.3.y, indexWorld.columns.3.z)

            let pinchDistance = simd_distance(thumbPos, indexPos)
            let pinchMidpoint = (thumbPos + indexPos) / 2.0

            // Pinch state with hysteresis
            let wasPinching = isPinching
            if pinchDistance < pinchThreshold {
                isPinching = true
            } else if pinchDistance > releaseThreshold {
                isPinching = false
            }

            if isPinching {
                if heldCubeIndex == nil && !wasPinching {
                    // Just started pinching — try to grab nearest unplaced cube
                    tryGrabCube(near: pinchMidpoint)
                }

                // Move held cube to pinch midpoint
                if let idx = heldCubeIndex {
                    cubeEntities[idx].position = pinchMidpoint
                }
            } else if wasPinching && !isPinching {
                // Just released — check if cube is near box
                if let idx = heldCubeIndex {
                    releaseCube(index: idx)
                }
            }
        }
    }

    // MARK: - Grab / Release

    private func tryGrabCube(near point: SIMD3<Float>) {
        var closestIndex: Int?
        var closestDist: Float = grabRadius

        for (i, cube) in cubeEntities.enumerated() {
            guard cube.isEnabled else { continue } // skip placed cubes
            let dist = simd_distance(cube.position, point)
            if dist < closestDist {
                closestDist = dist
                closestIndex = i
            }
        }

        heldCubeIndex = closestIndex
    }

    private func releaseCube(index: Int) {
        let cube = cubeEntities[index]
        let boxOpeningPos = boxDropZoneCenter()

        if simd_distance(cube.position, boxOpeningPos) < dropZoneRadius {
            // Placed in box — animate to box center, then disable
            placedCount += 1
            heldCubeIndex = nil

            cube.isEnabled = false  // disable immediately to prevent re-pickup

            cube.move(
                to: Transform(translation: boxOpeningPos),
                relativeTo: rootEntity,
                duration: 0.2,
                timingFunction: .easeOut
            )

            // Play chime and speak encouragement
            let count = placedCount
            let player = chimePlayer
            let synth = speechSynthesizer
            let phrase = encouragements[count - 1]
            let audioPos = boxOpeningPos

            Task {
                try? await Task.sleep(nanoseconds: 200_000_000) // wait for snap animation

                player.play(at: audioPos)
                let utterance = AVSpeechUtterance(string: phrase)
                utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85
                synth.speak(utterance)

                if count >= 5 {
                    try? await Task.sleep(nanoseconds: 1_500_000_000) // let speech finish
                    guard sceneState == .active else { return } // cancelled by reset
                    sceneState = .complete
                    appModel.showCongratulations = true
                }
            }
        } else {
            // Dropped outside box — cube stays where it is, still pickable
            heldCubeIndex = nil
        }
    }

    /// Center of the box drop zone — box position raised to the opening height.
    private func boxDropZoneCenter() -> SIMD3<Float> {
        guard let box = boxEntity else { return boxPosition }
        let bounds = box.visualBounds(relativeTo: nil)
        let openingY = bounds.max.y
        return SIMD3<Float>(boxPosition.x, openingY, boxPosition.z)
    }

    // MARK: - Reset

    private func resetScene() {
        speechSynthesizer.stopSpeaking(at: .immediate)

        // Remove all cubes
        for cube in cubeEntities {
            cube.removeFromParent()
        }
        cubeEntities.removeAll()

        // Respawn cubes at new random positions
        spawnCubes()

        placedCount = 0
        heldCubeIndex = nil
        isPinching = false
        sceneState = .active
        appModel.showCongratulations = false
    }
}
