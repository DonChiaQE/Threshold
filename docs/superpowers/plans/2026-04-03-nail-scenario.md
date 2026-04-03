# Nail in the Glove — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the "Nail in the Glove" pain neuroscience education scenario — a nail appears to be hammered through a gloved hand, but the reveal shows it passed between the fingers.

**Architecture:** Single new scene (`NailSceneView`) using ARKit `HandTrackingProvider` for right-hand tracking. UI refactored from flat card grid to native visionOS `TabView` with Education/Therapy tabs. `AppModel` gains a `showEducation` flag so the main window swaps to educational content after the reveal.

**Tech Stack:** SwiftUI, RealityKit, ARKit (HandTrackingProvider), visionOS 2.0+

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `Threshold/App/AppModel.swift` | Modify | Add `nail` to `SceneType`, add `SceneCategory` enum, add `showEducation` flag |
| `Threshold/Views/ContentView.swift` | Modify | Replace flat card grid with `TabView(.sidebarAdaptable)`, add `EducationDetailView` |
| `Threshold/App/ThresholdApp.swift` | Modify | Register `NailScene` ImmersiveSpace, remove old scene registrations |
| `Threshold/Scenes/NailSceneView.swift` | Create | Complete nail scenario — hand tracking, glove, nail, hammer, animation, reveal |

---

### Task 1: AppModel — Add nail scene, categories, and education flag

**Files:**
- Modify: `Threshold/App/AppModel.swift`

- [ ] **Step 1: Replace SceneType enum and add category system**

Replace the entire contents of `AppModel.swift` with:

```swift
//
//  AppModel.swift
//  Threshold
//
//  Created by Don Chia on 13/2/26.
//

import SwiftUI

/// Maintains app-wide state for scene management and immersive space lifecycle.
@MainActor
@Observable
class AppModel {

    // MARK: - Scene Categories

    enum SceneCategory: String, CaseIterable, Identifiable {
        case education = "Education"
        case therapy = "Therapy"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .education: "book.fill"
            case .therapy: "cross.case.fill"
            }
        }
    }

    // MARK: - Scene Definitions

    /// Each scene type maps to a registered ImmersiveSpace ID.
    enum SceneType: String, CaseIterable, Identifiable {
        case nail = "NailScene"

        var id: String { rawValue }

        var category: SceneCategory {
            switch self {
            case .nail: .education
            }
        }

        var title: String {
            switch self {
            case .nail: "Nail in the Glove"
            }
        }

        var subtitle: String {
            switch self {
            case .nail: "A nail appears to pierce your hand — but the reveal shows it passed harmlessly between your fingers."
            }
        }

        var systemImage: String {
            switch self {
            case .nail: "hammer.fill"
            }
        }
    }

    // MARK: - Immersive Space State

    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }

    var immersiveSpaceState = ImmersiveSpaceState.closed
    var activeScene: SceneType?

    /// When true, ContentView shows the educational debrief instead of the scene library.
    var showEducation = false
}
```

- [ ] **Step 2: Commit**

```bash
git add Threshold/App/AppModel.swift
git commit -m "refactor: replace SceneType with nail-only enum and add category system"
```

---

### Task 2: ContentView — TabView with Education/Therapy tabs and education overlay

**Files:**
- Modify: `Threshold/Views/ContentView.swift`

- [ ] **Step 1: Replace ContentView with TabView layout and education overlay**

Replace the entire contents of `ContentView.swift` with:

