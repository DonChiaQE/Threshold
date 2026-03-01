# Cactus Surface Placement Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the hardcoded cactus position with ARKit `PlaneDetectionProvider` so the cactus snaps onto the nearest real-world horizontal surface (table) when the scene opens.

**Architecture:** Add `PlaneDetectionProvider(alignments: [.horizontal])` to the existing `ARKitSession`. A new async task loops over plane anchor updates, finds the first qualifying horizontal plane (height > 0.4 m, within arm's reach), snaps the cactus there, and syncs the glow spheres to the new spine position. A 3-second fallback keeps the cactus at its hardcoded position if no surface is found.

**Tech Stack:** visionOS, RealityKit, ARKit (`PlaneDetectionProvider`, `PlaneAnchor`), Swift Concurrency

---

> **Note:** This is a visionOS app with no CLI build or unit test workflow. All verification is done by building and running in Xcode on a physical Vision Pro or visionOS Simulator. After each task, build in Xcode to confirm no compile errors before proceeding.

---

### Task 1: Convert `spinePosition` from `let` constant to `@State var`

`spinePosition` is currently a `let` constant. After surface placement snaps, it needs to update so the glow spheres track the new cactus position. Make it mutable state.

**Files:**
- Modify: `Threshold/Scenes/CactusSceneView.swift`

**Step 1: Change the `spinePosition` declaration**

In `CactusSceneView`, find these two lines under `// MARK: - Constants`:

```swift
private let cactusPosition: SIMD3<Float> = [0, 1.0, -0.6]
/// Raised above the pot base to target the cactus spines — tune this after on-device testing.
private let spinePosition: SIMD3<Float> = [0, 1.25, -0.6]
```

Replace with:

```swift
private let cactusPosition: SIMD3<Float> = [0, 1.0, -0.6]
/// Raised above the pot base to target the cactus spines. Updated after surface snap.
@State private var spinePosition: SIMD3<Float> = [0, 1.25, -0.6]
```

**Step 2: Build in Xcode**

Product → Build (⌘B). Expected: build succeeds with no errors.

**Step 3: Commit**

```bash
git add Threshold/Scenes/CactusSceneView.swift
git commit -m "refactor: make spinePosition mutable @State for surface placement"
```

---

### Task 2: Add `cactusPlaced` state flag and `PlaneDetectionProvider`

**Files:**
- Modify: `Threshold/Scenes/CactusSceneView.swift`

**Step 1: Add `cactusPlaced` state flag**

In the `// MARK: - State` section, after `@State private var trackingError: String?`, add:

```swift
@State private var cactusPlaced = false
```

**Step 2: Add `PlaneDetectionProvider` as a `let` property**

In the `// MARK: - ARKit (declared as \`let\` — not @State)` section, after the `handTracking` declaration, add:

```swift
private let planeDetection = PlaneDetectionProvider(alignments: [.horizontal])
```

**Step 3: Build in Xcode**

Product → Build (⌘B). Expected: build succeeds.

**Step 4: Commit**

```bash
git add Threshold/Scenes/CactusSceneView.swift
git commit -m "feat: add cactusPlaced flag and PlaneDetectionProvider to CactusSceneView"
```

---

### Task 3: Run `planeDetection` in the existing `arSession`

The existing `runHandTracking()` calls `arSession.run([handTracking])`. We need to also pass `planeDetection` so both providers run together.

**Files:**
- Modify: `Threshold/Scenes/CactusSceneView.swift`

**Step 1: Update the `arSession.run` call**

In `runHandTracking()`, find:

```swift
try await arSession.run([handTracking])
```

Replace with:

```swift
try await arSession.run([handTracking, planeDetection])
```

**Step 2: Build in Xcode**

Product → Build (⌘B). Expected: build succeeds.

**Step 3: Commit**

```bash
git add Threshold/Scenes/CactusSceneView.swift
git commit -m "feat: run planeDetection alongside handTracking in arSession"
```

---

### Task 4: Add `runPlaneDetection()` function

This function loops over plane anchor updates and snaps the cactus on the first qualifying horizontal plane.

**Files:**
- Modify: `Threshold/Scenes/CactusSceneView.swift`

**Step 1: Add the function**

Add this function under `// MARK: - Hand Tracking` (or create a new `// MARK: - Plane Detection` section before it):

```swift
// MARK: - Plane Detection

private func runPlaneDetection() async {
    for await update in planeDetection.anchorUpdates {
        guard !cactusPlaced else { return }

        let anchor = update.anchor
        // Only care about added or updated planes
        guard update.event == .added || update.event == .updated else { continue }

        // Extract world-space center of this plane
        let transform = anchor.originFromAnchorTransform
        let center = SIMD3<Float>(
            transform.columns.3.x,
            transform.columns.3.y,
            transform.columns.3.z
        )

        // Filter: table height (above 0.4 m from floor) and within arm's reach in front of user
        guard center.y > 0.4 else { continue }
        guard center.z < -0.3 && center.z > -1.5 else { continue }

        // Snap cactus to plane surface
        let snappedPosition = SIMD3<Float>(center.x, center.y, center.z)
        cactusEntity?.position = snappedPosition

        // Sync spine position: 0.25 m above cactus base (same offset as original design)
        spinePosition = SIMD3<Float>(center.x, center.y + 0.25, center.z)
        redGlowEntity?.position = spinePosition
        greenGlowEntity?.position = spinePosition

        cactusPlaced = true
        return
    }
}
```

**Step 2: Build in Xcode**

Product → Build (⌘B). Expected: build succeeds.

**Step 3: Commit**

```bash
git add Threshold/Scenes/CactusSceneView.swift
git commit -m "feat: add runPlaneDetection() snap-once surface placement logic"
```

---

### Task 5: Add 3-second fallback and launch `runPlaneDetection()` as a task

Wire the new function into the view's `.task` modifier and add the fallback timer.

**Files:**
- Modify: `Threshold/Scenes/CactusSceneView.swift`

**Step 1: Replace the single `.task` with concurrent tasks**

Find the current `.task` modifier at the bottom of `body`:

```swift
.task {
    await runHandTracking()
}
```

Replace with:

```swift
.task {
    // Fallback: if no surface found in 3 s, lock in the hardcoded position
    async let fallback: Void = {
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        if !cactusPlaced {
            cactusPlaced = true
        }
    }()

    async let tracking: Void = runHandTracking()
    async let planes: Void = runPlaneDetection()

    _ = await (fallback, tracking, planes)
}
```

**Step 2: Build in Xcode**

Product → Build (⌘B). Expected: build succeeds.

**Step 3: Test on device or Simulator**

- Run on a physical Vision Pro (Simulator does not provide real plane detection).
- Point toward a table or desk within arm's reach (~0.3–1.5 m in front of you).
- After a moment, the cactus should appear sitting on the table surface.
- If no table is in view, after 3 seconds the cactus appears at the hardcoded fallback position.
- Bring your right hand toward the cactus spines — the red → green glow sequence should still trigger correctly.

**Step 4: Commit**

```bash
git add Threshold/Scenes/CactusSceneView.swift
git commit -m "feat: launch plane detection and fallback timer alongside hand tracking"
```

---

## Summary of Changes

| File | Change |
|------|--------|
| `Threshold/Scenes/CactusSceneView.swift` | `spinePosition` → `@State var`; add `cactusPlaced`, `planeDetection`; update `arSession.run`; add `runPlaneDetection()`; update `.task` with concurrent tasks + fallback |

No other files need to change. `Info.plist` already has `NSWorldSensingUsageDescription`.
