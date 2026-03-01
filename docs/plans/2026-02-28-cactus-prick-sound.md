# Cactus Prick Sound Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Play a synthesised sharp noise snap at the cactus spine position the moment the user's fingertip triggers the scene.

**Architecture:** A self-contained `PrickSoundPlayer` class (modelled after `ThudAudioPlayer` in `DumbbellSceneView`) owns an `AVAudioEngine` + `AVAudioEnvironmentNode` for HRTF spatial audio. It synthesises a 50 ms white-noise burst with a fast exponential decay and a 3 kHz sine component for sharpness, then plays it at the world-space spine position. Held in `@State` on `CactusSceneView`. The existing dead-code "prick.wav" `Task` is replaced with a single synchronous `prickPlayer.play(at: spinePosition)` call.

**Tech Stack:** visionOS, AVFoundation (`AVAudioEngine`, `AVAudioEnvironmentNode`, `AVAudioPCMBuffer`), Swift

---

> **No unit tests.** Build in Xcode (⌘B) after each task. On-device testing confirms the sound fires at contact.

---

### Task 1: Add `PrickSoundPlayer` class

**Files:**
- Modify: `Threshold/Scenes/CactusSceneView.swift`

**Step 1: Insert the class above the `CactusSceneView` struct**

Find the line:

```swift
struct CactusSceneView: View {
```

Insert the following **immediately before** it (keep one blank line between the class and the struct):

```swift
// MARK: - Prick sound synthesiser

private final class PrickSoundPlayer: @unchecked Sendable {

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
        envNode.distanceAttenuationParameters.referenceDistance = 0.3
        envNode.distanceAttenuationParameters.rolloffFactor     = 1.0
        try? engine.start()
    }

    /// Synthesise and play a 50 ms sharp noise snap at `position` in world space.
    func play(at position: SIMD3<Float>) {
        let sampleRate: Double = 44_100
        let frameCount = AVAudioFrameCount(sampleRate * 0.05)   // 50 ms
        guard let buffer = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        let samples = buffer.floatChannelData![0]
        for i in 0..<Int(frameCount) {
            let t        = Double(i) / sampleRate
            let envelope = exp(-t * 80.0)                        // very fast decay
            let noise    = Double.random(in: -1.0...1.0) * 0.7  // white noise body
            let zing     = sin(2.0 * .pi * 3_000.0 * t) * 0.3  // 3 kHz for sharpness
            samples[i]   = Float(envelope * (noise + zing))
        }
        playerNode.position = AVAudio3DPoint(x: position.x, y: position.y, z: position.z)
        playerNode.scheduleBuffer(buffer)
        playerNode.play()
    }
}

```

**Step 2: Build in Xcode**

Product → Build (⌘B). Expected: build succeeds.

**Step 3: Commit**

```bash
git add Threshold/Scenes/CactusSceneView.swift
git commit -m "feat: add PrickSoundPlayer synthesising a sharp noise snap"
```

---

### Task 2: Wire `PrickSoundPlayer` into the scene

**Files:**
- Modify: `Threshold/Scenes/CactusSceneView.swift`

**Step 1: Add the player to the State section**

In `// MARK: - State`, after `@State private var speechSynthesizer = AVSpeechSynthesizer()`, add:

```swift
@State private var prickPlayer = PrickSoundPlayer()
```

**Step 2: Replace the dead "prick.wav" Task with a single play call**

In `triggerSequence()`, find and remove the entire dead-code block:

```swift
        Task {
            // Play prick sound (optional — requires "prick.wav" in bundle)
            if let url = Bundle.main.url(forResource: "prick", withExtension: "wav") {
                let player = try? AVAudioPlayer(contentsOf: url)
                player?.play()
                // Retain player for duration of playback
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
```

Replace it with a single synchronous call (no Task wrapper needed — `play(at:)` is non-blocking):

```swift
        prickPlayer.play(at: spinePosition)
```

`play(at:)` schedules the buffer and returns immediately; `AVAudioEngine` plays it on a background audio thread.

**Step 3: Build in Xcode**

Product → Build (⌘B). Expected: build succeeds.

**Step 4: Commit**

```bash
git add Threshold/Scenes/CactusSceneView.swift
git commit -m "feat: play synthesised prick sound at spine position on cactus contact"
```

---

## Summary of Changes

| File | Change |
|------|--------|
| `Threshold/Scenes/CactusSceneView.swift` | New `PrickSoundPlayer` class above struct; `@State private var prickPlayer` in State section; dead "prick.wav" Task replaced with `prickPlayer.play(at: spinePosition)` |