```swift
//
//  ContentView.swift
//  Threshold
//
//  Main window — TabView with Education and Therapy categories.
//  When appModel.showEducation is true, an overlay shows the
//  educational debrief text instead of the scene library.
//

import SwiftUI

struct ContentView: View {

    @Environment(AppModel.self) var appModel
    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace

    var body: some View {
        Group {
            if appModel.showEducation {
                EducationDetailView {
                    appModel.showEducation = false
                    await dismissImmersiveSpace()
                }
            } else {
                tabView
            }
        }
    }

    // MARK: - Tab View

    private var tabView: some View {
        TabView {
            Tab("Education", systemImage: "book.fill") {
                sceneCategoryView(for: .education)
            }

            Tab("Therapy", systemImage: "cross.case.fill") {
                therapyPlaceholderView
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }

    // MARK: - Education Tab Content

    private func sceneCategoryView(for category: AppModel.SceneCategory) -> some View {
        let scenes = AppModel.SceneType.allCases.filter { $0.category == category }

        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(category.rawValue)
                        .font(.largeTitle.bold())
                    Text("Pain neuroscience education scenarios")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)

                // Scene cards
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 260, maximum: 320))],
                    spacing: 20
                ) {
                    ForEach(scenes) { scene in
                        SceneCard(scene: scene) {
                            await launchScene(scene)
                        }
                        .disabled(appModel.immersiveSpaceState == .inTransition)
                    }
                }
            }
            .padding(40)
        }
    }

    // MARK: - Therapy Tab Placeholder

    private var therapyPlaceholderView: some View {
        VStack(spacing: 16) {
            Image(systemName: "cross.case.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            Text("Coming soon")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Clinical rehabilitation exercises will appear here.")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Scene Launching

    private func launchScene(_ scene: AppModel.SceneType) async {
        if appModel.immersiveSpaceState == .open {
            await dismissImmersiveSpace()
        }

        appModel.immersiveSpaceState = .inTransition

        let result = await openImmersiveSpace(id: scene.rawValue)
        switch result {
        case .opened:
            appModel.activeScene = scene
        case .userCancelled, .error:
            fallthrough
        @unknown default:
            appModel.immersiveSpaceState = .closed
            appModel.activeScene = nil
        }
    }
}

// MARK: - Scene Card

struct SceneCard: View {
    let scene: AppModel.SceneType
    let action: () async -> Void

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: scene.systemImage)
                    .font(.system(size: 36))
                    .foregroundStyle(.tint)
                    .frame(height: 44)

                VStack(alignment: .leading, spacing: 6) {
                    Text(scene.title)
                        .font(.headline)
                    Text(scene.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 20))
    }
}

// MARK: - Education Detail View

struct EducationDetailView: View {
    let onDone: () async -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text("The Nail That Never Was")
                    .font(.largeTitle.bold())

                VStack(alignment: .leading, spacing: 12) {
                    Text("What just happened")
                        .font(.title2.bold())
                    Text("The nail appeared to pierce your hand — but it passed harmlessly between your fingers. Your brain may have anticipated pain, even though no injury occurred.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("The Original Story")
                        .font(.title2.bold())
                    Text("In 1995, a construction worker jumped onto a plank and a 15cm nail drove straight through his boot. He was in agony — rushed to A&E in severe pain, requiring sedation. But when doctors removed the boot, they found the nail had passed between his toes. There was no wound. No tissue damage. The pain was real, but it was generated entirely by the brain's expectation of injury.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("The Takeaway")
                        .font(.title2.bold())
                    Text("Pain is a protective response, not a damage report. Your brain creates pain based on perceived threat — not just what's happening in your body. Understanding this is the first step in learning to retrain your pain response.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task { await onDone() }
                } label: {
                    Label("Done", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            }
            .padding(40)
            .frame(maxWidth: 600, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
```

- [ ] **Step 2: Commit**

```bash
git add Threshold/Views/ContentView.swift
git commit -m "refactor: replace flat card grid with TabView and add education debrief view"
```

---

### Task 3: ThresholdApp — Register NailScene and remove old scene registrations

**Files:**
- Modify: `Threshold/App/ThresholdApp.swift`

- [ ] **Step 1: Replace ThresholdApp body with NailScene registration only**

Replace the entire contents of `ThresholdApp.swift` with:

