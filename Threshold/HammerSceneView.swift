//
//  HammerSceneView.swift
//  Threshold
//
//  Immersive scene: Uses ARKit hand tracking to detect the user's right arm,
//  positions the Immersive hammer model near the arm, and plays its baked
//  strike animation when triggered.
//

import SwiftUI
import RealityKit
import ARKit
import RealityKitContent

struct HammerSceneView: View {

    @Environment(AppModel.self) var appModel
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace

    // MARK: - State

    @State private var rootEntity = Entity()
    @State private var hammerEntity: Entity?
    @State private var armPosition: SIMD3<Float>?
    @State private var hasDropped = false
    @State private var isTracking = false
    @State private var trackingError: String?

    // MARK: - ARKit

    private let arSession = ARKitSession()
    private let handTracking = HandTrackingProvider()

    // MARK: - Body

    var body: some View {
        RealityView { (content: inout RealityViewContent, attachments: RealityViewAttachments) in
            content.add(rootEntity)

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
                    onDrop: dropHammer,
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
        if hasDropped { return "The hammer struck past your arm." }
        return "Hold your arm still. Tap Drop to release."
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

            let t = anchor.originFromAnchorTransform
            let wristPos = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)

            armPosition = wristPos

            if !isTracking {
                isTracking = true
                await setupHammer(near: wristPos)
            } else if !hasDropped, let hammer = hammerEntity {
                // Keep the hammer hovering relative to the arm before the drop
                hammer.position = hammerHoverPosition(for: wristPos)
            }
        }
    }

    // MARK: - Hammer Management

    /// Position just above and to the left of the wrist, as a natural start for a downward swing.
    private func hammerHoverPosition(for pos: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(pos.x - 0.20, pos.y + 0.45, pos.z)
    }

    private func setupHammer(near position: SIMD3<Float>) async {
        do {
            let scene = try await Entity(named: "Immersive", in: realityKitContentBundle)
            scene.position = hammerHoverPosition(for: position)
            rootEntity.addChild(scene)
            hammerEntity = scene
        } catch {
            trackingError = "Failed to load hammer model: \(error.localizedDescription)"
        }
    }

    private func dropHammer() {
        guard let hammer = hammerEntity else { return }
        hasDropped = true

        if let animation = hammer.availableAnimations.first {
            hammer.playAnimation(animation)
        }
    }

    private func resetScene() {
        hammerEntity?.removeFromParent()
        hammerEntity = nil
        hasDropped = false
        isTracking = false

        if let pos = armPosition {
            isTracking = true
            Task {
                await setupHammer(near: pos)
            }
        }
    }
}
