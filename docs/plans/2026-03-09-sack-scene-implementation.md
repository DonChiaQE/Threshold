# Sack Scene Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a new immersive scene where the user picks up a grocery sack from the floor using a right-hand grip gesture, with an encouragement message on success.

**Architecture:** New `SackSceneView.swift` following the exact `CactusSceneView` pattern — `HandTrackingProvider` for fist detection + `PlaneDetectionProvider` for floor placement. `AppModel` and `ThresholdApp` get minimal additions to register the scene.

**Tech Stack:** SwiftUI, RealityKit, ARKit, AVFoundation, RealityKitContent bundle

---

### Task 1: Register the scene in AppModel

**Files:**
- Modify: `Threshold/App/AppModel.swift`

**Step 1: Add `sack` case to `SceneType` enum**

In `AppModel.swift`, add after `case cactus = "cactus"`:

```swift
case sack = "SackScene"
```

**Step 2: Add `title`, `subtitle`, and `systemImage` for `sack`**

In the `title` switch, add:
```swift
case .sack: "The Grocery Bag"
```

In the `subtitle` switch, add:
```swift
case .sack: "Lift a heavy bag to experience that movement is safe."
```

In the `systemImage` switch, add:
```swift
case .sack: "bag.fill"
```

**Step 3: Build in Xcode**

Open `Threshold.xcodeproj`, press ⌘B. Expected: build succeeds (Swift will error on non-exhaustive switch if any case is missed — fix any such errors).

**Step 4: Commit**

```bash
git add Threshold/App/AppModel.swift
git commit -m "feat: add sack scene type to AppModel"
```

---

### Task 2: Register the ImmersiveSpace in ThresholdApp

**Files:**
- Modify: `Threshold/App/ThresholdApp.swift`

**Step 1: Add the ImmersiveSpace block**

After the cactus `ImmersiveSpace` block (line ~57), add:

```swift
// Sack — floor pickup with grip gesture for upper body exposure therapy
ImmersiveSpace(id: AppModel.SceneType.sack.rawValue) {
    SackSceneView()
        .environment(appModel)
        .onAppear { appModel.immersiveSpaceState = .open }
        .onDisappear {
            appModel.immersiveSpaceState = .closed
            appModel.activeScene = nil
        }
}
.immersionStyle(selection: .constant(.mixed), in: .mixed)
```

**Step 2: Build in Xcode**

Press ⌘B. Expected: build succeeds (Xcode will warn about missing `SackSceneView` type — this is expected and will be resolved in Task 3).

**Step 3: Commit**

```bash
git add Threshold/App/ThresholdApp.swift
git commit -m "feat: register SackScene ImmersiveSpace in ThresholdApp"
```

---

### Task 3: Create SackSceneView

**Files:**
- Create: `Threshold/Scenes/SackSceneView.swift`

**Step 1: Create the file with this complete implementation**

```swift
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
    /// World-space position of the green orb. Updated after floor snap.
    @State private var orbPosition: SIMD3<Float> = [0, 0.65, -0.8]
    /// Floor-level position of the sack origin. Used to restore on reset.
    @State private var floorCenter: SIMD3<Float> = [0, 0, -0.8]
    @State private var speechSynthesizer = AVSpeechSynthesizer()

    // MARK: - Constants

    private let pickupProximity: Float = 0.20   // metres — wrist to orb
    private let fistThreshold: Float  = 0.07    // metres — fingertip to palm

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
            let newOrbPos = SIMD3<Float>(center.x, sackTopY + 0.15, center.z)
            orbPosition = newOrbPos
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

            // If already picked up, track sack to wrist
            if isPickedUp {
                sackEntity?.position = wristPos + SIMD3<Float>(0, -0.25, 0)
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

            // Fist detection via palm center (middleFingerMetacarpal)
            let palmJoint = skeleton.joint(.middleFingerMetacarpal)
            guard palmJoint.isTracked else { continue }
            let palmMatrix = anchor.originFromAnchorTransform * palmJoint.anchorFromJointTransform
            let palmPos = SIMD3<Float>(
                palmMatrix.columns.3.x,
                palmMatrix.columns.3.y,
                palmMatrix.columns.3.z
            )

            let tipJoints: [HandSkeleton.JointName] = [
                .indexFingerTip, .middleFingerTip, .ringFingerTip, .littleFingerTip
            ]
            let isFist = tipJoints.allSatisfy { jointName in
                let joint = skeleton.joint(jointName)
                guard joint.isTracked else { return false }
                let m = anchor.originFromAnchorTransform * joint.anchorFromJointTransform
                let tipPos = SIMD3<Float>(m.columns.3.x, m.columns.3.y, m.columns.3.z)
                return simd_distance(tipPos, palmPos) < fistThreshold
            }

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
        orbEntity?.isEnabled = false

        Task {
            showLabel = true
            let utterance = AVSpeechUtterance(
                string: "You did it. Your body carried the weight. Pain anticipated is not always pain caused."
            )
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85
            speechSynthesizer.speak(utterance)
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            showLabel = false
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
```

