//
//  GlovesSceneView.swift
//  Threshold
//
//  Immersive scene: A leather work glove rigidly follows the user's right
//  wrist joint via ARKit hand tracking. No finger deformation — MVP rigid
//  body attachment only.
//

import SwiftUI
import RealityKit
import ARKit
import RealityKitContent

struct GlovesSceneView: View {

    @Environment(AppModel.self) var appModel
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace

    // MARK: - State

    @State private var rootEntity = Entity()
    @State private var gloveEntity: Entity?
    @State private var isTracking = false
    @State private var trackingError: String?

    // MARK: - ARKit (declared as `let` — not @State)

    private let arSession = ARKitSession()
    private let handTracking = HandTrackingProvider()

    // MARK: - Body

    var body: some View {
        RealityView { (content: inout RealityViewContent, attachments: RealityViewAttachments) in
            content.add(rootEntity)

            // Load glove model on first RealityView build
            do {
                let glove = try await Entity(named: "Gloves", in: realityKitContentBundle)
                rootEntity.addChild(glove)
                gloveEntity = glove
            } catch {
                trackingError = "Failed to load glove model: \(error.localizedDescription)"
            }

            if let panel = attachments.entity(for: "controls") {
                panel.position = [0, 1.5, -1.2]
                content.add(panel)
            }
        } attachments: {
            Attachment(id: "controls") {
                SceneControlPanel(
                    sceneName: "The Glove",
                    instruction: instructionText,
                    isReady: false,          // No action button — purely visual
                    hasDropped: false,       // Never enters post-action state
                    onDrop: { },             // No-op
                    onReset: { },            // No-op
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
        return "The glove follows your wrist."
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
            let wristJoint = skeleton.joint(.wrist)
            guard wristJoint.isTracked else { continue }

            // Compute wrist world-space transform:
            // originFromAnchorTransform × anchorFromJointTransform
            let worldWristMatrix = anchor.originFromAnchorTransform * wristJoint.anchorFromJointTransform

            isTracking = true

            // Attach glove to wrist position in world space
            gloveEntity?.setTransformMatrix(worldWristMatrix, relativeTo: nil)
        }
    }
}
