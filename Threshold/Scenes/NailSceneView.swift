//
//  NailSceneView.swift
//  Threshold
//
//  Immersive scene: "Nail in the Glove" — A nail appears to be hammered
//  through the user's gloved right hand. After the animation, the glove
//  fades to reveal the nail passed harmlessly between the fingers.
//
//  Based on the 1995 "nail in the boot" case study for pain neuroscience
//  education.
//

import SwiftUI
import RealityKit
import ARKit
import RealityKitContent

struct NailSceneView: View {

    @Environment(AppModel.self) var appModel
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace

    // MARK: - Scene State

    enum SceneState {
        case waitingForHand
        case gloveAppearing
        case ready
        case animating
        case revealing
        case educating
    }

    @State private var sceneState: SceneState = .waitingForHand

    // MARK: - Entity References

    @State private var rootEntity = Entity()
    @State private var gloveEntity: Entity?
    @State private var nailEntity: Entity?
    @State private var hammerEntity: Entity?

    // MARK: - Tracking State

    @State private var trackingError: String?
    @State private var fingersSpread = false

    /// Cached nail target position (midpoint between index and middle knuckles).
    @State private var nailPosition: SIMD3<Float> = .zero

    // MARK: - ARKit (declared as `let` — not @State)

    private let arSession = ARKitSession()
    private let handTracking = HandTrackingProvider()

    // MARK: - Constants

    /// Minimum distance (metres) between index and middle knuckles to count as "spread".
    private let spreadThreshold: Float = 0.04

    /// How far above the knuckle midpoint the nail starts (metres).
    private let nailHoverHeight: Float = 0.05

    /// How far above the nail the hammer hovers (metres).
    private let hammerHoverHeight: Float = 0.15

    /// How far the nail drives down during the strike (metres).
    private let nailDriveDistance: Float = 0.04

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
                    sceneName: "Nail in the Glove",
                    instruction: instructionText,
                    isReady: sceneState == .ready,
                    hasDropped: sceneState == .educating,
                    actionLabel: "Strike",
                    actionIcon: "hammer.fill",
                    onDrop: performStrike,
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
        case .waitingForHand:
            if !fingersSpread {
                return "Place your right hand flat on the table and spread your fingers wide."
            }
            return "Detecting hand…"
        case .gloveAppearing:
            return "Fitting glove…"
        case .ready:
            return "Hold still. Tap Strike when ready."
        case .animating:
            return "Striking…"
        case .revealing:
            return "Look at your hand…"
        case .educating:
            return "Check the main window for what just happened."
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

            // Always update glove position when glove is attached
            let wristJoint = skeleton.joint(.wrist)
            if wristJoint.isTracked, let glove = gloveEntity {
                let worldWristMatrix = anchor.originFromAnchorTransform * wristJoint.anchorFromJointTransform
                glove.setTransformMatrix(worldWristMatrix, relativeTo: nil)
            }

            // Check finger spread and compute nail position
            let indexKnuckle = skeleton.joint(.indexFingerKnuckle)
            let middleKnuckle = skeleton.joint(.middleFingerKnuckle)
            guard indexKnuckle.isTracked, middleKnuckle.isTracked else { continue }

            let indexWorld = anchor.originFromAnchorTransform * indexKnuckle.anchorFromJointTransform
            let middleWorld = anchor.originFromAnchorTransform * middleKnuckle.anchorFromJointTransform

            let indexPos = SIMD3<Float>(indexWorld.columns.3.x, indexWorld.columns.3.y, indexWorld.columns.3.z)
            let middlePos = SIMD3<Float>(middleWorld.columns.3.x, middleWorld.columns.3.y, middleWorld.columns.3.z)

            let knuckleDistance = simd_distance(indexPos, middlePos)
            fingersSpread = knuckleDistance > spreadThreshold

            // Midpoint between the two knuckles, slightly above the hand surface
            let midpoint = (indexPos + middlePos) / 2.0
            nailPosition = SIMD3<Float>(midpoint.x, midpoint.y + nailHoverHeight, midpoint.z)

