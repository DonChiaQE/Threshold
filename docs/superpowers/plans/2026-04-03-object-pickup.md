# Object Pickup — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a therapy scenario where the patient picks up 5 colored cubes from the floor using a pinch grip and places them into a box, with audio encouragement and a congratulatory screen.

**Architecture:** Single new scene (`ObjectPickupSceneView`) using ARKit `HandTrackingProvider` for right-hand pinch detection (thumb + index finger). Cubes generated via `MeshResource`, box loaded from existing `Box.usda`. Chime via `AVAudioEngine` and speech via `AVSpeechSynthesizer`. AppModel gains `.objectPickup` scene type under `.therapy` category and a `showCongratulations` flag.

**Tech Stack:** SwiftUI, RealityKit, ARKit (HandTrackingProvider), AVFoundation (audio), visionOS 2.0+

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `Threshold/App/AppModel.swift` | Modify | Add `.objectPickup` to `SceneType`, add `showCongratulations` flag |
| `Threshold/Views/ContentView.swift` | Modify | Add `CongratulationsView`, handle `showCongratulations` flag, replace therapy placeholder with scene cards |
| `Threshold/App/ThresholdApp.swift` | Modify | Register `ObjectPickupScene` ImmersiveSpace |
| `Threshold/Scenes/ObjectPickupSceneView.swift` | Create | Complete pickup scenario — pinch detection, cubes, box, audio, counter |

---

### Task 1: AppModel — Add objectPickup scene and showCongratulations flag

**Files:**
- Modify: `Threshold/App/AppModel.swift`

- [ ] **Step 1: Add objectPickup case to SceneType and showCongratulations flag**

In `AppModel.swift`, add the `.objectPickup` case to the `SceneType` enum and the `showCongratulations` property.

Replace the `SceneType` enum (lines 34–62) with:

```swift
    /// Each scene type maps to a registered ImmersiveSpace ID.
    enum SceneType: String, CaseIterable, Identifiable {
        case nail = "NailScene"
        case objectPickup = "ObjectPickupScene"

        var id: String { rawValue }

        var category: SceneCategory {
            switch self {
            case .nail: .education
            case .objectPickup: .therapy
            }
        }

        var title: String {
            switch self {
            case .nail: "Nail in the Glove"
            case .objectPickup: "Object Pickup"
            }
        }

        var subtitle: String {
            switch self {
            case .nail: "A nail appears to pierce your hand — but the reveal shows it passed harmlessly between your fingers."
            case .objectPickup: "Pick up objects from the floor and place them in a box. Movement is safe."
            }
        }

        var systemImage: String {
            switch self {
            case .nail: "hammer.fill"
            case .objectPickup: "hand.pinch.fill"
            }
        }
    }
```

Then add `showCongratulations` after the existing `showEducation` property (after line 76):

```swift
    /// When true, ContentView shows the congratulatory screen instead of the scene library.
    var showCongratulations = false
```

- [ ] **Step 2: Commit**

```bash
git add Threshold/App/AppModel.swift
git commit -m "feat: add objectPickup scene type and showCongratulations flag"
```

---

### Task 2: ContentView — Add CongratulationsView and replace therapy placeholder

**Files:**
- Modify: `Threshold/Views/ContentView.swift`

- [ ] **Step 1: Update the conditional in body to handle showCongratulations**

Replace the `body` computed property (lines 18–29) with:

```swift
    var body: some View {
        Group {
            if appModel.showEducation {
                EducationDetailView {
                    appModel.showEducation = false
                    await dismissImmersiveSpace()
                }
            } else if appModel.showCongratulations {
                CongratulationsView {
                    appModel.showCongratulations = false
                    await dismissImmersiveSpace()
                }
            } else {
                tabView
            }
        }
    }
```

- [ ] **Step 2: Replace the therapy placeholder tab with scene cards**

Replace the Therapy `Tab` (lines 39–41) with:

```swift
            Tab("Therapy", systemImage: "cross.case.fill") {
                sceneCategoryView(for: .therapy)
            }
```

- [ ] **Step 3: Update the subtitle in sceneCategoryView to be category-aware**

Replace the hardcoded subtitle text in `sceneCategoryView` (line 59) with:

```swift
                    Text(category == .education
                         ? "Pain neuroscience education scenarios"
                         : "Clinical rehabilitation exercises")
```

- [ ] **Step 4: Remove the therapyPlaceholderView property**

Delete the entire `therapyPlaceholderView` computed property (lines 82–95).

- [ ] **Step 5: Add CongratulationsView after EducationDetailView**

Add the following struct after the closing brace of `EducationDetailView` (after line 200):

