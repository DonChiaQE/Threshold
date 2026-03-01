# Cactus Label + Narration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the post-trigger explanation obvious by (A) parenting the safe label to the cactus entity so it floats above the plant wherever it landed, and (B) narrating the message aloud with `AVSpeechSynthesizer` so it is heard even if the user is looking away.

**Architecture:** Two independent changes to `CactusSceneView.swift`. The label attachment is re-parented from `content` to `cactusEntity` with a position relative to the cactus. A single `AVSpeechSynthesizer` is held in `@State` (keeping it alive for the scene lifetime) and speaks when the green glow fires.

**Tech Stack:** visionOS, RealityKit, SwiftUI Attachments, AVFoundation (`AVSpeechSynthesizer`)

---

> **No unit tests.** Verify by building in Xcode (⌘B) after each task. On-device or Simulator testing confirms visual/audio behaviour.

---

### Task 1: Re-parent safe label to cactus and make it larger

The label currently sits at a fixed world position `[0, 1.7, -0.8]` and is added to `content`. It needs to be a child of `cactusEntity` so it moves with the cactus after surface placement and always appears directly above the plant.

**Files:**
- Modify: `Threshold/Scenes/CactusSceneView.swift`

**Step 1: Change the label position and parent**

In the `RealityView` initializer closure, find:

```swift
            // Safe label — always present, opacity driven by showSafeLabel state
            if let label = attachments.entity(for: "safeLabel") {
                label.position = [0, 1.7, -0.8]
                content.add(label)
            }
```

Replace with:

```swift
            // Safe label — parented to cactus so it floats above wherever the cactus landed
            if let label = attachments.entity(for: "safeLabel") {
                label.position = [0, 0.7, 0]  // 0.7 m above cactus entity origin
                cactusEntity?.addChild(label)
            }
```

Key points:
- `label.position` is now **relative to `cactusEntity`**, not world space.
- `cactusEntity` is set earlier in the same closure (the cactus load block runs first), so it is non-nil here.
- Do NOT call `content.add(label)` — parenting to `cactusEntity` already puts it in the scene graph.
- visionOS SwiftUI attachment entities automatically face the user (billboard behaviour is built in), so no extra configuration is needed.

**Step 2: Make the label larger and more prominent**

Find the `Attachment(id: "safeLabel")` block:

```swift
            Attachment(id: "safeLabel") {
                Text("Your skin is safe.\nYour brain just predicted danger.")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(20)
                    .frame(maxWidth: 320)
                    .glassBackgroundEffect()
                    .opacity(showSafeLabel ? 1 : 0)
            }
```

Replace with:

```swift
            Attachment(id: "safeLabel") {
                Text("Your skin is safe.\nYour brain just predicted danger.")
                    .font(.title.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(28)
                    .frame(maxWidth: 480)
                    .glassBackgroundEffect()
                    .opacity(showSafeLabel ? 1 : 0)
            }
```

Changes: `.title3` → `.title`, `maxWidth: 320` → `480`, `padding: 20` → `28`.

**Step 3: Build in Xcode**

Product → Build (⌘B). Expected: build succeeds with no errors.

**Step 4: Commit**

```bash
git add Threshold/Scenes/CactusSceneView.swift
git commit -m "feat: parent safe label to cactus entity and enlarge text"
```

---

### Task 2: Add AVSpeechSynthesizer narration

When the green glow fires (safety reappraisal moment), speak the message aloud. The synthesizer must be held in `@State` so it is not deallocated mid-speech. Stop speaking on reset.

**Files:**
- Modify: `Threshold/Scenes/CactusSceneView.swift`

**Step 1: Add the synthesizer to the State section**

In the `// MARK: - State` section, after `@State private var cactusPlaced = false`, add:

```swift
@State private var speechSynthesizer = AVSpeechSynthesizer()
```

`AVSpeechSynthesizer` is already available — `AVFoundation` is imported at the top of the file.

**Step 2: Speak the message when the green glow fires**

In `triggerSequence()`, find the sequence Task:

```swift
        Task {
            await animateRedGlow()
            try? await Task.sleep(nanoseconds: 1_500_000_000)  // 1.5 s pause
            await animateGreenGlow()
            showSafeLabel = true
            try? await Task.sleep(nanoseconds: 3_000_000_000)  // 3 s display
            showSafeLabel = false
        }
```

Replace with:

```swift
        Task {
            await animateRedGlow()
            try? await Task.sleep(nanoseconds: 1_500_000_000)  // 1.5 s pause
            await animateGreenGlow()
            // Narrate the reappraisal message aloud
            let utterance = AVSpeechUtterance(
                string: "Your skin is safe. Your brain just predicted danger."
            )
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85  // slightly slower for clarity
            speechSynthesizer.speak(utterance)
            showSafeLabel = true
            try? await Task.sleep(nanoseconds: 3_000_000_000)  // 3 s display
            showSafeLabel = false
        }
```

**Step 3: Stop speech on reset**

In `resetScene()`, add a stop call as the first line:

```swift
    private func resetScene() {
        speechSynthesizer.stopSpeaking(at: .immediate)
        redGlowEntity?.isEnabled = false
        greenGlowEntity?.isEnabled = false
        showSafeLabel = false
        hasTriggered = false
    }
```

**Step 4: Build in Xcode**

Product → Build (⌘B). Expected: build succeeds with no errors.

**Step 5: Commit**

```bash
git add Threshold/Scenes/CactusSceneView.swift
git commit -m "feat: narrate safety reappraisal message with AVSpeechSynthesizer"
```

---

## Summary of Changes

| File | Change |
|------|--------|
| `Threshold/Scenes/CactusSceneView.swift` | Label re-parented to cactus at `[0, 0.7, 0]`; font enlarged to `.title`; `AVSpeechSynthesizer` in `@State`; speech triggered at green glow; speech stopped on reset |

No other files change.

> **Tuning note:** The label position `[0, 0.7, 0]` may need adjustment on device depending on the cactus model height. If the label overlaps the plant, increase the y value (e.g. `0.9`). If it floats too high, reduce it.
