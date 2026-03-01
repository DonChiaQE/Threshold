# GlovesSceneView + CactusSceneView Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Wire up two new immersive visionOS scenes — GlovesSceneView (glove rigidly follows wrist via hand tracking) and CactusSceneView (proximity to cactus triggers a threat/reappraisal sequence) — with full AppModel and ThresholdApp registration.

**Architecture:** Both scenes follow the established visionOS scene pattern: `ARKitSession`/`HandTrackingProvider` as `let` struct properties, a `RealityView` with an explicit closure type annotation, and a reusable `SceneControlPanel` attachment. GlovesSceneView continuously maps wrist joint world-space transform onto the glove entity. CactusSceneView polls fingertip joint positions each frame against a fixed cactus world position, firing a one-shot glow + text attachment sequence when proximity is detected.

**Tech Stack:** SwiftUI, RealityKit, ARKit (HandTrackingProvider), RealityKitContent, AVAudioPlayer, visionOS

---

## Task 1: Add .gloves and .cactus to AppModel.SceneType

**Files:**
- Modify: `Threshold/App/AppModel.swift:18-56`

**Step 1: Add the two new enum cases**

In `AppModel.swift`, add `case gloves` and `case cactus` after the existing cases:

```swift
enum SceneType: String, CaseIterable, Identifiable {
    case blockDrop = "BlockDropScene"
    case smoke = "SmokeScene"
    case hammer = "HammerScene"
    case dumbbell = "DumbbellScene"
    case protectometerLab = "ProtectometerLabScene"
    case gloves = "gloves"
    case cactus = "cactus"
    // ...
}
```

**Step 2: Add title, subtitle, systemImage branches**

In the `title` switch, add:
```swift
case .gloves: "The Glove"
case .cactus: "The Cactus"
```

In the `subtitle` switch, add:
```swift
case .gloves: "Your brain predicts danger from a worn glove."
case .cactus: "Hurt does not equal harm."
```

In the `systemImage` switch, add:
```swift
case .gloves: "hand.raised.fill"
case .cactus: "leaf.fill"
```

**Step 3: Verify the file compiles**

Open `Threshold.xcodeproj` in Xcode and confirm there are no compile errors in `AppModel.swift`. The Swift exhaustive-switch checker will catch any missed branches.

**Step 4: Commit**

```bash
git add Threshold/App/AppModel.swift
git commit -m "feat: add .gloves and .cactus cases to AppModel.SceneType"
```

---

## Task 2: Create GlovesSceneView.swift

**Files:**
- Create: `Threshold/Scenes/GlovesSceneView.swift`

**Context / Pattern to follow:** `HammerSceneView.swift` — same `HandTrackingProvider` setup, same `let` ARKit properties, same `anchorUpdates` async loop. The key difference is that instead of positioning the hammer near the wrist at drop-time, GlovesSceneView continuously updates the glove entity's world-space transform to match the wrist joint every frame update.

**Step 1: Create the file with the full implementation**

```swift
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
```

**Step 2: Add file to Xcode project**

Open Xcode → right-click `Threshold/Scenes` group → Add Files. Select `GlovesSceneView.swift`. Confirm target membership is checked for `Threshold`.

**Step 3: Verify compile**

Build in Xcode (`⌘B`). Expected: builds clean. SourceKit may show false-positive macOS availability warnings — ignore them (see CLAUDE.md).

**Step 4: Commit**

```bash
git add Threshold/Scenes/GlovesSceneView.swift
git commit -m "feat: add GlovesSceneView with wrist-following glove entity"
```

---

## Task 3: Create CactusSceneView.swift

**Files:**
- Create: `Threshold/Scenes/CactusSceneView.swift`

**Context:** This scene places a cactus at `[0, 1.0, -0.6]`, then monitors the user's right fingertip joints each frame. When any fingertip is within 6 cm of the cactus position, a one-shot sequence fires:
1. (Immediate) Red glow sphere fades in over 0.3 s; prick sound plays.
2. (After 1.5 s) Red glow fades out, green glow fades in over 0.5 s; a SwiftUI "safe" label attachment appears for 3 s then its state clears.

