//
//  DumbbellLiftSceneView.swift
//  Threshold
//
//  Immersive scene: A dumbbell sits on the floor. The user brings their
//  hand to a green orb above the handle and clenches to pick it up.
//  Educational goal: "Your body is strong enough — lifting is safe."
//

import SwiftUI
import RealityKit
import RealityKitContent
import ARKit
import AVFoundation

struct DumbbellLiftSceneView: View {

    @Environment(AppModel.self) var appModel
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace

    // MARK: - State

    @State private var rootEntity = Entity()
    @State private var dumbbellEntity: Entity?
    @State private var orbEntity: ModelEntity?
    @State private var isPickedUp = false
    @State private var handInProximity = false
    @State private var showLabel = false
    @State private var trackingError: String?
    @State private var orbPosition: SIMD3<Float> = [0, 0.35, -0.8]
    @State private var orbFloorY: Float = 0.35
    @State private var floorCenter: SIMD3<Float> = [0, 0, -0.8]
    @State private var floorPlaced = false
    @State private var speechSynthesizer = AVSpeechSynthesizer()

    // MARK: - Constants

    private let pickupProximity: Float = 0.20
    private let fistThreshold: Float = 0.12

    // MARK: - ARKit (let, not @State)

    private let arSession = ARKitSession()
    private let handTracking = HandTrackingProvider()
    private let planeDetection = PlaneDetectionProvider(alignments: [.horizontal])

    // MARK: - Body

    var body: some View {
        RealityView { (content: inout RealityViewContent, attachments: RealityViewAttachments) in
            content.add(rootEntity)

            // Load Dumbbell model
            do {
                let dumbbell = try await Entity(named: "Dumbbell", in: realityKitContentBundle)
                dumbbell.position = floorCenter
                rootEntity.addChild(dumbbell)
                dumbbellEntity = dumbbell

                // Measure bounds and position orb above the handle
                let bounds = dumbbell.visualBounds(relativeTo: nil)
                let boundsHeight = bounds.max.y - bounds.min.y
                if boundsHeight > 0.01 {
                    orbPosition = SIMD3<Float>(floorCenter.x, floorCenter.y + boundsHeight * 0.15, floorCenter.z)
                }
            } catch {
                trackingError = "Failed to load dumbbell: \(error.localizedDescription)"
            }

            // Green interaction orb — floats above dumbbell
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
                    sceneName: "Dumbbell Lift",
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
                Text("Your body is strong enough.\nLifting is safe.")
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

            async let fallback: Void = {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if !floorPlaced { floorPlaced = true }
            }()

            async let tracking: Void = runHandTracking()
            async let planes: Void = runPlaneDetection()

            _ = await (fallback, tracking, planes)
        }
    }

    // MARK: - Instruction Text

    private var instructionText: String {
        if let error = trackingError { return error }
        if isPickedUp { return "You lifted it. Tap Reset to try again." }
        if handInProximity { return "Now clench your hand to grip the dumbbell." }
        return "Bring your hand to the green orb above the dumbbell and grip to pick it up."
    }

    // MARK: - Orb Builder