```swift
// MARK: - Congratulations View

struct CongratulationsView: View {
    let onDone: () async -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "trophy.fill")
                .font(.system(size: 72))
                .foregroundStyle(.yellow)

            Text("You Did It!")
                .font(.largeTitle.bold())

            Text("You picked up all 5 objects and placed them in the box. Movement is safe, and your body is capable of more than you think.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)

            Button {
                Task { await onDone() }
            } label: {
                Label("Done", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 6: Commit**

```bash
git add Threshold/Views/ContentView.swift
git commit -m "feat: add CongratulationsView and populate therapy tab with scene cards"
```

---

### Task 3: ThresholdApp — Register ObjectPickupScene

**Files:**
- Modify: `Threshold/App/ThresholdApp.swift`

- [ ] **Step 1: Add ObjectPickupScene ImmersiveSpace registration**

Add the following after the NailScene ImmersiveSpace block (after line 33):

```swift

        // Object Pickup — therapy rehabilitation
        ImmersiveSpace(id: AppModel.SceneType.objectPickup.rawValue) {
            ObjectPickupSceneView()
                .environment(appModel)
                .onAppear { appModel.immersiveSpaceState = .open }
                .onDisappear {
                    appModel.immersiveSpaceState = .closed
                    appModel.activeScene = nil
                }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
```

- [ ] **Step 2: Commit**

```bash
git add Threshold/App/ThresholdApp.swift
git commit -m "feat: register ObjectPickupScene ImmersiveSpace"
```

---

### Task 4: ObjectPickupSceneView — Complete implementation

**Files:**
- Create: `Threshold/Scenes/ObjectPickupSceneView.swift`

- [ ] **Step 1: Create ObjectPickupSceneView.swift with the complete implementation**

Create the file at `Threshold/Scenes/ObjectPickupSceneView.swift` with:

```swift
//
//  ObjectPickupSceneView.swift
//  Threshold
//
//  Immersive scene: "Object Pickup" — Patient picks up 5 colored cubes
//  from the floor using a pinch grip (thumb + index finger) and places
//  them into a box. Audio encouragement after each placement.
//

import SwiftUI
import RealityKit
import ARKit
import RealityKitContent
import AVFoundation

// MARK: - Chime synthesiser

private final class ChimeSoundPlayer: @unchecked Sendable {

    private let engine     = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let envNode    = AVAudioEnvironmentNode()
    private let mono       = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

    init() {
        engine.attach(playerNode)
        engine.attach(envNode)
        engine.connect(playerNode, to: envNode, format: mono)
        engine.connect(envNode, to: engine.mainMixerNode, format: nil)
        envNode.renderingAlgorithm = .HRTFHQ
        envNode.distanceAttenuationParameters.referenceDistance = 0.5
        envNode.distanceAttenuationParameters.rolloffFactor     = 1.0
        try? engine.start()
    }

    /// Play a pleasant chime at `position` in world space.
    func play(at position: SIMD3<Float>) {
        let sampleRate: Double = 44_100
        let frameCount = AVAudioFrameCount(sampleRate * 0.2) // 200 ms
        guard let buffer = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        let samples = buffer.floatChannelData![0]
        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            let envelope = exp(-t * 15.0) // gentle decay
            let tone = sin(2.0 * .pi * 800.0 * t) * 0.5 // 800 Hz sine
            let harmonic = sin(2.0 * .pi * 1200.0 * t) * 0.2 // soft overtone
            samples[i] = Float(envelope * (tone + harmonic))
        }
        playerNode.position = AVAudio3DPoint(x: position.x, y: position.y, z: position.z)
        playerNode.scheduleBuffer(buffer)
        playerNode.play()
    }
}

// MARK: - Scene View

struct ObjectPickupSceneView: View {

    @Environment(AppModel.self) var appModel
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace

    // MARK: - Scene State

    enum SceneState {
        case setup
        case active
        case complete
    }

    @State private var sceneState: SceneState = .setup

    // MARK: - Entity References

    @State private var rootEntity = Entity()
    @State private var boxEntity: Entity?
    @State private var cubeEntities: [ModelEntity] = []

    // MARK: - Pickup State

    @State private var placedCount = 0
    @State private var heldCubeIndex: Int?
    @State private var isPinching = false

    // MARK: - Tracking State

    @State private var trackingError: String?

    // MARK: - Audio

    @State private var chimePlayer = ChimeSoundPlayer()
    @State private var speechSynthesizer = AVSpeechSynthesizer()

    // MARK: - ARKit (declared as `let` — not @State)

    private let arSession = ARKitSession()
    private let handTracking = HandTrackingProvider()

    // MARK: - Constants

    private let cubeSize: Float = 0.05
    private let cubeColors: [UIColor] = [.systemRed, .systemBlue, .systemGreen, .systemYellow, .systemOrange]

