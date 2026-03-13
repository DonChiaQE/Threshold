//
//  SackSceneView.swift
//  Threshold
//
//  Immersive scene: A grocery sack sits on the floor. The user brings their
//  right hand to a green orb above the sack and clenches (fist) to pick it up.
//  On pickup, an encouragement message is narrated and displayed.
//  Educational goal: exposure therapy for upper-body movement fear.
//

import SwiftUI
import RealityKit
import ARKit
import RealityKitContent
import AVFoundation

struct SackSceneView: View {

    @Environment(AppModel.self) var appModel
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace

    // MARK: - State

    @State private var rootEntity = Entity()
    @State private var sackEntity: Entity?
    @State private var orbEntity: ModelEntity?
    @State private var sackPlaced = false
    @State private var isPickedUp = false
    @State private var handInProximity = false
    @State private var showLabel = false
    @State private var trackingError: String?
    /// World-space position of the green orb. Updated on drop so re-pickup targets current location.
    @State private var orbPosition: SIMD3<Float> = [0, 0.65, -0.8]
    /// Y of the orb when the sack is resting on the floor. Set once after plane snap, never changed.
    @State private var orbFloorY: Float = 0.65
    /// Floor-level position of the sack origin. Used to restore on reset.
    @State private var floorCenter: SIMD3<Float> = [0, 0, -0.8]
    @State private var speechSynthesizer = AVSpeechSynthesizer()

    // MARK: - Constants

    private let pickupProximity: Float = 0.20   // metres — wrist to orb
    private let fistThreshold: Float  = 0.08   // metres — fingertip to own metacarpal (straight ~14 cm, fist ~6-8 cm)

    // MARK: - ARKit (declared as `let` — not @State)

    private let arSession      = ARKitSession()
    private let handTracking   = HandTrackingProvider()
    private let planeDetection = PlaneDetectionProvider(alignments: [.horizontal])

    // MARK: - Body