**Step 2: Add the file to the Xcode target**

In Xcode, right-click `Threshold/Scenes` group → Add Files → select `SackSceneView.swift`. Ensure the `Threshold` target is checked.

**Step 3: Build in Xcode**

Press ⌘B. Expected: build succeeds with no errors.

Common issues:
- `'SackSceneView' cannot be found` in ThresholdApp — file not added to target. Fix: add file to target (Step 2).
- `'HandSkeleton.JointName' has no member 'middleFingerMetacarpal'` — check SDK version. Fallback: use `.indexFingerKnuckle` as the palm proxy instead.

**Step 4: Commit**

```bash
git add Threshold/Scenes/SackSceneView.swift
git commit -m "feat: add SackSceneView with floor spawn, orb interaction, and fist pickup"
```

---

### Task 4: Verify Sack.usda is in the bundle

**Files:**
- Check: `Packages/RealityKitContent/Sources/RealityKitContent/RealityKitContent.rkassets/Sack.usda`

**Step 1: Confirm file exists**

```bash
ls Packages/RealityKitContent/Sources/RealityKitContent/RealityKitContent.rkassets/Sack.usda
```

Expected: file is present (user confirmed this).

**Step 2: Confirm it loads**

Run the scene on device/simulator. If `trackingError` shows "Failed to load sack", the asset name in code doesn't match. The `Entity(named: "Sack", ...)` call strips the `.usda` extension — the file must be named exactly `Sack.usda`. If the file is named differently, update the `Entity(named:)` call in `SackSceneView.swift` to match.

**Step 3: No commit needed** (asset already exists)

---

### Task 5: Manual test on device

Run on visionOS device. Walk through this checklist:

- [ ] Scene card "The Grocery Bag" appears in the library
- [ ] Entering scene: sack appears on floor within ~3 seconds, or at fallback position
- [ ] Green orb floats visibly above the sack
- [ ] Instruction panel shows "Bring your right hand to the green orb above the bag and grip to pick it up."
- [ ] Moving right hand near orb: orb pulses larger, instruction updates to "Now clench your hand to grip the bag."
- [ ] Moving hand away: orb returns to normal size
- [ ] Clenching fist while near orb: sack attaches to wrist, orb disappears
- [ ] Sack follows wrist as hand moves
- [ ] Encouragement label appears and is narrated
- [ ] Label fades after ~5 seconds
- [ ] Reset button restores sack to floor and orb reappears
- [ ] Return to Library works

**If fist threshold feels off:** Adjust `fistThreshold` in `SackSceneView.swift`. Increase (e.g. `0.09`) if hard to trigger, decrease (e.g. `0.05`) if triggering accidentally.

**If orb is too high/low:** Adjust the `+ 0.15` offset in `runPlaneDetection()` after the `sackTopY` calculation.

---

### Task 6: Final commit

```bash
git add -A
git commit -m "feat: sack scene — floor spawn, grip pickup, encouragement label"
```