    /// Thumb-to-index distance below which a pinch is detected (metres).
    private let pinchThreshold: Float = 0.025
    /// Thumb-to-index distance above which a pinch is released (metres) — hysteresis.
    private let releaseThreshold: Float = 0.04
    /// Max distance from pinch midpoint to cube center to pick it up (metres).
    private let grabRadius: Float = 0.08
    /// Max distance from cube to box opening to count as placed (metres).
    private let dropZoneRadius: Float = 0.15

    /// Box placement position.
    private let boxPosition: SIMD3<Float> = [0.6, 0, -0.4]

    /// Encouragement phrases keyed by placement count (1-indexed).
    private let encouragements = ["Well done!", "Great job!", "Keep it up!", "Almost there!", "You did it!"]

    // MARK: - Body

    var body: some View {
        RealityView { (content: inout RealityViewContent, attachments: RealityViewAttachments) in
            content.add(rootEntity)

            // Load and place the box
            do {
                let box = try await Entity(named: "Box", in: realityKitContentBundle)
                box.position = boxPosition
                // Adjust so box base sits on the floor
                let bounds = box.visualBounds(relativeTo: nil)
                let boundsHeight = bounds.max.y - bounds.min.y
                if boundsHeight > 0.01 {
                    box.position.y += boxPosition.y - bounds.min.y
                }
                rootEntity.addChild(box)
                boxEntity = box
            } catch {
                trackingError = "Failed to load box model: \(error.localizedDescription)"
            }

            // Spawn cubes
            spawnCubes()

            sceneState = .active

            if let panel = attachments.entity(for: "controls") {
                panel.position = [0, 1.5, -1.2]
                content.add(panel)
            }
        } attachments: {
            Attachment(id: "controls") {
                SceneControlPanel(
                    sceneName: "Object Pickup",
                    instruction: instructionText,
                    isReady: false,
                    hasDropped: sceneState == .complete,
                    onDrop: { },
                    onReset: resetScene,
                    onReturn: { await dismissImmersiveSpace() }
                )
            }
        }
        .task {
            await runHandTracking()
        }
    }

    // MARK: - Instruction Text

    private var instructionText: String {
        if let error = trackingError { return error }
        switch sceneState {
        case .setup:
            return "Setting up…"
        case .active:
            return "Pick up the objects and place them in the box. (\(placedCount)/5)"
        case .complete:
            return "All objects collected! Check the main window."
        }
    }

    // MARK: - Cube Spawning