```swift
//
//  ThresholdApp.swift
//  Threshold
//
//  Created by Don Chia on 13/2/26.
//

import SwiftUI

@main
struct ThresholdApp: App {

    @State private var appModel = AppModel()

    var body: some Scene {

        // Main window – scene library
        WindowGroup {
            ContentView()
                .environment(appModel)
        }

        // Nail in the Glove — pain neuroscience education
        ImmersiveSpace(id: AppModel.SceneType.nail.rawValue) {
            NailSceneView()
                .environment(appModel)
                .onAppear { appModel.immersiveSpaceState = .open }
                .onDisappear {
                    appModel.immersiveSpaceState = .closed
                    appModel.activeScene = nil
                }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Threshold/App/ThresholdApp.swift
git commit -m "refactor: register NailScene only, remove old scene registrations"
```

---

### Task 4: NailSceneView — Complete implementation

**Files:**
- Create: `Threshold/Scenes/NailSceneView.swift`

- [ ] **Step 1: Create NailSceneView.swift with the complete scene implementation**

Create the file at `Threshold/Scenes/NailSceneView.swift` with:

```swift
//
//  NailSceneView.swift
//  Threshold
//
//  Immersive scene: "Nail in the Glove" — A nail appears to be hammered
//  through the user's gloved right hand. After the animation, the glove
//  fades to reveal the nail passed harmlessly between the fingers.
//
//  Based on the 1995 "nail in the boot" case study for pain neuroscience
//  education.
//

import SwiftUI
import RealityKit
import ARKit
import RealityKitContent

struct NailSceneView: View {

    @Environment(AppModel.self) var appModel
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace

    // MARK: - Scene State

    enum SceneState {
        case waitingForHand
        case gloveAppearing
        case ready
        case animating
        case revealing
        case educating
    }

    @State private var sceneState: SceneState = .waitingForHand

    // MARK: - Entity References

    @State private var rootEntity = Entity()
    @State private var gloveEntity: Entity?
    @State private var nailEntity: Entity?
    @State private var hammerEntity: Entity?

    // MARK: - Tracking State

    @State private var trackingError: String?
    @State private var fingersSpread = false

    /// Cached nail target position (midpoint between index and middle knuckles).
    @State private var nailPosition: SIMD3<Float> = .zero

    // MARK: - ARKit (declared as `let` — not @State)

    private let arSession = ARKitSession()
    private let handTracking = HandTrackingProvider()

    // MARK: - Constants

    /// Minimum distance (metres) between index and middle knuckles to count as "spread".
    private let spreadThreshold: Float = 0.04

    /// How far above the knuckle midpoint the nail starts (metres).
    private let nailHoverHeight: Float = 0.05

    /// How far above the nail the hammer hovers (metres).
    private let hammerHoverHeight: Float = 0.15

    /// How far the nail drives down during the strike (metres).
    private let nailDriveDistance: Float = 0.04

    // MARK: - Body

    var body: some View {
        RealityView { (content: inout RealityViewContent, attachments: RealityViewAttachments) in
            content.add(rootEntity)

            if let panel = attachments.entity(for: "controls") {
                panel.position = [0, 1.5, -1.2]
                content.add(panel)
            }
        } attachments: {
            Attachment(id: "controls") {
                SceneControlPanel(
                    sceneName: "Nail in the Glove",
                    instruction: instructionText,
                    isReady: sceneState == .ready,
                    hasDropped: sceneState == .educating,
                    actionLabel: "Strike",
                    actionIcon: "hammer.fill",
                    onDrop: performStrike,
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
        case .waitingForHand:
            if !fingersSpread {
                return "Place your right hand flat on the table and spread your fingers wide."
            }
            return "Detecting hand…"
        case .gloveAppearing:
            return "Fitting glove…"
        case .ready:
            return "Hold still. Tap Strike when ready."
        case .animating:
            return "Striking…"
        case .revealing:
            return "Look at your hand…"
        case .educating:
            return "Check the main window for what just happened."
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

            // Always update glove position when glove is attached
            let wristJoint = skeleton.joint(.wrist)
            if wristJoint.isTracked, let glove = gloveEntity {
                let worldWristMatrix = anchor.originFromAnchorTransform * wristJoint.anchorFromJointTransform
                glove.setTransformMatrix(worldWristMatrix, relativeTo: nil)
            }

            // Check finger spread and compute nail position
            let indexKnuckle = skeleton.joint(.indexFingerKnuckle)
            let middleKnuckle = skeleton.joint(.middleFingerKnuckle)
            guard indexKnuckle.isTracked, middleKnuckle.isTracked else { continue }

            let indexWorld = anchor.originFromAnchorTransform * indexKnuckle.anchorFromJointTransform
            let middleWorld = anchor.originFromAnchorTransform * middleKnuckle.anchorFromJointTransform

            let indexPos = SIMD3<Float>(indexWorld.columns.3.x, indexWorld.columns.3.y, indexWorld.columns.3.z)
            let middlePos = SIMD3<Float>(middleWorld.columns.3.x, middleWorld.columns.3.y, middleWorld.columns.3.z)

            let knuckleDistance = simd_distance(indexPos, middlePos)
            fingersSpread = knuckleDistance > spreadThreshold

            // Midpoint between the two knuckles, slightly above the hand surface
            let midpoint = (indexPos + middlePos) / 2.0
            nailPosition = SIMD3<Float>(midpoint.x, midpoint.y + nailHoverHeight, midpoint.z)

            // State transitions
            switch sceneState {
            case .waitingForHand:
                if fingersSpread && wristJoint.isTracked {
                    sceneState = .gloveAppearing
                    await attachGlove()
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    await placeNailAndHammer()
                    sceneState = .ready
                }
            case .ready:
                // Update nail and hammer position to track hand until strike
                nailEntity?.position = nailPosition
                hammerEntity?.position = SIMD3<Float>(
                    nailPosition.x,
                    nailPosition.y + hammerHoverHeight,
                    nailPosition.z
                )
            default:
                break
            }
        }
    }

    // MARK: - Model Loading

    private func attachGlove() async {
        do {
            let glove = try await Entity(named: "Gloves", in: realityKitContentBundle)
            glove.components.set(OpacityComponent(opacity: 0))
            rootEntity.addChild(glove)
            gloveEntity = glove

            // Fade glove in over 0.5s
            let steps = 10
            let interval: UInt64 = 500_000_000 / UInt64(steps)
            for i in 1...steps {
                let opacity = Float(i) / Float(steps)
                glove.components.set(OpacityComponent(opacity: opacity))
                try? await Task.sleep(nanoseconds: interval)
            }
        } catch {
            trackingError = "Failed to load glove model: \(error.localizedDescription)"
        }
    }

    private func placeNailAndHammer() async {
        // Load nail
        do {
            let nail = try await Entity(named: "Nail", in: realityKitContentBundle)
            nail.position = nailPosition
            rootEntity.addChild(nail)
            nailEntity = nail
        } catch {
            trackingError = "Failed to load nail model: \(error.localizedDescription)"
            return
        }

        // Load hammer
        do {
            let hammer = try await Entity(named: "Immersive", in: realityKitContentBundle)
            hammer.position = SIMD3<Float>(
                nailPosition.x,
                nailPosition.y + hammerHoverHeight,
                nailPosition.z
            )
            rootEntity.addChild(hammer)
            hammerEntity = hammer
        } catch {
            trackingError = "Failed to load hammer model: \(error.localizedDescription)"
        }
    }

    // MARK: - Strike Animation

    private func performStrike() {
        guard sceneState == .ready,
              let hammer = hammerEntity,
              let nail = nailEntity else { return }

        sceneState = .animating

        let hammerStartPos = hammer.position
        let nailStartPos = nail.position

        // Target: hammer moves down to nail head level
        let hammerStrikePos = SIMD3<Float>(
            nailStartPos.x,
            nailStartPos.y + 0.02, // just above nail head
            nailStartPos.z
        )

        // Target: nail drives down
        let nailDrivenPos = SIMD3<Float>(
            nailStartPos.x,
            nailStartPos.y - nailDriveDistance,
            nailStartPos.z
        )

        Task {
            // 1. Hammer swings down (0.3s)
            hammer.move(
                to: Transform(translation: hammerStrikePos),
                relativeTo: rootEntity,
                duration: 0.3,
                timingFunction: .easeIn
            )
            try? await Task.sleep(nanoseconds: 300_000_000)

            // 2. Nail drives down (0.7s)
            nail.move(
                to: Transform(translation: nailDrivenPos),
                relativeTo: rootEntity,
                duration: 0.7,
                timingFunction: .easeOut
            )
            try? await Task.sleep(nanoseconds: 700_000_000)

            // 3. Hammer lifts back up (0.4s)
            hammer.move(
                to: Transform(translation: hammerStartPos),
                relativeTo: rootEntity,
                duration: 0.4,
                timingFunction: .easeOut
            )
            try? await Task.sleep(nanoseconds: 400_000_000)

            // 4. Pause for tension (0.6s)
            try? await Task.sleep(nanoseconds: 600_000_000)

            // 5. Reveal — fade glove out (1.0s)
            sceneState = .revealing
            await fadeGloveOut()

            // 6. Trigger education view
            sceneState = .educating
            appModel.showEducation = true
        }
    }

    // MARK: - Glove Fade

    private func fadeGloveOut() async {
        guard let glove = gloveEntity else { return }
        let steps = 20
        let interval: UInt64 = 1_000_000_000 / UInt64(steps) // 1s total
        for i in 1...steps {
            let opacity = 1.0 - Float(i) / Float(steps)
            glove.components.set(OpacityComponent(opacity: opacity))
            try? await Task.sleep(nanoseconds: interval)
        }
    }

    // MARK: - Reset

    private func resetScene() {
        gloveEntity?.removeFromParent()
        gloveEntity = nil
        nailEntity?.removeFromParent()
        nailEntity = nil
        hammerEntity?.removeFromParent()
        hammerEntity = nil
        fingersSpread = false
        sceneState = .waitingForHand
        appModel.showEducation = false
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Threshold/Scenes/NailSceneView.swift
git commit -m "feat: implement NailSceneView with hand tracking, strike animation, and reveal"
```

