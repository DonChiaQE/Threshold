# Cactus + Glove Combined Scene Design

**Date:** 2026-02-27

## Goal

Update `CactusSceneView` to show a leather work glove on the user's right wrist throughout the scene, so the cactus contact sequence is experienced while "wearing" the glove.

## Approach

Modify `CactusSceneView` in place (Option A). `GlovesSceneView` remains as a separate standalone scene card.

## Changes

**File:** `Threshold/Scenes/CactusSceneView.swift`

1. Add `@State private var gloveEntity: Entity?` alongside the existing entity state properties.
2. In the `RealityView` make closure, load the glove model: `Entity(named: "Gloves", in: realityKitContentBundle)` — add it as a child of `rootEntity`.
3. In `runHandTracking()`, after extracting the wrist joint transform, call `gloveEntity?.setTransformMatrix(worldWristMatrix, relativeTo: nil)` each frame — identical to `GlovesSceneView`.
4. The single `HandTrackingProvider` update loop handles both wrist positioning (glove) and fingertip proximity (cactus trigger) in one pass.

## What Does Not Change

- Contact detection: 5 fingertip joints < 6 cm from `cactusPosition`
- Animation sequence: red glow → green glow → safe label
- `SceneControlPanel`, `hasTriggered` guard, reset logic
- `GlovesSceneView.swift`, `AppModel.swift`, `ThresholdApp.swift`

## Non-Goals

- No collision geometry on the glove
- No finger deformation or rig animation
- No changes to the scene library card or ImmersiveSpace ID
