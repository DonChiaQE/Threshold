# Object Pickup — Therapy Scenario Design Spec

## Overview

A therapy scenario where the patient picks up 5 colored cubes scattered on the floor using a pinch grip (thumb + index finger) and places them into a box. Each successful placement triggers a chime and spoken encouragement. After all 5 are collected, a congratulatory screen appears.

## UI Integration

### AppModel Changes

- Add `.objectPickup` case to `SceneType` with raw value `"ObjectPickupScene"`
- `.objectPickup` returns `.therapy` for its `category` property
- Add `var showCongratulations = false` flag (same pattern as `showEducation`)

### ContentView Changes

- `CongratulationsView` shown when `appModel.showCongratulations` is true (same conditional pattern as `EducationDetailView`)
- Therapy tab now shows the "Object Pickup" scene card instead of "Coming soon"

### ThresholdApp Changes

- Register `ObjectPickupScene` ImmersiveSpace with `.mixed` immersion style

## Scene: ObjectPickupSceneView

### File

`Threshold/Scenes/ObjectPickupSceneView.swift`

### Assets

- **Box**: `Box.usda` (existing) — placed on the floor as the drop target
- **Cubes**: Generated via `MeshResource.generateBox(size: 0.05)` + `SimpleMaterial` — no asset files needed

### Tracking

- `HandTrackingProvider` only — right hand
- ARKit session declared as `let` properties (per project convention)

### State Machine

```
setup → active → complete
```

| State | User sees | Next trigger |
|-------|-----------|-------------|
| `setup` | 5 colored cubes spawn at random floor positions. Box placed to the right. Instruction text shown | Auto-advance when spawning complete |
| `active` | Patient pinch-grips cubes and places them in the box. Counter updates "2/5 collected". Chime + speech after each placement | All 5 placed |
| `complete` | Main window shows congratulatory screen. Immersive space stays open | User taps Done |

### Pinch Detection

- Track `.thumbTip` and `.indexFingerTip` joints on the right hand
- Convert both to world space via `anchor.originFromAnchorTransform * joint.anchorFromJointTransform`
- Pinch detected when `simd_distance(thumbTipPos, indexTipPos) < 0.025` (2.5cm)
- Pinch released when distance exceeds `0.04` (4cm) — hysteresis to prevent flicker
- Pinch midpoint (average of thumb and index positions) used as the "grab point"

### Object Pickup

- When pinching and no object is held: check distance from pinch midpoint to each unplaced cube
- If any cube is within 0.08m of the pinch midpoint, attach it to the hand
- While held: cube position tracks the pinch midpoint each frame
- On pinch release:
  - If cube is within 0.15m of the box opening position → animate cube to box center (short `entity.move` over 0.2s), then disable the entity (`isEnabled = false`), increment counter, play chime + speech
  - Otherwise → drop cube at current position (it stays where released, still pickable)

### Spatial Layout

#### Cubes
- 5 cubes, each 0.05m (5cm), spawned at random floor positions
- y = 0.025 (half cube height, sitting on floor)
- Scatter area: x from -0.75 to 0.75, z from -0.5 to -1.5 (in front of patient)
- Minimum 0.3m apart (reject and re-randomize if too close to another cube)
- Colors: red, blue, green, yellow, orange — using `SimpleMaterial(color:roughness:isMetallic:)`

#### Box
- Loaded from `Box.usda` (existing asset)
- Position: x ≈ 0.6, y ≈ 0, z ≈ -0.4 (floor level, to the right of the scatter area)
- Drop zone: sphere of radius 0.15m centered on the box opening (box position + y offset for the opening height)
- Use `visualBounds(relativeTo: nil)` to determine the box opening y position after loading

### Audio

#### Chime
- Synthesized pleasant tone using `AVAudioEngine` + `AVAudioPlayerNode`
- Short sine wave at ~800Hz with gentle decay (~200ms)
- Plays at the box position for spatial audio

#### Speech
- `AVSpeechSynthesizer` (same pattern as CactusSceneView)
- Rotating phrases keyed to the placement count:
  - 1st: "Well done!"
  - 2nd: "Great job!"
  - 3rd: "Keep it up!"
  - 4th: "Almost there!"
  - 5th: "You did it!"
- Speech rate: `AVSpeechUtteranceDefaultSpeechRate * 0.85` (slightly slower for clarity)

### SceneControlPanel

- `sceneName`: "Object Pickup"
- `instruction`: Dynamic text —
  - During `active`: "Pick up the objects and place them in the box. (0/5)"
  - During `complete`: "All objects collected! Check the main window."
- `isReady`: always false (no action button — interaction is hand-based)
- `hasDropped`: true when `sceneState == .complete` (shows Reset + Library buttons)
- `onReset`: Respawns cubes at new random positions, empties box visual, resets counter to 0, resets state to `setup`

### Reset

- Remove all cube entities from scene
- Respawn 5 new cubes at fresh random positions
- Reset `placedCount` to 0
- Reset `sceneState` to `.setup`
- Set `appModel.showCongratulations = false`
- Keep the box in place

## Congratulations View

Displayed in the main window when `appModel.showCongratulations` is true.

### Title
"You Did It!"

### Body
"You picked up all 5 objects and placed them in the box. Movement is safe, and your body is capable of more than you think."

### UI
- Same layout pattern as `EducationDetailView`
- Done button sets `showCongratulations = false` and calls `dismissImmersiveSpace()`

## Files Modified

| File | Change |
|------|--------|
| `Threshold/App/AppModel.swift` | Add `.objectPickup` to `SceneType`, add `showCongratulations` flag |
| `Threshold/Views/ContentView.swift` | Add `CongratulationsView`, show it when flag is true, update therapy tab |
| `Threshold/App/ThresholdApp.swift` | Register `ObjectPickupScene` ImmersiveSpace |
| `Threshold/Scenes/ObjectPickupSceneView.swift` | New file — complete pickup scenario |

## Files Unchanged

`NailSceneView.swift`, `SceneControlPanel.swift`, and all other existing files remain untouched.