---

### Task 5: Final verification and integration commit

- [ ] **Step 1: Verify all files are saved and consistent**

Open the project in Xcode and verify:
1. `AppModel.swift` — `SceneType` has only `.nail`, `SceneCategory` enum exists, `showEducation` property exists
2. `ThresholdApp.swift` — only `NailScene` ImmersiveSpace registered
3. `ContentView.swift` — `TabView` with Education/Therapy tabs, `EducationDetailView` shown when `showEducation` is true
4. `NailSceneView.swift` — compiles, references correct asset names (`"Gloves"`, `"Nail"`, `"Immersive"`)

```bash
open Threshold.xcodeproj
```

- [ ] **Step 2: Verify asset names match RealityKitContent bundle**

Confirm these asset names exist in `Packages/RealityKitContent/Sources/RealityKitContent/RealityKitContent.rkassets/`:
- `Gloves.usda` — loaded as `Entity(named: "Gloves", in: realityKitContentBundle)`
- `Nail.usda` — loaded as `Entity(named: "Nail", in: realityKitContentBundle)`
- `Immersive.usda` — loaded as `Entity(named: "Immersive", in: realityKitContentBundle)` (hammer model)

- [ ] **Step 3: Build in Xcode**

Use Xcode's Build button (Cmd+B) targeting the visionOS Simulator or device. Fix any compilation errors.

Note: SourceKit may report false positives like `'HandTrackingProvider' is unavailable in macOS`. These are not real errors — the visionOS build target resolves them. Only address errors that appear in the Xcode build log.

- [ ] **Step 4: Run in Simulator or device**

Test the flow:
1. App launches → TabView with Education tab visible, Therapy tab shows placeholder
2. Tap "Nail in the Glove" card → immersive space opens
3. Control panel shows "Place your right hand flat on the table and spread your fingers wide."
4. (On device) Place right hand flat, spread fingers → glove fades in, nail and hammer appear
5. Tap "Strike" → hammer drives nail down, then lifts
6. Glove fades out → nail visible between fingers
7. Main window shows "The Nail That Never Was" educational text
8. Tap "Done" → immersive space dismisses, back to scene library
