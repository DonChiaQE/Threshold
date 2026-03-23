# Box Lift Scene Design

## Overview

A new immersive scene for Threshold where the user picks up a box from the floor using both hands and places it on a detected elevated surface (table/shelf). The educational message: "Lifting is safe when done with confidence" — reinforcing that movement avoidance, not the lift itself, is the problem.

## Scene Registration

- **SceneType case:** `.boxLift`
- **Raw ID:** `"BoxLiftScene"`
- **Title:** "The Box Lift"
- **Subtitle:** "Lift a box from the floor to a surface — movement is safe"
- **Icon:** `shippingbox.fill`
- **Immersion style:** `.mixed` (same as all other scenes)

Registered as an `ImmersiveSpace` in `ThresholdApp.swift`. Listed in `ContentView` scene library.

## Entities

### Box

- Procedural: `MeshResource.generateBox(size: 0.3)` — a 30cm cube
- Material: `SimpleMaterial(color: .brown, roughness: 0.8, isMetallic: false)` (cardboard-ish)
- Placed on the floor via plane detection with the standard floor-snapping pattern (measure `visualBounds`, shift so base sits on surface)
- Fallback position: `[0, 0, -0.8]` if no floor plane detected within 3 seconds

### Green Orbs (x2)

- Procedural: `MeshResource.generateSphere(radius: 0.05)`
- Material: `SimpleMaterial(color: UIColor(red: 0.2, green: 0.9, blue: 0.4, alpha: 0.7), roughness: 1.0, isMetallic: false)`
- Positioned on opposite sides of the box at its vertical midpoint:
  - Left orb: `box.position.x - 0.2`, `box midpoint Y`, `box.position.z`
  - Right orb: `box.position.x + 0.2`, `box midpoint Y`, `box.position.z`
- Float slightly outside the box edges so hands can approach naturally

### Target Zone

- Procedural: `MeshResource.generateCylinder(height: 0.02, radius: 0.2)`
- Material: semi-transparent green `SimpleMaterial`
- Rendered on the detected elevated surface
- Subtle pulse animation (scale oscillation) to draw attention
- Fades out after successful box placement

## ARKit Tracking

### Providers

- `HandTrackingProvider` — tracks both `.left` and `.right` chiralities
- `PlaneDetectionProvider(alignments: [.horizontal])` — finds floor and elevated surfaces

No `WorldTrackingProvider` needed (no gaze tracking in this scene).

### Plane Detection Logic

- **Floor** (`center.y < 0.3`): Place the box here using standard floor-snapping pattern
- **Elevated surface** (`center.y > 0.3 && center.y < 1.3`): Nearest qualifying horizontal plane becomes the target. Render the target zone disc on it. If multiple planes qualify, pick the one closest to the user (smallest Z magnitude).
- **Fallback:** If no elevated surface found within 3 seconds, spawn a virtual target zone at `[0, 0.75, -0.8]`

### Hand Tracking

- Same fist detection as SackSceneView: 3+ fingers curled (tip-to-metacarpal distance `< 0.08m`)
- Runs for both chiralities in a single `for await` loop
- Stores separate state for left hand and right hand (wrist position, `isFist`, proximity to nearest orb)

### Session Setup

Authorization requested for `[.handTracking, .worldSensing]`. Session runs `[handTracking, planeDetection]` before launching concurrent async tasks that consume provider streams.

## Interaction State Machine

| State | Condition | Behavior |
|-------|-----------|----------|
| **Idle** | No hands near orbs | Box on floor, orbs at rest |
| **Proximity** | Either hand within 0.20m of its nearest orb | That orb pulses (scale 1.0 -> 1.3, 0.3s ease-in-out) |
| **Lifting** | Both orbs gripped (fist detected near each) | Box + orbs follow midpoint between two hands, box offset 0.15m below midpoint |
| **Carrying (one hand)** | One hand releases during lift | Box + orbs follow remaining gripped hand (single-hand carry) |
| **Placed** | Both hands release while box is within 0.25m of target zone center | Box snaps to surface, encouragement triggers |

### Key Transitions

- **Idle -> Proximity:** Hand enters orb range (< 0.20m)
- **Proximity -> Lifting:** Both orbs gripped (fist near each orb)
- **Lifting -> Carrying:** One hand unclenches
- **Carrying -> Lifting:** Second hand re-grips
- **Lifting/Carrying -> Placed:** Both hands release while box center is within 0.25m of target zone center
- **Lifting/Carrying -> Idle:** Both hands release outside target zone; box drops back to floor position

### Carrying Position

- **Two hands:** Box follows the midpoint of left and right grip positions, offset 0.15m downward
- **One hand:** Box follows the single grip position, offset 0.15m downward (same as SackScene pattern)
- Orbs maintain their relative offset from the box center at all times

## Placement & Encouragement

### Placement Animation

When both hands release in the target zone:
1. Box animates via `move(to:)` (0.3s, `.easeOut`) snapping to target surface center
2. Target zone disc fades out
3. Orbs fade out or snap to box sides at rest

### Encouragement Sequence

Same pattern as SackSceneView:
1. Label fades in (0.6s ease-in): **"Lifting is safe when done with confidence"**
2. `AVSpeechUtterance` at 0.85x rate speaks the same text
3. 5 second display
4. Label fades out (0.4s ease-out)

## Control Panel & Attachments

### SceneControlPanel

Position: `[-0.7, 1.5, -1.0]`

Parameters:
- `sceneName: "Box Lift"`
- `instruction: "Grip both sides of the box to lift it onto the surface"`
- `isReady`: not actively used (interaction is hand-driven, no pre-action button)
- `hasDropped` maps to `hasPlaced` state
- No `onMark` callback (no foot marking)
- `onReset`: returns box to floor, orbs to sides, clears placement, resets to Idle
- `onReturn`: dismisses immersive space

### Label Attachment

Position: `[0, 1.6, -1.0]` — encouragement text, controlled by `showLabel` state with fade animations.

## File Changes

| File | Change |
|------|--------|
| `AppModel.swift` | Add `.boxLift` case to `SceneType` |
| `ThresholdApp.swift` | Register `ImmersiveSpace(id: "BoxLiftScene")` |
| `ContentView.swift` | No change needed (iterates `SceneType.allCases`) |
| `BoxLiftSceneView.swift` | **New file** — self-contained scene view |

## State Properties

```
@State private var rootEntity = Entity()
@State private var box: ModelEntity        // the procedural cube
@State private var leftOrb: ModelEntity    // left-side orb
@State private var rightOrb: ModelEntity   // right-side orb
@State private var targetZone: ModelEntity // placement target disc

@State private var leftHandGripping = false
@State private var rightHandGripping = false
@State private var leftHandPosition: SIMD3<Float> = .zero
@State private var rightHandPosition: SIMD3<Float> = .zero
@State private var leftInProximity = false
@State private var rightInProximity = false

@State private var isLifted = false        // box is being carried
@State private var hasPlaced = false       // box successfully placed
@State private var showLabel = false       // encouragement visibility

@State private var floorCenter: SIMD3<Float> = [0, 0, -0.8]
@State private var targetSurfaceCenter: SIMD3<Float> = [0, 0.75, -0.8]
@State private var boxPlaced = false       // plane detection success flag

// ARKit (let, not @State)
private let arSession = ARKitSession()
private let handTracking = HandTrackingProvider()
private let planeDetection = PlaneDetectionProvider(alignments: [.horizontal])
```

## Approach

Self-contained `BoxLiftSceneView.swift` following Approach A — same patterns as existing scenes, no shared abstractions. Consistent with the project's "each scene is self-contained" architecture.
