# Box Lift Scene Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new "Box Lift" immersive scene where the user picks up a procedural cube from the floor using two-handed grip (two green orbs) and places it on a detected elevated surface.

**Architecture:** Self-contained `BoxLiftSceneView.swift` following the existing scene-per-file pattern. Registers via `AppModel.SceneType` and `ImmersiveSpace`. Uses `HandTrackingProvider` (both hands) and `PlaneDetectionProvider` for floor + elevated surface detection. Interaction is a gripCount-based state machine (0/1/2 hands gripping).

**Tech Stack:** SwiftUI, RealityKit, ARKit (HandTrackingProvider, PlaneDetectionProvider), AVFoundation (speech)

**Spec:** `docs/superpowers/specs/2026-03-24-box-lift-scene-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `Threshold/App/AppModel.swift` | Modify (lines 18-51) | Add `.boxLift` case to `SceneType` enum |
| `Threshold/App/ThresholdApp.swift` | Modify (lines 60-71) | Register `ImmersiveSpace(id: "BoxLiftScene")` |
| `Threshold/Scenes/BoxLiftSceneView.swift` | Create | Self-contained scene view with all interaction logic |

`ContentView.swift` needs no changes — it iterates `SceneType.allCases` automatically.

---

### Task 1: Register BoxLift in AppModel

**Files:**
- Modify: `Threshold/App/AppModel.swift:18-51`

- [ ] **Step 1: Add `.boxLift` case to SceneType enum**

In `AppModel.swift`, add the new case after `.sack`:

```swift
// In enum SceneType (line 22, after `case sack = "SackScene"`):
case boxLift = "BoxLiftScene"
```

Add to each computed property switch:

```swift
// In var title (after case .sack):
case .boxLift: "The Box Lift"

// In var subtitle (after case .sack):
case .boxLift: "Lift a box from the floor to a surface — movement is safe"

// In var systemImage (after case .sack):
case .boxLift: "shippingbox.fill"
```

- [ ] **Step 2: Verify the app still compiles**

Open Xcode, build for visionOS Simulator (Cmd+B). Expected: build succeeds (ContentView picks up the new case automatically via `allCases`). There will be a missing `BoxLiftSceneView` reference in the next task, so the ImmersiveSpace registration will be added after the view exists.

- [ ] **Step 3: Commit**

```bash
git add Threshold/App/AppModel.swift
git commit -m "feat: add boxLift case to AppModel.SceneType"
```

---

### Task 2: Create BoxLiftSceneView — Skeleton + Entities

**Files:**
- Create: `Threshold/Scenes/BoxLiftSceneView.swift`

- [ ] **Step 1: Create the scene view file with all state properties and entity setup**

Create `Threshold/Scenes/BoxLiftSceneView.swift` with the full skeleton. This includes: imports, state properties, ARKit providers, the `RealityView` body with entity creation (box, two orbs, target zone), attachments (control panel + encouragement label), and stub functions for tracking.

```swift
//
//  BoxLiftSceneView.swift
//  Threshold
//
//  Immersive scene: A box sits on the floor. The user grips both sides
//  (two green orbs) to lift it, then places it on a detected elevated surface.
//  Educational goal: "Lifting is safe when done with confidence."
//

import SwiftUI
import RealityKit
import ARKit
import AVFoundation

struct BoxLiftSceneView: View {

    @Environment(AppModel.self) var appModel
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace

    // MARK: - State

    @State private var rootEntity = Entity()
    @State private var box: ModelEntity?
    @State private var leftOrb: ModelEntity?
    @State private var rightOrb: ModelEntity?
    @State private var targetZone: ModelEntity?
    @State private var speechSynthesizer = AVSpeechSynthesizer()
    @State private var trackingError: String?

    @State private var leftHandGripping = false
    @State private var rightHandGripping = false
    @State private var leftHandPosition: SIMD3<Float> = .zero
    @State private var rightHandPosition: SIMD3<Float> = .zero
    @State private var leftInProximity = false
    @State private var rightInProximity = false

    @State private var isLifted = false
    @State private var hasPlaced = false
    @State private var showLabel = false

