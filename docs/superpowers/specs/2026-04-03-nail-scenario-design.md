# Nail in the Glove — Design Spec

## Overview

A pain neuroscience education scenario for visionOS where a nail appears to be driven through the patient's gloved hand by a hammer, but the reveal shows it passed harmlessly between their fingers. Based on the 1995 "nail in the boot" case study.

## UI Structure

### Navigation

Replace the current flat card grid in `ContentView` with a native visionOS `TabView` using `.tabViewStyle(.sidebarAdaptable)`.

Two tabs:
- **Education** — pain neuroscience education scenarios (contains the Nail scenario)
- **Therapy** — clinical rehabilitation exercises (empty "Coming soon" placeholder for now)

### AppModel Changes

- Add a `nail` case to `SceneType` with raw value `"NailScene"`
- Add a `category` property to `SceneType` (`.education` / `.therapy`)
- Filter existing scenes out of the UI — keep the code, just don't show them
- Only the `nail` scene appears under the Education tab

## Scene: NailSceneView

### File

`Threshold/Scenes/NailSceneView.swift`

### Assets

- **Glove**: `Gloves.usda` (existing) — references `gloves.usdz`, scale 0.02
- **Hammer**: `Immersive.usda` (existing) — references `Stright (1).usdz`
- **Nail**: `Nail.usda` (existing, new) — references `Nail.usdz`, scale 0.01

### Tracking

- `HandTrackingProvider` only — no plane detection
- Right hand only
- ARKit session declared as `let` properties (per project convention)
- Requires `NSHandsTrackingUsageDescription` in Info.plist (already present)

### State Machine

```
waitingForHand → gloveAppearing → ready → animating → revealing → educating
```

| State | User sees | Next trigger |
|-------|-----------|-------------|
| `waitingForHand` | Text: "Place your right hand flat on the table and spread your fingers wide" | Right hand detected + finger spread check passes |
| `gloveAppearing` | Glove fades in on the right hand, tracking wrist | Auto-advance after ~1s |
| `ready` | Nail visible above index-middle gap. Hammer above nail. "Strike" button in control panel | User taps "Strike" |
| `animating` | Hammer drives down onto nail. Nail moves down through glove. Hammer lifts away | Animation completes (~3s total) |
| `revealing` | Glove fades out over ~1s. Nail visible between fingers | Auto-advance after fade |
| `educating` | Main window shows educational content. Immersive space remains open | User taps "Done" in main window |

### Spatial Positioning

#### Nail Position
- Calculated as the midpoint between `.indexFingerKnuckle` and `.middleFingerKnuckle` joints
- Both joints converted to world space: `anchor.originFromAnchorTransform * joint.anchorFromJointTransform`
- Nail placed slightly above this midpoint (on top of the hand surface)
- Nail oriented vertically (point down)

#### Finger Spread Check
- Measure distance between index and middle finger knuckle world positions
- Threshold: > 0.04m (4cm) to confirm fingers are spread wide enough
- If not spread enough, update instruction text: "Spread your fingers wider"

#### Glove Attachment
- Same pattern as `GlovesSceneView`: attach to `.wrist` joint via `setTransformMatrix()`
- Uses `anchor.originFromAnchorTransform * wristJoint.anchorFromJointTransform`

#### Hammer Position
- Positioned ~15cm directly above the nail position
- Floating (no hand attachment)

### Animation Sequence

Triggered when user taps "Strike":

| Time | Action | Code |
|------|--------|------|
| 0s | Hammer moves down to nail head | `hammer.move(to: nailHeadTransform, duration: 0.3)` |
| 0.3s | Nail drives downward ~3-4cm | `nail.move(to: drivenTransform, duration: 0.7)` |
| 1.0s | Hammer lifts back to original position | `hammer.move(to: originalTransform, duration: 0.4)` |
| 2.0s | Glove fades out | Animate `OpacityComponent` from 1→0 over 1s |
| 3.0s | Reveal complete, trigger educational content | Update `appModel` to show education view |

The nail's driven position is level with the knuckles — visually suggesting penetration, but sitting in the gap between the fingers.

### Audio

None for now. May add hammer strike sound in a future iteration.

## Educational Content

Displayed in the main window after the reveal. The immersive space stays open so the patient can look at their hand while reading.

### Title
"The Nail That Never Was"

### What just happened
"The nail appeared to pierce your hand — but it passed harmlessly between your fingers. Your brain may have anticipated pain, even though no injury occurred."

### The original story
"In 1995, a construction worker jumped onto a plank and a 15cm nail drove straight through his boot. He was in agony — rushed to A&E in severe pain, requiring sedation. But when doctors removed the boot, they found the nail had passed between his toes. There was no wound. No tissue damage. The pain was real, but it was generated entirely by the brain's expectation of injury."

### The takeaway
"Pain is a protective response, not a damage report. Your brain creates pain based on perceived threat — not just what's happening in your body. Understanding this is the first step in learning to retrain your pain response."

### Communication Mechanism
- `NailSceneView` sets `appModel.showEducation = true` after the reveal completes
- `ContentView` observes `showEducation` (via `@Observable` AppModel) and swaps the scene library for the educational text view
- "Done" button sets `showEducation = false` and calls `dismissImmersiveSpace()`

### UI
- Large, readable text in the main window
- "Done" button dismisses both the educational view and the immersive space

## Files Modified

| File | Change |
|------|--------|
| `AppModel.swift` | Add `nail` to `SceneType`, add `category` property, add `showEducation` flag |
| `ThresholdApp.swift` | Register `NailScene` ImmersiveSpace, remove old scene registrations from active use |
| `ContentView.swift` | Replace flat card grid with `TabView(.sidebarAdaptable)`, two tabs |
| `NailSceneView.swift` | New file — the nail scenario scene |
| `SceneControlPanel.swift` | No changes needed — pass `actionLabel: "Strike"` and `actionIcon: "hammer.fill"` |

## Files Unchanged

All existing scene view files (`HammerSceneView.swift`, `DumbbellSceneView.swift`, etc.) remain in the project but are not referenced by the UI. They can be re-enabled later.