    var body: some View {
        RealityView { (content: inout RealityViewContent, attachments: RealityViewAttachments) in
            content.add(rootEntity)

            // Load sack model
            do {
                let sack = try await Entity(named: "Sack", in: realityKitContentBundle)
                sack.position = floorCenter
                rootEntity.addChild(sack)
                sackEntity = sack

                // Set fallback orb position based on actual model height
                let bounds = sack.visualBounds(relativeTo: nil)
                let boundsHeight = bounds.max.y - bounds.min.y
                if boundsHeight > 0.01 {
                    orbPosition = SIMD3<Float>(floorCenter.x, floorCenter.y + boundsHeight + 0.15, floorCenter.z)
                }
            } catch {
                trackingError = "Failed to load sack: \(error.localizedDescription)"
            }

            // Green interaction orb — floats above sack top
            let orb = makeOrb()
            orb.position = orbPosition
            rootEntity.addChild(orb)
            orbEntity = orb

            // Control panel
            if let panel = attachments.entity(for: "controls") {
                panel.position = [-0.7, 1.5, -1.0]
                content.add(panel)
            }

            // Encouragement label
            if let label = attachments.entity(for: "encouragement") {
                label.position = [0, 1.6, -1.2]
                content.add(label)
            }
        } attachments: {
            Attachment(id: "controls") {
                SceneControlPanel(
                    sceneName: "The Grocery Bag",
                    instruction: instructionText,
                    isReady: false,
                    hasDropped: isPickedUp,
                    resetLabel: "Reset",
                    onDrop: { },
                    onReset: resetScene,
                    onReturn: { await dismissImmersiveSpace() }
                )
            }

            Attachment(id: "encouragement") {
                Text("You did it.\nYour body carried the weight.\nPain anticipated is not always pain caused.")
                    .font(.title.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(28)
                    .frame(maxWidth: 520)
                    .glassBackgroundEffect()
                    .opacity(showLabel ? 1 : 0)
            }
        }
        .task {
            await startARSession()

            // Fallback: if no floor found in 3 s, keep hardcoded position
            async let fallback: Void = {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if !sackPlaced { sackPlaced = true }
            }()

            async let tracking: Void = runHandTracking()
            async let planes: Void   = runPlaneDetection()

            _ = await (fallback, tracking, planes)
        }
    }

    // MARK: - Instruction Text

    private var instructionText: String {
        if let error = trackingError { return error }
        if isPickedUp { return "You lifted it. Tap Reset to try again." }
        if handInProximity { return "Now clench your hand to grip the bag." }
        return "Bring your right hand to the green orb above the bag and grip to pick it up."
    }

    // MARK: - Orb Builder

    private func makeOrb() -> ModelEntity {
        let mesh = MeshResource.generateSphere(radius: 0.05)
        let material = SimpleMaterial(
            color: UIColor(red: 0.2, green: 0.9, blue: 0.4, alpha: 0.7),
            roughness: 1.0,
            isMetallic: false
        )
        return ModelEntity(mesh: mesh, materials: [material])
    }

    // MARK: - Session Setup

    private func startARSession() async {
        let auth = await arSession.requestAuthorization(for: [.handTracking, .worldSensing])
        guard auth[.handTracking] == .allowed else {
            trackingError = "Hand tracking permission denied. Please enable it in Settings."
            return
        }
        if auth[.worldSensing] != .allowed {
            sackPlaced = true
        }
        do {
            if auth[.worldSensing] == .allowed {
                try await arSession.run([handTracking, planeDetection])
            } else {
                try await arSession.run([handTracking])
            }
        } catch {
            trackingError = "Tracking unavailable: \(error.localizedDescription)"
        }
    }

    // MARK: - Plane Detection (floor)

    private func runPlaneDetection() async {
        for await update in planeDetection.anchorUpdates {
            guard !sackPlaced else { return }

            let anchor = update.anchor
            guard update.event == .added || update.event == .updated else { continue }

            let transform = anchor.originFromAnchorTransform
            let center = SIMD3<Float>(
                transform.columns.3.x,
                transform.columns.3.y,
                transform.columns.3.z
            )

            // Floor plane: y near 0, in front of user
            guard center.y < 0.3 && center.y > -0.1 else { continue }
            guard center.z < -0.3 && center.z > -1.5 else { continue }

            guard let sack = sackEntity else { continue }

            // Snap sack base to floor surface
            sack.position = center
            let worldBounds = sack.visualBounds(relativeTo: nil)
            let boundsHeight = worldBounds.max.y - worldBounds.min.y
            if boundsHeight > 0.01 {
                sack.position.y += center.y - worldBounds.min.y
            }

            // Store floor position for reset
            floorCenter = sack.position

            // Orb: 15 cm above sack top
            let sackTopY = sack.position.y + (boundsHeight > 0.01 ? boundsHeight : 0.5)
            let newOrbPos = SIMD3<Float>(center.x, sackTopY + 0, center.z)
            orbPosition = newOrbPos
            orbFloorY = newOrbPos.y
            orbEntity?.position = newOrbPos

            sackPlaced = true
            return
        }
    }

    // MARK: - Hand Tracking

    private func runHandTracking() async {
        for await update in handTracking.anchorUpdates {
            let anchor = update.anchor
            guard anchor.chirality == .right, anchor.isTracked else { continue }
            guard let skeleton = anchor.handSkeleton else { continue }

            // Wrist world position
            let wristJoint = skeleton.joint(.wrist)
            guard wristJoint.isTracked else { continue }
            let wristMatrix = anchor.originFromAnchorTransform * wristJoint.anchorFromJointTransform
            let wristPos = SIMD3<Float>(
                wristMatrix.columns.3.x,
                wristMatrix.columns.3.y,
                wristMatrix.columns.3.z
            )

            // If already picked up, track sack + orb to wrist or release on unclench
            if isPickedUp {
                let carriedSackPos = wristPos + SIMD3<Float>(0, -0.40, 0)
                // Orb follows the grip point so user can see where to re-grab
                let carriedOrbPos  = wristPos + SIMD3<Float>(0,  0.05, 0)

                let fingerPairs: [(HandSkeleton.JointName, HandSkeleton.JointName)] = [
                    (.indexFingerTip,  .indexFingerMetacarpal),
                    (.middleFingerTip, .middleFingerMetacarpal),
                    (.ringFingerTip,   .ringFingerMetacarpal),
                    (.littleFingerTip, .littleFingerMetacarpal)
                ]
                // Same per-finger curl detection; lenient (untracked = still holding) to avoid jitter
                do {
                    let stillFist = fingerPairs.filter { (tipName, mcName) in
                        let tipJoint = skeleton.joint(tipName)
                        let mcJoint  = skeleton.joint(mcName)
                        guard tipJoint.isTracked, mcJoint.isTracked else { return true }
                        let tipMatrix = anchor.originFromAnchorTransform * tipJoint.anchorFromJointTransform
                        let mcMatrix  = anchor.originFromAnchorTransform * mcJoint.anchorFromJointTransform
                        let tipPos = SIMD3<Float>(tipMatrix.columns.3.x, tipMatrix.columns.3.y, tipMatrix.columns.3.z)
                        let mcPos  = SIMD3<Float>(mcMatrix.columns.3.x,  mcMatrix.columns.3.y,  mcMatrix.columns.3.z)
                        return simd_distance(tipPos, mcPos) < fistThreshold
                    }.count >= 3
                    if !stillFist {
                        // Sack drops to floor at the XZ position where it was released
                        let dropSackPos = SIMD3<Float>(carriedSackPos.x, floorCenter.y, carriedSackPos.z)
                        let dropOrbPos  = SIMD3<Float>(carriedSackPos.x, orbFloorY,     carriedSackPos.z)
                        isPickedUp = false
                        handInProximity = false
                        orbPosition = dropOrbPos
                        sackEntity?.position = dropSackPos
                        orbEntity?.position  = dropOrbPos
                        orbEntity?.transform.scale = [1, 1, 1]
                        continue
                    }
                }
                sackEntity?.position = carriedSackPos
                orbEntity?.position  = carriedOrbPos
                continue
            }

            // Proximity check: wrist to orb
            let distToOrb = simd_distance(wristPos, orbPosition)
            let nowInProximity = distToOrb < pickupProximity

            if nowInProximity != handInProximity {
                handInProximity = nowInProximity
                pulseOrb(grow: nowInProximity)
            }

            guard nowInProximity else { continue }

            // Fist detection: each finger's tip vs its own metacarpal.
            // This is orientation-independent — Euclidean distance is invariant under rotation,
            // so palm-up, palm-down, and palm-inward all produce the same curl measurement.
            let fingerPairs: [(HandSkeleton.JointName, HandSkeleton.JointName)] = [
                (.indexFingerTip,  .indexFingerMetacarpal),
                (.middleFingerTip, .middleFingerMetacarpal),
                (.ringFingerTip,   .ringFingerMetacarpal),
                (.littleFingerTip, .littleFingerMetacarpal)
            ]
            let curledCount = fingerPairs.filter { (tipName, mcName) in
                let tipJoint = skeleton.joint(tipName)
                let mcJoint  = skeleton.joint(mcName)
                guard tipJoint.isTracked, mcJoint.isTracked else { return false }
                let tipMatrix = anchor.originFromAnchorTransform * tipJoint.anchorFromJointTransform
                let mcMatrix  = anchor.originFromAnchorTransform * mcJoint.anchorFromJointTransform
                let tipPos = SIMD3<Float>(tipMatrix.columns.3.x, tipMatrix.columns.3.y, tipMatrix.columns.3.z)
                let mcPos  = SIMD3<Float>(mcMatrix.columns.3.x,  mcMatrix.columns.3.y,  mcMatrix.columns.3.z)
                return simd_distance(tipPos, mcPos) < fistThreshold
            }.count
            let isFist = curledCount >= 3

            if isFist {
                triggerPickup()
            }
        }
    }

    // MARK: - Orb Pulse

    private func pulseOrb(grow: Bool) {
        guard let orb = orbEntity else { return }
        let scale: Float = grow ? 1.3 : 1.0
        let target = Transform(
            scale: [scale, scale, scale],
            rotation: orb.transform.rotation,
            translation: orb.position
        )
        orb.move(to: target, relativeTo: nil, duration: 0.3, timingFunction: .easeInOut)
    }

    // MARK: - Pickup Trigger

    private func triggerPickup() {
        guard !isPickedUp else { return }
        isPickedUp = true

        Task {
            withAnimation(.easeIn(duration: 0.6)) { showLabel = true }
            let utterance = AVSpeechUtterance(
                string: "You did it. Your body carried the weight. Pain anticipated is not always pain caused."
            )
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85
            speechSynthesizer.speak(utterance)
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            withAnimation(.easeOut(duration: 0.4)) { showLabel = false }
        }
    }

    // MARK: - Reset

    private func resetScene() {
        speechSynthesizer.stopSpeaking(at: .immediate)
        isPickedUp = false
        handInProximity = false
        showLabel = false

        // Restore sack to floor
        sackEntity?.position = floorCenter

        // Restore orb
        orbEntity?.isEnabled = true
        orbEntity?.transform.scale = [1, 1, 1]
        orbEntity?.position = orbPosition
    }
}
