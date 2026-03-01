# Cactus + Glove Combined Scene Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Update `CactusSceneView` so the user wears a leather glove on their right hand throughout the scene, and the existing cactus contact sequence fires when the gloved hand touches the cactus.

**Architecture:** One change to one file — `CactusSceneView.swift`. A new `gloveEntity` state property is loaded in the `RealityView` make closure alongside the cactus. The existing `HandTrackingProvider` update loop is restructured: wrist tracking (glove positioning) runs unconditionally every frame, while fingertip proximity checking only runs before the trigger fires. This fixes a latent bug where the current `guard !hasTriggered else { continue }` would stop glove movement after the sequence fires.

**Tech Stack:** SwiftUI, RealityKit, ARKit (HandTrackingProvider), RealityKitContent, visionOS

---

## Task 1: Add gloveEntity state and load glove in the make closure

**Files:**
- Modify: `Threshold/Scenes/CactusSceneView.swift`

### Context

`CactusSceneView.swift` currently has this state block (lines 24–32):

```swift
// MARK: - State

@State private var rootEntity = Entity()
@State private var cactusEntity: Entity?
@State private var redGlowEntity: ModelEntity?
@State private var greenGlowEntity: ModelEntity?
@State private var hasTriggered = false
@State private var showSafeLabel = false
@State private var trackingError: String?
```

And this make closure block that loads the cactus (lines 50–58):

```swift
// Load cactus model
do {
    let cactus = try await Entity(named: "Cactus", in: realityKitContentBundle)
    cactus.position = cactusPosition
    rootEntity.addChild(cactus)
    cactusEntity = cactus
} catch {
    trackingError = "Failed to load cactus model: \(error.localizedDescription)"
}
```

### Step 1: Add gloveEntity to the state block

Insert `@State private var gloveEntity: Entity?` after `greenGlowEntity`:

```swift
@State private var rootEntity = Entity()
@State private var cactusEntity: Entity?
@State private var redGlowEntity: ModelEntity?
@State private var greenGlowEntity: ModelEntity?
@State private var gloveEntity: Entity?           // ← add this line
@State private var hasTriggered = false
@State private var showSafeLabel = false
@State private var trackingError: String?
```

### Step 2: Load the glove in the make closure

Insert a glove-loading block immediately after the cactus-loading block (after line 58, before the glow sphere block):

```swift
// Load glove model — follows right wrist via hand tracking
do {
    let glove = try await Entity(named: "Gloves", in: realityKitContentBundle)
    rootEntity.addChild(glove)
    gloveEntity = glove
} catch {
    // Glove load failure is non-fatal; scene still works without it
}
```

The glove does not need a fixed position here — its transform is overwritten every frame by the tracking loop.

### Step 3: Verify the make closure ordering

After the edit, the make closure body should follow this order:
1. `content.add(rootEntity)`
2. Load cactus (`Entity(named: "Cactus", ...)`)
3. Load glove (`Entity(named: "Gloves", ...)`)  ← new
4. Build red glow sphere
5. Build green glow sphere
6. Add controls panel attachment
7. Add safeLabel attachment

### Step 4: Commit

```bash
git add Threshold/Scenes/CactusSceneView.swift
git commit -m "feat: load glove entity in CactusSceneView make closure"
```

---

## Task 2: Update the tracking loop to always drive glove position

**Files:**
- Modify: `Threshold/Scenes/CactusSceneView.swift`

### Context

The current `runHandTracking()` loop (lines 157–181) has this structure:

```swift
for await update in handTracking.anchorUpdates {
    let anchor = update.anchor
    guard anchor.chirality == .right, anchor.isTracked else { continue }
    guard !hasTriggered else { continue }          // ← blocks ALL work after trigger
    guard let skeleton = anchor.handSkeleton else { continue }

    for jointName in tipJoints {
        // fingertip proximity check
    }
}
```

**Problem:** `guard !hasTriggered else { continue }` is evaluated before the skeleton is accessed. After the sequence fires (`hasTriggered = true`), the loop skips the rest of the body entirely — the glove would freeze in place for the remainder of the scene.

**Fix:** Move the `hasTriggered` guard to just before the fingertip loop, and insert the wrist-tracking block before it.

### Step 1: Replace the loop body

Replace the entire `for await update in handTracking.anchorUpdates { ... }` block with:

```swift
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
```

Key changes vs the original:
- `guard let skeleton` moved up before the `hasTriggered` check
- Wrist joint block inserted before `guard !hasTriggered`
- `guard !hasTriggered` now only gates the fingertip loop, not the glove tracking

### Step 2: Verify the full `runHandTracking()` function

After the edit, the complete function should look like this:

```swift
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
```

### Step 3: Commit

```bash
git add Threshold/Scenes/CactusSceneView.swift
git commit -m "feat: update tracking loop to drive glove wrist position in CactusSceneView"
```

---

## Verification

Build in Xcode (`⌘B`). Expected: compiles clean.

On device / simulator:
1. Open the **Cactus** scene from the library
2. Raise your right hand — the glove should appear on your wrist immediately
3. Move your hand toward the cactus — red glow fires on fingertip contact
4. After the sequence completes, move your hand away and back — the glove keeps tracking
5. Tap Reset — glove continues tracking, glow is cleared, scene is ready again

## Notes

- `GlovesSceneView.swift`, `AppModel.swift`, `ThresholdApp.swift` — no changes
- Glove load failure is silently swallowed; the scene is still fully functional without it (non-fatal catch)
- The glove model origin may not align perfectly with the wrist on first test — if offset adjustment is needed, add `glove.position = SIMD3<Float>(...)` after the `Entity(named:)` call in Task 1 Step 2