**Opacity animation strategy:** `SimpleMaterial` does not support transform-based opacity animation. Use a `Task` with multiple `await Task.sleep()` intervals and replace materials to step through opacity values. Steps of 10% over the appropriate duration give a smooth perceived fade at ~visionOS 90 Hz.

**Glow entity approach:** `ModelEntity` sphere at cactus world position, starting with fully transparent material. Animate by replacing `.model?.materials` in a loop.

**Sound:** Attempt to load `"prick.wav"` from the main bundle with `AVAudioPlayer`. If the file doesn't exist the scene still works — the sound is optional. Drop `prick.wav` into `Threshold/` and add it to the Xcode target to activate it.

**Step 1: Create the file with the full implementation**

```swift
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

            // Pre-build invisible glow spheres (opacity set at runtime)
            let redGlow = makeGlowSphere(color: UIColor.red.withAlphaComponent(0.0))
            redGlow.position = cactusPosition
            rootEntity.addChild(redGlow)
            redGlowEntity = redGlow

            let greenGlow = makeGlowSphere(
                color: UIColor(red: 0.2, green: 0.9, blue: 0.4, alpha: 0.0)
            )
            greenGlow.position = cactusPosition
            rootEntity.addChild(greenGlow)
            greenGlowEntity = greenGlow

            // Control panel
            if let panel = attachments.entity(for: "controls") {
                panel.position = [0, 1.5, -1.2]
                content.add(panel)
            }
        } update: { (content: inout RealityViewContent, attachments: RealityViewAttachments) in
            // Show/hide the safe label attachment based on state
            if showSafeLabel {
                if let label = attachments.entity(for: "safeLabel") {
                    label.position = [0, 1.3, -0.6]
                    content.add(label)
                }
            }
        } attachments: {
            Attachment(id: "controls") {
                SceneControlPanel(
                    sceneName: "The Cactus",
                    instruction: instructionText,
                    isReady: !hasTriggered,
                    hasDropped: hasTriggered,
                    resetLabel: "Reset",
                    onDrop: triggerSequence,      // also manually triggerable
                    onReset: resetScene,
                    onReturn: { await dismissImmersiveSpace() }
                )
            }

            Attachment(id: "safeLabel") {
                if showSafeLabel {
                    Text("Your skin is safe.\nYour brain just predicted danger.")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(20)
                        .frame(maxWidth: 320)
                        .glassBackgroundEffect()
                }
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
            guard !hasTriggered else { continue }
            guard let skeleton = anchor.handSkeleton else { continue }

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

    /// Fade red glow from alpha 0 → 0.6 over ~0.3 s using material swaps.
    private func animateRedGlow() async {
        guard let entity = redGlowEntity else { return }
        let steps = 6
        let stepDuration: UInt64 = 50_000_000  // 50 ms per step → 300 ms total
        for i in 1...steps {
            let alpha = CGFloat(i) / CGFloat(steps) * 0.6
            setGlowAlpha(alpha, on: entity, baseColor: UIColor.red)
            try? await Task.sleep(nanoseconds: stepDuration)
        }
    }

    /// Fade red glow out over ~0.5 s, then fade green glow in over ~0.5 s.
    private func animateGreenGlow() async {
        guard let red = redGlowEntity, let green = greenGlowEntity else { return }
        let steps = 10
        let stepDuration: UInt64 = 50_000_000  // 50 ms per step → 500 ms total

        // Fade red out
        for i in stride(from: steps, through: 0, by: -1) {
            let alpha = CGFloat(i) / CGFloat(steps) * 0.6
            setGlowAlpha(alpha, on: red, baseColor: UIColor.red)
            try? await Task.sleep(nanoseconds: stepDuration)
        }

        // Fade green in
        let greenBase = UIColor(red: 0.2, green: 0.9, blue: 0.4, alpha: 1.0)
        for i in 1...steps {
            let alpha = CGFloat(i) / CGFloat(steps) * 0.5
            setGlowAlpha(alpha, on: green, baseColor: greenBase)
            try? await Task.sleep(nanoseconds: stepDuration)
        }
    }

    private func setGlowAlpha(_ alpha: CGFloat, on entity: ModelEntity, baseColor: UIColor) {
        let material = SimpleMaterial(
            color: baseColor.withAlphaComponent(alpha),
            roughness: 1.0,
            isMetallic: false
        )
        entity.model?.materials = [material]
    }

    // MARK: - Reset

    private func resetScene() {
        // Clear glow entities to fully transparent
        setGlowAlpha(0, on: redGlowEntity!, baseColor: UIColor.red)
        setGlowAlpha(0, on: greenGlowEntity!, baseColor: UIColor(red: 0.2, green: 0.9, blue: 0.4, alpha: 1.0))
        showSafeLabel = false
        hasTriggered = false
    }
}
```

