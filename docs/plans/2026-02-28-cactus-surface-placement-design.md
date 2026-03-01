# Design: Cactus Surface Placement

**Date:** 2026-02-28
**Feature:** Place cactus on nearest real-world horizontal surface (table) using ARKit plane detection

---

## Goal

Replace the hardcoded cactus position `[0, 1.0, -0.6]` with dynamic placement on the nearest detected horizontal surface (e.g. a table). The cactus snaps to position once and stays there for the duration of the scene.

---

## ARKit Setup

- Add `let planeDetection = PlaneDetectionProvider(alignments: [.horizontal])` as a `let` property on `CactusSceneView` (same pattern as existing ARKit providers)
- Run both `handTracking` and `planeDetection` in the same `arSession` call: `arSession.run([handTracking, planeDetection])`
- Add a `@State private var cactusPlaced = false` flag to gate snap-once logic

---

## Surface Selection Logic

New async function `runPlaneDetection()` loops over `planeDetection.anchorUpdates`:

1. **Filter by height:** plane center `y > 0.4 m` (above floor, approximately table height)
2. **Filter by reach:** plane center `z` between `-0.3 m` and `-1.5 m` (reachable arm distance in front of user)
3. **On first qualifying plane:** extract world position from `anchor.originFromAnchorTransform.columns.3`, set `cactusEntity?.position` to `[x, y, z]`, set `cactusPlaced = true`
4. Once `cactusPlaced` is true, ignore further plane updates

---

## Glow and Spine Position Sync

After snapping, recompute `spinePosition` relative to the cactus's new y:

```
let snappedSpineY = cactusPos.y + 0.25  // same offset as original design
spinePosition = [cactusPos.x, snappedSpineY, cactusPos.z]
redGlowEntity?.position = spinePosition
greenGlowEntity?.position = spinePosition
```

`spinePosition` must become a `@State var` (not a `let` constant) so it can be updated after snap.

---

## Fallback

A `Task` runs concurrently with `runPlaneDetection()`:

```swift
Task {
    try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
    if !cactusPlaced {
        cactusPlaced = true  // stop plane detection; cactus stays at hardcoded position
    }
}
```

If no qualifying plane is found within 3 seconds, the cactus remains at `[0, 1.0, -0.6]`.

---

## Permissions

`NSWorldSensingUsageDescription` is already present in `Info.plist`. No changes needed.

---

## Files Changed

- `Threshold/Scenes/CactusSceneView.swift` — all changes contained here

---

## Out of Scope

- No UI indicator while scanning for surface (scene loads immediately with cactus at fallback position)
- No preference for `.table` classification vs generic horizontal plane (visionOS plane classification API not relied upon)
- No multi-surface selection or user override