            // State transitions
            switch sceneState {
            case .waitingForHand:
                if fingersSpread && wristJoint.isTracked {
                    sceneState = .gloveAppearing
                    await attachGlove()
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    await placeNailAndHammer()
                    sceneState = .ready
                }
            case .ready:
                // Update nail and hammer position to track hand until strike
                nailEntity?.position = nailPosition
                hammerEntity?.position = SIMD3<Float>(
                    nailPosition.x,
                    nailPosition.y + hammerHoverHeight,
                    nailPosition.z
                )
            default:
                break
            }
        }
    }

    // MARK: - Model Loading

    private func attachGlove() async {
        do {
            let glove = try await Entity(named: "Gloves", in: realityKitContentBundle)
            glove.components.set(OpacityComponent(opacity: 0))
            rootEntity.addChild(glove)
            gloveEntity = glove

            // Fade glove in over 0.5s
            let steps = 10
            let interval: UInt64 = 500_000_000 / UInt64(steps)
            for i in 1...steps {
                let opacity = Float(i) / Float(steps)
                glove.components.set(OpacityComponent(opacity: opacity))
                try? await Task.sleep(nanoseconds: interval)
            }
        } catch {
            trackingError = "Failed to load glove model: \(error.localizedDescription)"
        }
    }

    private func placeNailAndHammer() async {
        // Load nail
        do {
            let nail = try await Entity(named: "Nail", in: realityKitContentBundle)
            nail.position = nailPosition
            rootEntity.addChild(nail)
            nailEntity = nail
        } catch {
            trackingError = "Failed to load nail model: \(error.localizedDescription)"
            return
        }

        // Load hammer
        do {
            let hammer = try await Entity(named: "Immersive", in: realityKitContentBundle)
            hammer.position = SIMD3<Float>(
                nailPosition.x,
                nailPosition.y + hammerHoverHeight,
                nailPosition.z
            )
            rootEntity.addChild(hammer)
            hammerEntity = hammer
        } catch {
            trackingError = "Failed to load hammer model: \(error.localizedDescription)"
        }
    }

    // MARK: - Strike Animation

    private func performStrike() {
        guard sceneState == .ready,
              let hammer = hammerEntity,
              let nail = nailEntity else { return }

        sceneState = .animating

        let hammerStartPos = hammer.position
        let nailStartPos = nail.position

        // Target: hammer moves down to nail head level
        let hammerStrikePos = SIMD3<Float>(
            nailStartPos.x,
            nailStartPos.y + 0.02, // just above nail head
            nailStartPos.z
        )

        // Target: nail drives down
        let nailDrivenPos = SIMD3<Float>(
            nailStartPos.x,
            nailStartPos.y - nailDriveDistance,
            nailStartPos.z
        )

        Task {
            // 1. Hammer swings down (0.3s)
            hammer.move(
                to: Transform(translation: hammerStrikePos),
                relativeTo: rootEntity,
                duration: 0.3,
                timingFunction: .easeIn
            )
            try? await Task.sleep(nanoseconds: 300_000_000)

            // 2. Nail drives down (0.7s)
            nail.move(
                to: Transform(translation: nailDrivenPos),
                relativeTo: rootEntity,
                duration: 0.7,
                timingFunction: .easeOut
            )
            try? await Task.sleep(nanoseconds: 700_000_000)

            // 3. Hammer lifts back up (0.4s)
            hammer.move(
                to: Transform(translation: hammerStartPos),
                relativeTo: rootEntity,
                duration: 0.4,
                timingFunction: .easeOut
            )
            try? await Task.sleep(nanoseconds: 400_000_000)

            // 4. Pause for tension (0.6s)
            try? await Task.sleep(nanoseconds: 600_000_000)

            // 5. Reveal — fade glove out (1.0s)
            sceneState = .revealing
            await fadeGloveOut()

            // 6. Trigger education view
            sceneState = .educating
            appModel.showEducation = true
        }
    }

    // MARK: - Glove Fade

    private func fadeGloveOut() async {
        guard let glove = gloveEntity else { return }
        let steps = 20
        let interval: UInt64 = 1_000_000_000 / UInt64(steps) // 1s total
        for i in 1...steps {
            let opacity = 1.0 - Float(i) / Float(steps)
            glove.components.set(OpacityComponent(opacity: opacity))
            try? await Task.sleep(nanoseconds: interval)
        }
    }

    // MARK: - Reset

    private func resetScene() {
        gloveEntity?.removeFromParent()
        gloveEntity = nil
        nailEntity?.removeFromParent()
        nailEntity = nil
        hammerEntity?.removeFromParent()
        hammerEntity = nil
        fingersSpread = false
        sceneState = .waitingForHand
        appModel.showEducation = false
    }
}