    private func spawnCubes() {
        let mesh = MeshResource.generateBox(size: cubeSize)
        var positions: [SIMD3<Float>] = []

        for i in 0..<5 {
            let material = SimpleMaterial(
                color: cubeColors[i],
                roughness: 0.3,
                isMetallic: false
            )
            let cube = ModelEntity(mesh: mesh, materials: [material])

            // Generate random floor position with minimum spacing
            var position: SIMD3<Float>
            var attempts = 0
            repeat {
                position = SIMD3<Float>(
                    Float.random(in: -0.75...0.75),
                    cubeSize / 2.0, // half height so cube sits on floor
                    Float.random(in: -1.5...(-0.5))
                )
                attempts += 1
            } while positions.contains(where: { simd_distance($0, position) < 0.3 }) && attempts < 50

            positions.append(position)
            cube.position = position
            rootEntity.addChild(cube)
            cubeEntities.append(cube)
        }
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
            guard sceneState == .active else { continue }

            let thumbTip = skeleton.joint(.thumbTip)
            let indexTip = skeleton.joint(.indexFingerTip)
            guard thumbTip.isTracked, indexTip.isTracked else { continue }

            let thumbWorld = anchor.originFromAnchorTransform * thumbTip.anchorFromJointTransform
            let indexWorld = anchor.originFromAnchorTransform * indexTip.anchorFromJointTransform

            let thumbPos = SIMD3<Float>(thumbWorld.columns.3.x, thumbWorld.columns.3.y, thumbWorld.columns.3.z)
            let indexPos = SIMD3<Float>(indexWorld.columns.3.x, indexWorld.columns.3.y, indexWorld.columns.3.z)

            let pinchDistance = simd_distance(thumbPos, indexPos)
            let pinchMidpoint = (thumbPos + indexPos) / 2.0

            // Pinch state with hysteresis
            let wasPinching = isPinching
            if pinchDistance < pinchThreshold {
                isPinching = true
            } else if pinchDistance > releaseThreshold {
                isPinching = false
            }

            if isPinching {
                if heldCubeIndex == nil && !wasPinching {
                    // Just started pinching — try to grab nearest unplaced cube
                    tryGrabCube(near: pinchMidpoint)
                }

                // Move held cube to pinch midpoint
                if let idx = heldCubeIndex {
                    cubeEntities[idx].position = pinchMidpoint
                }
            } else if wasPinching && !isPinching {
                // Just released — check if cube is near box
                if let idx = heldCubeIndex {
                    releaseCube(index: idx)
                }
            }
        }
    }

    // MARK: - Grab / Release

    private func tryGrabCube(near point: SIMD3<Float>) {
        var closestIndex: Int?
        var closestDist: Float = grabRadius

        for (i, cube) in cubeEntities.enumerated() {
            guard cube.isEnabled else { continue } // skip placed cubes
            let dist = simd_distance(cube.position, point)
            if dist < closestDist {
                closestDist = dist
                closestIndex = i
            }
        }

        heldCubeIndex = closestIndex
    }

    private func releaseCube(index: Int) {
        let cube = cubeEntities[index]
        let boxOpeningPos = boxDropZoneCenter()

        if simd_distance(cube.position, boxOpeningPos) < dropZoneRadius {
            // Placed in box — animate to box center, then disable
            placedCount += 1
            heldCubeIndex = nil

            cube.move(
                to: Transform(translation: boxOpeningPos),
                relativeTo: rootEntity,
                duration: 0.2,
                timingFunction: .easeOut
            )

            // Play chime and speak encouragement
            let count = placedCount
            let player = chimePlayer
            let synth = speechSynthesizer
            let phrase = encouragements[count - 1]
            let audioPos = boxOpeningPos

            Task {
                try? await Task.sleep(nanoseconds: 200_000_000) // wait for snap animation
                cube.isEnabled = false

                player.play(at: audioPos)
                let utterance = AVSpeechUtterance(string: phrase)
                utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85
                synth.speak(utterance)

                if count >= 5 {
                    try? await Task.sleep(nanoseconds: 1_500_000_000) // let speech finish
                    guard sceneState == .active else { return } // cancelled by reset
                    sceneState = .complete
                    appModel.showCongratulations = true
                }
            }
        } else {
            // Dropped outside box — cube stays where it is, still pickable
            heldCubeIndex = nil
        }
    }

    /// Center of the box drop zone — box position raised to the opening height.
    private func boxDropZoneCenter() -> SIMD3<Float> {
        guard let box = boxEntity else { return boxPosition }
        let bounds = box.visualBounds(relativeTo: nil)
        let openingY = bounds.max.y
        return SIMD3<Float>(boxPosition.x, openingY, boxPosition.z)
    }

    // MARK: - Reset

    private func resetScene() {
        speechSynthesizer.stopSpeaking(at: .immediate)

        // Remove all cubes
        for cube in cubeEntities {
            cube.removeFromParent()
        }
        cubeEntities.removeAll()

        // Respawn cubes at new random positions
        spawnCubes()

        placedCount = 0
        heldCubeIndex = nil
        isPinching = false
        sceneState = .active
        appModel.showCongratulations = false
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Threshold/Scenes/ObjectPickupSceneView.swift
git commit -m "feat: implement ObjectPickupSceneView with pinch grip, audio, and congratulations"
```

---

### Task 5: Final verification

- [ ] **Step 1: Verify all files are saved and consistent**

Open the project in Xcode and verify:
1. `AppModel.swift` — `SceneType` has `.nail` and `.objectPickup`, `showCongratulations` exists
2. `ThresholdApp.swift` — both `NailScene` and `ObjectPickupScene` ImmersiveSpaces registered
3. `ContentView.swift` — Therapy tab uses `sceneCategoryView(for: .therapy)`, `CongratulationsView` exists, body handles `showCongratulations`
4. `ObjectPickupSceneView.swift` — compiles, references `"Box"` asset name

```bash
open Threshold.xcodeproj
```

- [ ] **Step 2: Verify asset names**

Confirm these exist in `Packages/RealityKitContent/Sources/RealityKitContent/RealityKitContent.rkassets/`:
- `Box.usda` — loaded as `Entity(named: "Box", in: realityKitContentBundle)`

- [ ] **Step 3: Build in Xcode**

Use Xcode's Build button (Cmd+B) targeting the visionOS Simulator or device. Fix any compilation errors.

SourceKit may report false positives like `'HandTrackingProvider' is unavailable in macOS`. These are not real errors — the visionOS build target resolves them.

- [ ] **Step 4: Run in Simulator or device**

Test the flow:
1. App launches → TabView with Education and Therapy tabs
2. Therapy tab shows "Object Pickup" card
3. Tap card → immersive space opens
4. 5 colored cubes on the floor, box to the right
5. Pinch grip (thumb + index) on right hand near a cube → cube attaches to hand
6. Release pinch near box → cube snaps to box, chime + speech plays, counter updates
7. Repeat for all 5 cubes
8. After 5th cube → main window shows "You Did It!" congratulatory screen
9. Tap "Done" → immersive space dismisses, back to scene library
10. Reset button respawns cubes at new random positions
