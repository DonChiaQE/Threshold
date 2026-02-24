//
//  HammerSceneView.swift
//  Threshold
//
//  Immersive scene: Uses ARKit hand tracking to detect the user's right arm,
//  positions a cube (placeholder hammer) above the arm, and drops it beside
//  the arm as a near-miss.
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
    private let nearMissOffset: Float = 0.08
    /// Height above the arm where the cube starts (metres).
    private let startHeight: Float = 0.40
    /// Cube edge length (metres).
    private let cubeSize: Float = 0.08
    /// Duration of the drop animation (seconds).
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
        if hasDropped { return "The cube missed your arm." }
        return "Hold your arm still. Tap Drop when ready."
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
                // Keep cube locked above the arm while it moves (pre-drop)
                cube.position = cubeStartPosition(above: wristPos)
            }
        }
    }

    // MARK: - Cube Management

    private func cubeStartPosition(above pos: SIMD3<Float>) -> SIMD3<Float> {
        // Offset laterally (positive X = user's right) and above the arm
        SIMD3<Float>(pos.x + nearMissOffset, pos.y + startHeight, pos.z)
    }

    private func setupCube(above position: SIMD3<Float>) {
        let mesh = MeshResource.generateBox(size: cubeSize, cornerRadius: 0.004)
        let material = SimpleMaterial(color: .gray, roughness: 0.3, isMetallic: true)
        let cube = ModelEntity(mesh: mesh, materials: [material])
        cube.position = cubeStartPosition(above: position)
        rootEntity.addChild(cube)
        cubeEntity = cube
    }

    private func dropCube() {
        guard let cube = cubeEntity, let armPos = armPosition else { return }
        hasDropped = true

        // Target: arm height, offset to the side so it visibly misses
        let target = SIMD3<Float>(
            armPos.x + nearMissOffset,
            armPos.y - 0.05,   // slightly below wrist level
            armPos.z
        )

        var dropTransform = cube.transform
        dropTransform.translation = target
        cube.move(to: dropTransform, relativeTo: rootEntity, duration: dropDuration, timingFunction: .easeIn)
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
