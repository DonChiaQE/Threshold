# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

This is an Apple Vision Pro (visionOS) app. There is no CLI build or test workflow — all building and running is done through Xcode.

```bash
# Open in Xcode
open Threshold.xcodeproj
```

Deploy to a physical Vision Pro or the visionOS Simulator via Xcode's Run button. There are no unit tests.

## Architecture

**Threshold** is a pain neuroscience education app built on visionOS. Each scene is a self-contained immersive experience demonstrating "near-miss" scenarios to help users distinguish anticipated pain from actual harm.

### Scene lifecycle

`ThresholdApp.swift` registers each scene as an `ImmersiveSpace` with `.mixed` immersion style. `ContentView` is the scene library (window). `AppModel` (shared via `.environment`) tracks `immersiveSpaceState` and `activeScene`.

To add a new scene:
1. Add a case to `AppModel.SceneType` with a raw string ID, `title`, `subtitle`, and `systemImage`.
2. Create a `FooSceneView.swift` following the patterns below.
3. Register an `ImmersiveSpace(id: AppModel.SceneType.foo.rawValue)` block in `ThresholdApp.swift`.

### Scene view pattern

Every scene view follows this structure:

```swift
struct FooSceneView: View {
    @Environment(AppModel.self) var appModel
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace

    @State private var rootEntity = Entity()
    // other @State...

    // ARKit sessions declared as `let` (not @State)
    private let arSession = ARKitSession()
    private let worldTracking = WorldTrackingProvider() // or HandTrackingProvider

    var body: some View {
        RealityView { (content: inout RealityViewContent, attachments: RealityViewAttachments) in
            content.add(rootEntity)
            if let panel = attachments.entity(for: "controls") {
                panel.position = [0, 1.5, -1.2]
                content.add(panel)
            }
        } attachments: {
            Attachment(id: "controls") {
                SceneControlPanel(...)
            }
        }
        .task { await runTracking() }
    }
}
```

The **explicit type annotation** on the RealityView closure — `(content: inout RealityViewContent, attachments: RealityViewAttachments)` — is required when the closure body is non-trivial; omitting it causes Swift type-checker crashes ("Failed to produce diagnostic").

### ARKit tracking patterns

- **Device gaze → floor**: `WorldTrackingProvider` + `queryDeviceAnchor(atTimestamp:)` → project forward vector to y=0 plane. See `DumbbellSceneView.runDeviceTracking()`.
- **Hand tracking**: `HandTrackingProvider` + `for await update in handTracking.anchorUpdates`. See `HammerSceneView.runHandTracking()`.
- ARKit sessions are declared as `let` properties on the view struct, not `@State`.
- `Info.plist` must include `NSWorldSensingUsageDescription` for `WorldTrackingProvider` and `NSHandsTrackingUsageDescription` for `HandTrackingProvider`.

### Animation

Use `entity.move(to: Transform, relativeTo:, duration:, timingFunction:)` for all object movement — **not** `PhysicsBodyComponent` with a `material:` parameter (that initialiser overload does not exist in this SDK). `BlockDropSceneView` uses `PhysicsBodyComponent(shapes:mass:mode:)` (no `material:`) for gravity-based dropping, which is the only valid physics pattern.

For multi-stage arcs, chain sequential `cube.move()` calls inside a `Task` with `Task.sleep` between stages.

### SceneControlPanel

`SceneControlPanel` (`SceneControlPanel.swift`) is a reusable SwiftUI attachment panel. Key parameters:
- `isReady: Bool` — shows the primary action button (red "Drop" by default).
- `hasDropped: Bool` — shows Reset + Library buttons.
- `actionLabel`/`actionIcon`/`resetLabel` — override button labels (used by SmokeSceneView).
- `onMark: (() -> Void)?` — optional; shows a blue "Mark Foot" button in the pre-action state.

### Spatial audio

`DumbbellSceneView` contains `ThudAudioPlayer`, a self-contained `AVAudioEngine` + `AVAudioEnvironmentNode` class with `.HRTFHQ` binaural rendering. Mark it `@unchecked Sendable` and hold it in `@State` to keep it alive for the scene lifetime. Capture it as a local `let` before entering a `Task` closure.

### SourceKit false positives

SourceKit analyses Swift files in a macOS context and reports errors like `'HandTrackingProvider' is unavailable in macOS` or `Cannot find 'AppModel' in scope`. These are **not real errors** — the visionOS build target resolves them correctly. Ignore any SourceKit diagnostic that references macOS availability or missing visionOS-only types.

### Materials

Only use `SimpleMaterial(color: UIColor, roughness: Float, isMetallic: Bool)`. `UnlitMaterial` and `PhysicallyBasedMaterial` have had API incompatibilities in this project — avoid them.