**Step 2: Add file to Xcode project**

Right-click `Threshold/Scenes` group → Add Files. Select `CactusSceneView.swift`. Confirm target membership.

**Step 3: Verify compile**

Build in Xcode (`⌘B`). Expected: builds clean.

**Step 4: Commit**

```bash
git add Threshold/Scenes/CactusSceneView.swift
git commit -m "feat: add CactusSceneView with proximity glow sequence"
```

---

## Task 4: Register ImmersiveSpaces in ThresholdApp.swift

**Files:**
- Modify: `Threshold/App/ThresholdApp.swift:72-81` (after the protectometerLab block)

**Step 1: Add the two new ImmersiveSpace blocks**

After the `ProtectometerLabScene` block (before the closing `}` of `body`), add:

```swift
// Gloves – wrist-following glove hand tracking scene
ImmersiveSpace(id: AppModel.SceneType.gloves.rawValue) {
    GlovesSceneView()
        .environment(appModel)
        .onAppear { appModel.immersiveSpaceState = .open }
        .onDisappear {
            appModel.immersiveSpaceState = .closed
            appModel.activeScene = nil
        }
}
.immersionStyle(selection: .constant(.mixed), in: .mixed)

// Cactus – proximity threat/reappraisal sequence
ImmersiveSpace(id: AppModel.SceneType.cactus.rawValue) {
    CactusSceneView()
        .environment(appModel)
        .onAppear { appModel.immersiveSpaceState = .open }
        .onDisappear {
            appModel.immersiveSpaceState = .closed
            appModel.activeScene = nil
        }
}
.immersionStyle(selection: .constant(.mixed), in: .mixed)
```

**Step 2: Verify compile**

Build in Xcode (`⌘B`). Expected: builds clean. The ContentView scene library will now show both new scenes in its grid automatically (it iterates `SceneType.allCases`).

**Step 3: Full build + simulator smoke test**

Run in visionOS Simulator. Open the library window. Verify "The Glove" and "The Cactus" appear as cards. Tap each one to open its ImmersiveSpace. Verify the scene launches without crashing, the control panel appears, and the Back button returns to the library.

**Step 4: Commit**

```bash
git add Threshold/App/ThresholdApp.swift
git commit -m "feat: register GlovesSceneView and CactusSceneView ImmersiveSpaces"
```

---

## Known Limitations / Follow-up Notes

- **GlovesSceneView offset:** The glove model's origin point may not perfectly align with the wrist — you'll likely need to add a position/orientation offset to `worldWristMatrix` after testing on device. Expose it as a constant at the top of the struct.
- **CactusSceneView resetScene force unwrap:** The `resetScene()` function force-unwraps `redGlowEntity` and `greenGlowEntity`. These are always set in the `RealityView` init closure, but if the build ever changes consider using optional chaining instead.
- **AVAudioPlayer retention:** The prick sound player is created inside a `Task` and will be released immediately after. This is fine for short sounds but for robustness consider holding it in a `@State` property.
- **Gloves asset scale:** The `Gloves.usdz` model's real-world scale is unknown until tested on device. Add a `gloveEntity.scale = [x, y, z]` line in the tracking loop if scaling is needed.
- **CactusSceneView `update` closure:** The `RealityView` `update` closure is used to add the `safeLabel` attachment entity dynamically. If visionOS triggers the update closure before the attachment is ready, the label may flicker. An alternative is to keep the label permanently in the scene and show/hide via `.opacity(showSafeLabel ? 1 : 0)` on the SwiftUI `Attachment` content — simpler and avoids the `update` closure entirely.
