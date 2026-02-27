//
//  CactusSceneView.swift
//  Threshold
//
//  Immersive scene: A cactus sits at arm's reach. When the user brings any
//  right-hand fingertip within 6 cm, a red glow appears (threat prediction),
//  then shifts to green (safety reappraisal), teaching that hurt ≠ harm.
//
//  Audio: Drop a file named "prick.wav" into the Xcode target to enable the
//  puncture sound. The scene works without it.
//

import SwiftUI
import RealityKit
import ARKit
import RealityKitContent
import AVFoundation

struct CactusSceneView: View {

    @Environment(AppModel.self) var appModel
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace

    // MARK: - State

    @State private var rootEntity = Entity()
    @State private var cactusEntity: Entity?
    @State private var redGlowEntity: ModelEntity?
    @State private var greenGlowEntity: ModelEntity?
    @State private var gloveEntity: Entity?
    @State private var hasTriggered = false
    @State private var showSafeLabel = false
    @State private var trackingError: String?

    // MARK: - Constants

    private let cactusPosition: SIMD3<Float> = [0, 1.0, -0.6]
    private let triggerDistance: Float = 0.06  // metres

    // MARK: - ARKit (declared as `let` — not @State)

    private let arSession = ARKitSession()
    private let handTracking = HandTrackingProvider()

    // MARK: - Body

    var body: some View {
        RealityView { (content: inout RealityViewContent, attachments: RealityViewAttachments) in
            content.add(rootEntity)

            // Load cactus model
            do {
                let cactus = try await Entity(named: "Cactus", in: realityKitContentBundle)
                cactus.position = cactusPosition
                rootEntity.addChild(cactus)
                cactusEntity = cactus
            } catch {
                trackingError = "Failed to load cactus model: \(error.localizedDescription)"
            }

            // Load glove model — follows right wrist via hand tracking
            do {
                let glove = try await Entity(named: "Gloves", in: realityKitContentBundle)
                rootEntity.addChild(glove)
                gloveEntity = glove
            } catch {
                // Glove load failure is non-fatal; scene still works without it
            }

            // Pre-build glow spheres — hidden until triggered
            let redGlow = makeGlowSphere(color: UIColor.red.withAlphaComponent(0.6))
            redGlow.position = cactusPosition
            redGlow.isEnabled = false
            rootEntity.addChild(redGlow)
            redGlowEntity = redGlow

            let greenGlow = makeGlowSphere(
                color: UIColor(red: 0.2, green: 0.9, blue: 0.4, alpha: 0.5)
            )
            greenGlow.position = cactusPosition
            greenGlow.isEnabled = false
            rootEntity.addChild(greenGlow)
            greenGlowEntity = greenGlow

            // Control panel
            if let panel = attachments.entity(for: "controls") {
                panel.position = [0, 1.5, -1.2]
                content.add(panel)
            }

            // Safe label — always present, opacity driven by showSafeLabel state
            if let label = attachments.entity(for: "safeLabel") {
                label.position = [0, 1.3, -0.6]
                content.add(label)
            }
        } attachments: {
            Attachment(id: "controls") {
                SceneControlPanel(
                    sceneName: "The Cactus",
                    instruction: instructionText,
                    isReady: false,
                    hasDropped: hasTriggered,
                    resetLabel: "Reset",
                    onDrop: { },
                    onReset: resetScene,
                    onReturn: { await dismissImmersiveSpace() }
                )
            }

            Attachment(id: "safeLabel") {
                Text("Your skin is safe.\nYour brain just predicted danger.")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(20)
                    .frame(maxWidth: 320)
                    .glassBackgroundEffect()
                    .opacity(showSafeLabel ? 1 : 0)
            }
        }
        .task {
            await runHandTracking()
        }
    }

    private var instructionText: String {
        if let error = trackingError { return error }
        if hasTriggered { return "Your skin is safe. Tap Reset to try again." }
        return "Move your right hand toward the cactus."
    }

    // MARK: - Glow Entity Builder

    private func makeGlowSphere(color: UIColor) -> ModelEntity {
        let mesh = MeshResource.generateSphere(radius: 0.15)
        let material = SimpleMaterial(
            color: color,
            roughness: 1.0,
            isMetallic: false
        )
        return ModelEntity(mesh: mesh, materials: [material])
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

        // Fingertip joints to monitor
        let tipJoints: [HandSkeleton.JointName] = [
            .indexFingerTip,
            .middleFingerTip,
            .ringFingerTip,
            .littleFingerTip,
            .thumbTip
        ]

        for await update in handTracking.anchorUpdates {
            let anchor = update.anchor
            guard anchor.chirality == .right, anchor.isTracked else { continue }
            guard let skeleton = anchor.handSkeleton else { continue }

            // Always update glove position — runs even after trigger fires
            let wristJoint = skeleton.joint(.wrist)
            if wristJoint.isTracked {
                let worldWristMatrix = anchor.originFromAnchorTransform * wristJoint.anchorFromJointTransform
                gloveEntity?.setTransformMatrix(worldWristMatrix, relativeTo: nil)
            }

            // Proximity check only needed before trigger
            guard !hasTriggered else { continue }

            for jointName in tipJoints {
                let joint = skeleton.joint(jointName)
                guard joint.isTracked else { continue }

                // World-space tip position
                let worldMatrix = anchor.originFromAnchorTransform * joint.anchorFromJointTransform
                let tipPos = SIMD3<Float>(
                    worldMatrix.columns.3.x,
                    worldMatrix.columns.3.y,
                    worldMatrix.columns.3.z
                )

                let dist = simd_distance(tipPos, cactusPosition)
                if dist < triggerDistance {
                    triggerSequence()
                    break
                }
            }
        }
    }

    // MARK: - Sequence

    private func triggerSequence() {
        guard !hasTriggered else { return }
        hasTriggered = true

        Task {
            // Play prick sound (optional — requires "prick.wav" in bundle)
            if let url = Bundle.main.url(forResource: "prick", withExtension: "wav") {
                let player = try? AVAudioPlayer(contentsOf: url)
                player?.play()
                // Retain player for duration of playback
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }

        Task {
            await animateRedGlow()
            try? await Task.sleep(nanoseconds: 1_500_000_000)  // 1.5 s pause
            await animateGreenGlow()
            showSafeLabel = true
            try? await Task.sleep(nanoseconds: 3_000_000_000)  // 3 s display
            showSafeLabel = false
        }
    }

    // MARK: - Glow Animations

    /// Show red glow for 0.3 s, then leave it on until animateGreenGlow runs.
    private func animateRedGlow() async {
        guard let entity = redGlowEntity else { return }
        entity.isEnabled = true
        try? await Task.sleep(nanoseconds: 300_000_000)
    }

    /// Hide red glow, show green glow for the reappraisal beat.
    private func animateGreenGlow() async {
        guard let red = redGlowEntity, let green = greenGlowEntity else { return }
        red.isEnabled = false
        green.isEnabled = true
    }

    // MARK: - Reset

    private func resetScene() {
        redGlowEntity?.isEnabled = false
        greenGlowEntity?.isEnabled = false
        showSafeLabel = false
        hasTriggered = false
    }
}