    private func makeOrb() -> ModelEntity {
        let mesh = MeshResource.generateSphere(radius: 0.03)
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
            floorPlaced = true
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
            guard !floorPlaced else { return }

            let anchor = update.anchor
            guard update.event == .added || update.event == .updated else { continue }

            let transform = anchor.originFromAnchorTransform
            let center = SIMD3<Float>(
                transform.columns.3.x,
                transform.columns.3.y,
                transform.columns.3.z
            )

            guard center.y < 0.3 && center.y > -0.1 else { continue }
            guard center.z < -0.3 && center.z > -1.5 else { continue }

            guard let dumbbell = dumbbellEntity else { continue }

            // Snap dumbbell base to floor
            dumbbell.position = center
            let worldBounds = dumbbell.visualBounds(relativeTo: nil)
            let boundsHeight = worldBounds.max.y - worldBounds.min.y
            if boundsHeight > 0.01 {
                dumbbell.position.y += center.y - worldBounds.min.y
            }

            floorCenter = dumbbell.position

            // Orb above dumbbell top
            let topY = dumbbell.position.y + (boundsHeight > 0.01 ? boundsHeight : 0.3)
            let newOrbPos = SIMD3<Float>(center.x, topY, center.z)
            orbPosition = newOrbPos
            orbFloorY = newOrbPos.y
            orbEntity?.position = newOrbPos

            floorPlaced = true
            return
        }
    }

    // MARK: - Hand Tracking

    private func runHandTracking() async {
        for await update in handTracking.anchorUpdates {
            let anchor = update.anchor
            guard anchor.isTracked else { continue }
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

            // Grip center (middle finger knuckle)
            let knuckleJoint = skeleton.joint(.middleFingerKnuckle)
            let gripPos: SIMD3<Float>
            if knuckleJoint.isTracked {
                let knuckleMatrix = anchor.originFromAnchorTransform * knuckleJoint.anchorFromJointTransform
                gripPos = SIMD3<Float>(knuckleMatrix.columns.3.x, knuckleMatrix.columns.3.y, knuckleMatrix.columns.3.z)
            } else {
                gripPos = wristPos
            }

            // If already picked up, track dumbbell + orb to wrist or release on unclench
            if isPickedUp {
                let carriedPos = wristPos + SIMD3<Float>(0, -0.08, 0)
                let carriedOrbPos = wristPos + SIMD3<Float>(0, -0.03, 0)

                let fingerPairs: [(HandSkeleton.JointName, HandSkeleton.JointName)] = [
                    (.indexFingerTip, .indexFingerMetacarpal),
                    (.middleFingerTip, .middleFingerMetacarpal),
                    (.ringFingerTip, .ringFingerMetacarpal),
                    (.littleFingerTip, .littleFingerMetacarpal)
                ]
                let stillFist = fingerPairs.filter { (tipName, mcName) in
                    let tipJoint = skeleton.joint(tipName)
                    let mcJoint = skeleton.joint(mcName)
                    guard tipJoint.isTracked, mcJoint.isTracked else { return true }
                    let tipMatrix = anchor.originFromAnchorTransform * tipJoint.anchorFromJointTransform
                    let mcMatrix = anchor.originFromAnchorTransform * mcJoint.anchorFromJointTransform
                    let tipPos = SIMD3<Float>(tipMatrix.columns.3.x, tipMatrix.columns.3.y, tipMatrix.columns.3.z)
                    let mcPos = SIMD3<Float>(mcMatrix.columns.3.x, mcMatrix.columns.3.y, mcMatrix.columns.3.z)
                    return simd_distance(tipPos, mcPos) < fistThreshold
                }.count >= 2

                if !stillFist {
                    // Drop dumbbell at current XZ, back to floor height
                    let dropPos = SIMD3<Float>(carriedPos.x, floorCenter.y, carriedPos.z)
                    let dropOrbPos = SIMD3<Float>(carriedPos.x, orbFloorY, carriedPos.z)
                    isPickedUp = false
                    handInProximity = false
                    orbPosition = dropOrbPos
                    dumbbellEntity?.position = dropPos
                    orbEntity?.position = dropOrbPos
                    orbEntity?.transform.scale = [1, 1, 1]
                    continue
                }

                dumbbellEntity?.position = carriedPos
                orbEntity?.position = carriedOrbPos
                continue
            }

            // Proximity check: grip center to orb
            let distToOrb = simd_distance(gripPos, orbPosition)
            let nowInProximity = distToOrb < pickupProximity

            if nowInProximity != handInProximity {
                handInProximity = nowInProximity
                pulseOrb(grow: nowInProximity)
            }

            guard nowInProximity else { continue }

            // Fist detection
            let fingerPairs: [(HandSkeleton.JointName, HandSkeleton.JointName)] = [
                (.indexFingerTip, .indexFingerMetacarpal),
                (.middleFingerTip, .middleFingerMetacarpal),
                (.ringFingerTip, .ringFingerMetacarpal),
                (.littleFingerTip, .littleFingerMetacarpal)
            ]
            let curledCount = fingerPairs.filter { (tipName, mcName) in
                let tipJoint = skeleton.joint(tipName)
                let mcJoint = skeleton.joint(mcName)
                guard tipJoint.isTracked, mcJoint.isTracked else { return false }
                let tipMatrix = anchor.originFromAnchorTransform * tipJoint.anchorFromJointTransform
                let mcMatrix = anchor.originFromAnchorTransform * mcJoint.anchorFromJointTransform
                let tipPos = SIMD3<Float>(tipMatrix.columns.3.x, tipMatrix.columns.3.y, tipMatrix.columns.3.z)
                let mcPos = SIMD3<Float>(mcMatrix.columns.3.x, mcMatrix.columns.3.y, mcMatrix.columns.3.z)
                return simd_distance(tipPos, mcPos) < fistThreshold
            }.count
            let isFist = curledCount >= 2

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
                string: "Your body is strong enough. Lifting is safe."
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

        dumbbellEntity?.position = floorCenter

        orbEntity?.isEnabled = true
        orbEntity?.transform.scale = [1, 1, 1]
        orbPosition = SIMD3<Float>(floorCenter.x, orbFloorY, floorCenter.z)
        orbEntity?.position = orbPosition
    }
}