    @State private var floorCenter: SIMD3<Float> = [0, 0.15, -0.8]  // y = boxSize/2 so base sits on floor
    @State private var targetSurfaceCenter: SIMD3<Float> = [0, 0.75, -0.8]
    @State private var floorDetected = false
    @State private var surfaceDetected = false

    // MARK: - Constants

    private let pickupProximity: Float = 0.20
    private let fistThreshold: Float = 0.08
    private let placementRadius: Float = 0.25
    private let boxSize: Float = 0.3

    // MARK: - ARKit (let, not @State)

    private let arSession = ARKitSession()
    private let handTracking = HandTrackingProvider()
    private let planeDetection = PlaneDetectionProvider(alignments: [.horizontal])

    // MARK: - Body

    var body: some View {
        RealityView { (content: inout RealityViewContent, attachments: RealityViewAttachments) in
            content.add(rootEntity)

            // Procedural box (cardboard-ish brown cube)
            let boxMesh = MeshResource.generateBox(size: boxSize)
            let boxMaterial = SimpleMaterial(
                color: UIColor.brown,
                roughness: 0.8,
                isMetallic: false
            )
            let boxEntity = ModelEntity(mesh: boxMesh, materials: [boxMaterial])
            boxEntity.position = floorCenter
            rootEntity.addChild(boxEntity)
            box = boxEntity

            // Two green orbs on opposite sides of the box
            let lOrb = makeOrb()
            let rOrb = makeOrb()
            let orbY = floorCenter.y + boxSize / 2  // box midpoint
            lOrb.position = SIMD3<Float>(floorCenter.x - 0.2, orbY, floorCenter.z)
            rOrb.position = SIMD3<Float>(floorCenter.x + 0.2, orbY, floorCenter.z)
            rootEntity.addChild(lOrb)
            rootEntity.addChild(rOrb)
            leftOrb = lOrb
            rightOrb = rOrb

            // Target zone disc (semi-transparent green)
            let zoneMesh = MeshResource.generateCylinder(height: 0.02, radius: 0.2)
            let zoneMaterial = SimpleMaterial(
                color: UIColor(red: 0.2, green: 0.9, blue: 0.4, alpha: 0.4),
                roughness: 1.0,
                isMetallic: false
            )
            let zone = ModelEntity(mesh: zoneMesh, materials: [zoneMaterial])
            zone.position = targetSurfaceCenter
            rootEntity.addChild(zone)
            targetZone = zone

            // Control panel attachment
            if let panel = attachments.entity(for: "controls") {
                panel.position = [-0.7, 1.5, -1.0]
                content.add(panel)
            }

            // Encouragement label attachment
            if let label = attachments.entity(for: "encouragement") {
                label.position = [0, 1.6, -1.0]
                content.add(label)
            }
        } attachments: {
            Attachment(id: "controls") {
                SceneControlPanel(
                    sceneName: "Box Lift",
                    instruction: instructionText,
                    isReady: false,
                    hasDropped: hasPlaced,
                    onDrop: { },
                    onReset: resetScene,
                    onReturn: { await dismissImmersiveSpace() }
                )
            }

            Attachment(id: "encouragement") {
                Text("Lifting is safe when done with confidence.")
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

            async let floorFallback: Void = {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if !floorDetected { floorDetected = true }
            }()

            async let surfaceFallback: Void = {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if !surfaceDetected { surfaceDetected = true }
            }()

            async let tracking: Void = runHandTracking()
            async let planes: Void = runPlaneDetection()

            _ = await (floorFallback, surfaceFallback, tracking, planes)
        }
    }

    // MARK: - Instruction Text

    private var instructionText: String {
        if let error = trackingError { return error }
        if hasPlaced { return "You placed it. Tap Reset to try again." }
        if isLifted { return "Now move the box to the green target zone and release." }
        if leftInProximity || rightInProximity { return "Clench your hand to grip. Grip both sides to lift." }
        return "Grip both sides of the box to lift it onto the surface."
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
            floorDetected = true
            surfaceDetected = true
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

    // MARK: - Plane Detection

    private func runPlaneDetection() async {
        // Stub — implemented in Task 3
    }

    // MARK: - Hand Tracking

    private func runHandTracking() async {
        // Stub — implemented in Task 4
    }

    // MARK: - Orb Pulse

    private func pulseOrb(_ orb: ModelEntity?, grow: Bool) {
        guard let orb else { return }
        let scale: Float = grow ? 1.3 : 1.0
        let target = Transform(
            scale: [scale, scale, scale],
            rotation: orb.transform.rotation,
            translation: orb.position
        )
        orb.move(to: target, relativeTo: nil, duration: 0.3, timingFunction: .easeInOut)
    }

    // MARK: - Target Zone Pulse

    private func startTargetZonePulse() {
        // Stub — implemented in Task 3
    }

    // MARK: - Encouragement

    private func triggerEncouragement() {
        // Stub — implemented in Task 5
    }

    // MARK: - Reset

    private func resetScene() {
        speechSynthesizer.stopSpeaking(at: .immediate)
        isLifted = false
        hasPlaced = false
        leftHandGripping = false
        rightHandGripping = false
        leftInProximity = false
        rightInProximity = false
        showLabel = false

        // Restore box to floor
        box?.position = floorCenter

        // Restore orbs to box sides
        let orbY = floorCenter.y + boxSize / 2
        leftOrb?.position = SIMD3<Float>(floorCenter.x - 0.2, orbY, floorCenter.z)
        rightOrb?.position = SIMD3<Float>(floorCenter.x + 0.2, orbY, floorCenter.z)
        leftOrb?.transform.scale = [1, 1, 1]
        rightOrb?.transform.scale = [1, 1, 1]

        // Restore target zone
        targetZone?.isEnabled = true
        targetZone?.transform.scale = [1, 1, 1]
        startTargetZonePulse()
    }
}
```

- [ ] **Step 2: Verify file compiles**

Build in Xcode (Cmd+B). Expected: compiles with no errors. The stub functions are empty but valid.

- [ ] **Step 3: Commit**

```bash
git add Threshold/Scenes/BoxLiftSceneView.swift
git commit -m "feat: add BoxLiftSceneView skeleton with entities and control panel"
```

---

### Task 3: Register ImmersiveSpace in ThresholdApp

**Files:**
- Modify: `Threshold/App/ThresholdApp.swift:60-71`

- [ ] **Step 1: Add the ImmersiveSpace registration**

After the Sack `ImmersiveSpace` block (line 70), add:

```swift
        // Box Lift — two-handed grip pickup and surface placement
        ImmersiveSpace(id: AppModel.SceneType.boxLift.rawValue) {
            BoxLiftSceneView()
                .environment(appModel)
                .onAppear { appModel.immersiveSpaceState = .open }
                .onDisappear {
                    appModel.immersiveSpaceState = .closed
                    appModel.activeScene = nil
                }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
```

- [ ] **Step 2: Build and verify**

Build in Xcode (Cmd+B). Expected: compiles. The new scene should now appear in the ContentView scene library.

- [ ] **Step 3: Commit**

```bash
git add Threshold/App/ThresholdApp.swift
git commit -m "feat: register BoxLiftScene ImmersiveSpace in ThresholdApp"
```

---

### Task 4: Implement Plane Detection (Floor + Elevated Surface)

**Files:**
- Modify: `Threshold/Scenes/BoxLiftSceneView.swift` (replace `runPlaneDetection` and `startTargetZonePulse` stubs)

- [ ] **Step 1: Implement `runPlaneDetection()`**

Replace the stub with full plane detection logic. This handles both floor planes (for box placement) and elevated surface planes (for target zone placement):

```swift
    private func runPlaneDetection() async {
        for await update in planeDetection.anchorUpdates {
            // Exit once both surfaces found
            guard !floorDetected || !surfaceDetected else { return }

            let anchor = update.anchor
            guard update.event == .added || update.event == .updated else { continue }

            let transform = anchor.originFromAnchorTransform
            let center = SIMD3<Float>(
                transform.columns.3.x,
                transform.columns.3.y,
                transform.columns.3.z
            )

            // Z-range: in front of user
            guard center.z < -0.3 && center.z > -1.5 else { continue }

            // Floor plane
            if !floorDetected && center.y > -0.1 && center.y < 0.3 {
                guard let boxEntity = box else { continue }

                boxEntity.position = center
                let worldBounds = boxEntity.visualBounds(relativeTo: nil)
                let boundsHeight = worldBounds.max.y - worldBounds.min.y
                if boundsHeight > 0.01 {
                    boxEntity.position.y += center.y - worldBounds.min.y
                }

                floorCenter = boxEntity.position

                // Reposition orbs to box sides
                let orbY = boxEntity.position.y + boxSize / 2
                leftOrb?.position = SIMD3<Float>(boxEntity.position.x - 0.2, orbY, boxEntity.position.z)
                rightOrb?.position = SIMD3<Float>(boxEntity.position.x + 0.2, orbY, boxEntity.position.z)

                floorDetected = true
            }

            // Elevated surface — pick closest to user (smallest |z|)
            if !surfaceDetected && center.y > 0.3 && center.y < 1.3 {
                let isBetter = abs(center.z) < abs(targetSurfaceCenter.z)
                if isBetter || !surfaceDetected {
                    targetSurfaceCenter = center

                    targetZone?.position = center
                    // Lift target zone to sit on the surface
                    if let zone = targetZone {
                        let zoneBounds = zone.visualBounds(relativeTo: nil)
                        let zoneHeight = zoneBounds.max.y - zoneBounds.min.y
                        if zoneHeight > 0.001 {
                            zone.position.y += center.y - zoneBounds.min.y
                        }
                    }
                }

                surfaceDetected = true
                startTargetZonePulse()
            }
        }
    }
```

- [ ] **Step 2: Implement `startTargetZonePulse()`**

Replace the stub with a looping scale animation:

```swift
    private func startTargetZonePulse() {
        guard let zone = targetZone else { return }
        Task {
            while !hasPlaced {
                // Scale up
                let growTransform = Transform(
                    scale: [1.1, 1.0, 1.1],
                    rotation: zone.transform.rotation,
                    translation: zone.position
                )
                zone.move(to: growTransform, relativeTo: nil, duration: 0.75, timingFunction: .easeInOut)
                try? await Task.sleep(nanoseconds: 750_000_000)

                guard !hasPlaced else { break }

                // Scale back
                let shrinkTransform = Transform(
                    scale: [1.0, 1.0, 1.0],
                    rotation: zone.transform.rotation,
                    translation: zone.position
                )
                zone.move(to: shrinkTransform, relativeTo: nil, duration: 0.75, timingFunction: .easeInOut)
                try? await Task.sleep(nanoseconds: 750_000_000)
            }
        }
    }
```

- [ ] **Step 3: Build and verify**

Build in Xcode (Cmd+B). Expected: compiles with no errors.

- [ ] **Step 4: Commit**

```bash
git add Threshold/Scenes/BoxLiftSceneView.swift
git commit -m "feat: implement plane detection for floor and elevated surface in BoxLiftScene"
```

---

### Task 5: Implement Hand Tracking with Dual-Hand Grip

**Files:**
- Modify: `Threshold/Scenes/BoxLiftSceneView.swift` (replace `runHandTracking` stub)

- [ ] **Step 1: Implement `runHandTracking()` with both-hand fist detection and gripCount state machine**

Replace the stub. This is the core interaction logic — processes both hands, detects fist per hand, manages proximity/pulse, computes gripCount, and drives the state machine:

```swift
    private func runHandTracking() async {
        for await update in handTracking.anchorUpdates {
            let anchor = update.anchor
            guard anchor.isTracked else { continue }
            guard let skeleton = anchor.handSkeleton else { continue }
            guard !hasPlaced else { continue }

            // Wrist world position
            let wristJoint = skeleton.joint(.wrist)
            guard wristJoint.isTracked else { continue }
            let wristMatrix = anchor.originFromAnchorTransform * wristJoint.anchorFromJointTransform
            let wristPos = SIMD3<Float>(
                wristMatrix.columns.3.x,
                wristMatrix.columns.3.y,
                wristMatrix.columns.3.z
            )

            // Fist detection: 3+ fingers curled
            let fingerPairs: [(HandSkeleton.JointName, HandSkeleton.JointName)] = [
                (.indexFingerTip, .indexFingerMetacarpal),
                (.middleFingerTip, .middleFingerMetacarpal),
                (.ringFingerTip, .ringFingerMetacarpal),
                (.littleFingerTip, .littleFingerMetacarpal)
            ]

            let isFist: Bool
            if isLifted {
                // Lenient while carrying: untracked = still holding
                let curledCount = fingerPairs.filter { (tipName, mcName) in
                    let tipJoint = skeleton.joint(tipName)
                    let mcJoint = skeleton.joint(mcName)
                    guard tipJoint.isTracked, mcJoint.isTracked else { return true }
                    let tipMatrix = anchor.originFromAnchorTransform * tipJoint.anchorFromJointTransform
                    let mcMatrix = anchor.originFromAnchorTransform * mcJoint.anchorFromJointTransform
                    let tipPos = SIMD3<Float>(tipMatrix.columns.3.x, tipMatrix.columns.3.y, tipMatrix.columns.3.z)
                    let mcPos = SIMD3<Float>(mcMatrix.columns.3.x, mcMatrix.columns.3.y, mcMatrix.columns.3.z)
                    return simd_distance(tipPos, mcPos) < fistThreshold
                }.count
                isFist = curledCount >= 3
            } else {
                // Strict before pickup: untracked = not curled
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
                isFist = curledCount >= 3
            }

            // Update per-hand state
            let nearestOrb: ModelEntity?
            if anchor.chirality == .left {
                leftHandPosition = wristPos
                leftHandGripping = isFist && (leftInProximity || isLifted)
                nearestOrb = leftOrb
            } else {
                rightHandPosition = wristPos
                rightHandGripping = isFist && (rightInProximity || isLifted)
                nearestOrb = rightOrb
            }

            // Proximity check (only when not yet lifted)
            if !isLifted {
                if let orb = nearestOrb {
                    let dist = simd_distance(wristPos, orb.position)
                    let nowInProximity = dist < pickupProximity

                    if anchor.chirality == .left {
                        if nowInProximity != leftInProximity {
                            leftInProximity = nowInProximity
                            pulseOrb(leftOrb, grow: nowInProximity)
                        }
                    } else {
                        if nowInProximity != rightInProximity {
                            rightInProximity = nowInProximity
                            pulseOrb(rightOrb, grow: nowInProximity)
                        }
                    }
                }
            }

            // gripCount-based state machine
            let gripCount = (leftHandGripping ? 1 : 0) + (rightHandGripping ? 1 : 0)

            if !isLifted && gripCount == 2 {
                // Both hands gripping near orbs → lift
                isLifted = true
            }

            if isLifted {
                if gripCount == 0 {
                    // Released — check placement
                    guard let boxEntity = box else { continue }
                    let distToTarget = simd_distance(boxEntity.position, targetSurfaceCenter)

                    if distToTarget < placementRadius {
                        // Place on surface
                        placeBox()
                    } else {
                        // Drop back to floor
                        dropBoxToFloor()
                    }
                } else {
                    // Carrying — update box position
                    updateCarryPosition(gripCount: gripCount)
                }
            }
        }
    }
```

- [ ] **Step 2: Add the carry position and drop/place helper functions**

Add these functions after `runHandTracking()`:

```swift
    // MARK: - Carry Position

    private func updateCarryPosition(gripCount: Int) {
        let carryPoint: SIMD3<Float>
        if gripCount == 2 {
            carryPoint = (leftHandPosition + rightHandPosition) / 2
        } else if leftHandGripping {
            carryPoint = leftHandPosition
        } else {
            carryPoint = rightHandPosition
        }

        let boxPos = carryPoint + SIMD3<Float>(0, -0.15, 0)
        box?.position = boxPos

        // Orbs maintain relative offset from box center
        leftOrb?.position = SIMD3<Float>(boxPos.x - 0.2, boxPos.y + boxSize / 2, boxPos.z)
        rightOrb?.position = SIMD3<Float>(boxPos.x + 0.2, boxPos.y + boxSize / 2, boxPos.z)
    }

    // MARK: - Drop to Floor

    private func dropBoxToFloor() {
        guard let boxEntity = box else { return }
        let dropPos = SIMD3<Float>(boxEntity.position.x, floorCenter.y, boxEntity.position.z)

        isLifted = false
        leftHandGripping = false
        rightHandGripping = false
        leftInProximity = false
        rightInProximity = false

        boxEntity.position = dropPos

        let orbY = dropPos.y + boxSize / 2
        leftOrb?.position = SIMD3<Float>(dropPos.x - 0.2, orbY, dropPos.z)
        rightOrb?.position = SIMD3<Float>(dropPos.x + 0.2, orbY, dropPos.z)
        leftOrb?.transform.scale = [1, 1, 1]
        rightOrb?.transform.scale = [1, 1, 1]
    }

    // MARK: - Place on Surface

    private func placeBox() {
        hasPlaced = true
        isLifted = false
        leftHandGripping = false
        rightHandGripping = false

        // Snap box to target surface
        if let boxEntity = box {
            var snapTransform = boxEntity.transform
            snapTransform.translation = targetSurfaceCenter
            // Lift box so base sits on surface
            snapTransform.translation.y += boxSize / 2
            boxEntity.move(to: snapTransform, relativeTo: nil, duration: 0.3, timingFunction: .easeOut)
        }

        // Snap orbs to box sides at rest
        let orbY = targetSurfaceCenter.y + boxSize / 2
        leftOrb?.position = SIMD3<Float>(targetSurfaceCenter.x - 0.2, orbY, targetSurfaceCenter.z)
        rightOrb?.position = SIMD3<Float>(targetSurfaceCenter.x + 0.2, orbY, targetSurfaceCenter.z)

        // Fade out target zone (scale to zero)
        if let zone = targetZone {
            var fadeTransform = zone.transform
            fadeTransform.scale = [0.01, 0.01, 0.01]
            zone.move(to: fadeTransform, relativeTo: nil, duration: 0.3, timingFunction: .easeOut)
        }

        triggerEncouragement()
    }
```

- [ ] **Step 3: Build and verify**

Build in Xcode (Cmd+B). Expected: compiles with no errors.

- [ ] **Step 4: Commit**

```bash
git add Threshold/Scenes/BoxLiftSceneView.swift
git commit -m "feat: implement dual-hand tracking and gripCount state machine for BoxLiftScene"
```

---

### Task 6: Implement Encouragement Sequence

**Files:**
- Modify: `Threshold/Scenes/BoxLiftSceneView.swift` (replace `triggerEncouragement` stub)

- [ ] **Step 1: Implement `triggerEncouragement()`**

Replace the stub with the speech + label fade sequence:

```swift
    private func triggerEncouragement() {
        Task {
            withAnimation(.easeIn(duration: 0.6)) { showLabel = true }
            let utterance = AVSpeechUtterance(
                string: "Lifting is safe when done with confidence."
            )
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85
            speechSynthesizer.speak(utterance)
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            withAnimation(.easeOut(duration: 0.4)) { showLabel = false }
        }
    }
```

- [ ] **Step 2: Build and verify**

Build in Xcode (Cmd+B). Expected: compiles.

- [ ] **Step 3: Commit**

```bash
git add Threshold/Scenes/BoxLiftSceneView.swift
git commit -m "feat: add encouragement speech and label animation to BoxLiftScene"
```

---

### Task 7: End-to-End Smoke Test

**Files:** None (testing only)

- [ ] **Step 1: Run in visionOS Simulator**

Build and run in Xcode targeting the visionOS Simulator. Verify:
1. "The Box Lift" card appears in the ContentView scene library with the shippingbox.fill icon
2. Tapping the card opens the immersive space
3. A brown cube appears on the floor (or at fallback position)
4. Two green orbs appear on opposite sides of the cube
5. A green disc (target zone) appears at elevated height with pulsing animation
6. The control panel displays with correct instruction text
7. The "Back" button dismisses the immersive space

- [ ] **Step 2: Test on device (if available)**

On a physical Vision Pro, verify:
1. Hand tracking detects both hands
2. Orbs pulse when hands approach
3. Clenching both fists near orbs lifts the box
4. Box follows hand midpoint while carrying
5. Releasing one hand continues single-hand carry
6. Releasing near target zone places the box with snap animation
7. Encouragement text and speech play
8. Reset button restores everything
9. Releasing away from target zone drops box to floor

- [ ] **Step 3: Fix any issues found and commit**

```bash
git add -A
git commit -m "fix: address issues found during BoxLiftScene smoke test"
```

(Skip this step if no issues found.)
