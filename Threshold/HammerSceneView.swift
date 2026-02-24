//
//  HammerSceneView.swift
//  Threshold
//
//  Immersive scene: Uses ARKit hand tracking to detect the user's right arm,
//  positions a cube (placeholder hammer) to the side of the arm, and swings it
//  past the arm in a near-miss arc when triggered.
//
//  Arc animation:
//    The cube hovers to the upper-left of the arm before the drop.
//    On "Drop" it swings diagonally across the body toward the arm (75 % of
//    the duration, easeIn), then snaps sharply past it to the landing spot
//    (25 %, easeOut) – simulating a hammer bypassing the arm at the last moment.
//

import SwiftUI
import RealityKit
import ARKit

struct HammerSceneView: View {

    @Environment(AppModel.self) var appModel
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace

    // MARK: - State

    @State private var rootEntity = Entity()
    @State private var cubeEntity: ModelEntity?
    @State private var armPosition: SIMD3<Float>?
    @State private var hasDropped = false
    @State private var isTracking = false
    @State private var trackingError: String?

    // MARK: - Constants

    /// Lateral offset from the arm so the cube misses (metres).
    private let nearMissOffset: Float = 0.10
    /// Height above the arm where the cube starts (metres).
    private let startHeight: Float = 0.45
    /// Cube edge length (metres).
    private let cubeSize: Float = 0.08
    /// Total duration of the two-stage arc drop (seconds).
    private let dropDuration: TimeInterval = 1.2

    // MARK: - ARKit

    private let arSession = ARKitSession()
    private let handTracking = HandTrackingProvider()

    // MARK: - Body

    var body: some View {
        RealityView { content, attachments in
            content.add(rootEntity)

            // Attach the control panel floating in front of the user
            if let panel = attachments.entity(for: "controls") {
                panel.position = [0, 1.5, -1.2]
                content.add(panel)
            }
        } attachments: {
            Attachment(id: "controls") {
                SceneControlPanel(
                    sceneName: "Hammer (Arm)",
                    instruction: instructionText,
                    isReady: isTracking && !hasDropped,
                    hasDropped: hasDropped,
                    onDrop: dropCube,
                    onReset: resetScene,
                    onReturn: { await dismissImmersiveSpace() }
                )
            }
        }
        .task {
            await runHandTracking()
        }
    }

    private var instructionText: String {
        if let error = trackingError { return error }
        if !isTracking { return "Searching for your right hand…" }
        if hasDropped { return "The cube swung past your arm." }
        return "Hold your arm still. Tap Drop to release."
    }

    // MARK: - Hand Tracking

    private func runHandTracking() async {
        // Request hand tracking authorisation
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

        // Consume anchor updates – runs until the view disappears (task cancelled)
        for await update in handTracking.anchorUpdates {
            let anchor = update.anchor
            // We track the right hand; ignore the left
            guard anchor.chirality == .right, anchor.isTracked else { continue }

            // The anchor's origin sits at the wrist
            let t = anchor.originFromAnchorTransform
            let wristPos = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)

            armPosition = wristPos

            if !isTracking {
                // First successful track – create the cube
                isTracking = true
                setupCube(above: wristPos)
            } else if !hasDropped, let cube = cubeEntity {
                // Keep cube locked at the hover position while the arm moves (pre-drop)
                cube.position = cubeHoverPosition(for: wristPos)
            }
        }
    }

    // MARK: - Cube Management

    /// Hover position: upper-left of the arm.
    /// Positions the cube on the opposite side of the body from the landing spot,
    /// creating a natural swing arc when the drop is triggered.
    private func cubeHoverPosition(for pos: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(pos.x - 0.20, pos.y + startHeight, pos.z)
    }

    private func setupCube(above position: SIMD3<Float>) {
        let mesh = MeshResource.generateBox(size: cubeSize, cornerRadius: 0.004)
        let material = SimpleMaterial(color: .gray, roughness: 0.3, isMetallic: true)
        let cube = ModelEntity(mesh: mesh, materials: [material])
        cube.position = cubeHoverPosition(for: position)
        rootEntity.addChild(cube)
        cubeEntity = cube
    }

    private func dropCube() {
        guard let cube = cubeEntity, let armPos = armPosition else { return }
        hasDropped = true

        // Two-stage arc animation
        // Stage 1 (75 %): swing across body from upper-left to just above and beside arm
        // Stage 2 (25 %): quick snap past the arm to the landing spot (the "near-miss" moment)
        let swingTarget = SIMD3<Float>(armPos.x + nearMissOffset, armPos.y + 0.08, armPos.z)
        let landTarget  = SIMD3<Float>(armPos.x + nearMissOffset, armPos.y - 0.05, armPos.z)

        let swingDuration = dropDuration * 0.75
        let snapDuration  = dropDuration * 0.25

        var swingTransform = cube.transform
        swingTransform.translation = swingTarget
        cube.move(to: swingTransform, relativeTo: rootEntity, duration: swingDuration, timingFunction: .easeIn)

        let localRoot = rootEntity
        Task {
            try? await Task.sleep(nanoseconds: UInt64(swingDuration * 1_000_000_000))
            guard cube.parent != nil else { return }
            var landTransform = cube.transform
            landTransform.translation = landTarget
            cube.move(to: landTransform, relativeTo: localRoot, duration: snapDuration, timingFunction: .easeOut)
        }
    }

    private func resetScene() {
        cubeEntity?.removeFromParent()
        cubeEntity = nil
        hasDropped = false
        isTracking = false

        // Immediately re-attach if we still have a tracked position
        if let pos = armPosition {
            isTracking = true
            setupCube(above: pos)
        }
    }
}
