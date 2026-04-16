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
    @State private var toyEntities: [Entity] = []

    // MARK: - Pickup State

    @State private var placedCount = 0
    @State private var encouragementText: String = ""
    @State private var showEncouragement: Bool = false

    // MARK: - Audio

    @State private var chimePlayer = ChimeSoundPlayer()
    @State private var speechSynthesizer = AVSpeechSynthesizer()

    /// Pick the best available English voice: premium > enhanced > default.
    private var bestVoice: AVSpeechSynthesisVoice? {
        let english = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
        return english.first(where: { $0.quality == .premium })
            ?? english.first(where: { $0.quality == .enhanced })
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    // MARK: - Constants

    private let toyNames = ["Toy1", "Toy2", "Toy3", "Toy4", "Toy5"]

    /// Max distance from toy to box interior to count as placed (metres).
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
                // Non-fatal: scene still works without a box model
            }

            guard boxEntity != nil else { return }

            // Spawn toys
            await spawnToys()

            sceneState = .active

            if let panel = attachments.entity(for: "controls") {
                panel.position = [0, 1.5, -1.2]
                content.add(panel)
            }

            if let encouragement = attachments.entity(for: "encouragement"),
               let box = boxEntity {
                // Attach above the box — position relative to box entity
                let boxBounds = box.visualBounds(relativeTo: box)
                encouragement.position = SIMD3<Float>(0, boxBounds.max.y + 0.15, 0)
                box.addChild(encouragement)
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

            Attachment(id: "encouragement") {
                if showEncouragement {
                    Text(encouragementText)
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 16)
                        .background(.ultraThinMaterial, in: .capsule)
                        .transition(.scale.combined(with: .opacity))
                        .animation(.easeOut(duration: 0.3), value: showEncouragement)
                }
            }
        }
        .task {
            // Periodically check if any toy has been moved near the box
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                if sceneState == .active {
                    checkToysInBox()
                }
            }
        }
    }

    // MARK: - Instruction Text

    private var instructionText: String {
        switch sceneState {
        case .setup:
            return "Setting up…"
        case .active:
            return "Pick up the toys and place them in the box. (\(placedCount)/5)"
        case .complete:
            return "All toys collected! Check the main window."
        }
    }

    // MARK: - Toy Spawning

    private func spawnToys() async {
        var positions: [SIMD3<Float>] = []

        for name in toyNames {
            guard let toy = try? await Entity(named: name, in: realityKitContentBundle) else {
                continue
            }

            // Generate random floor position with minimum spacing
            var position: SIMD3<Float>
            var attempts = 0
            repeat {
                position = SIMD3<Float>(
                    Float.random(in: -0.75...0.75),
                    0,
                    Float.random(in: -1.5...(-0.5))
                )
                attempts += 1
            } while positions.contains(where: { simd_distance($0, position) < 0.3 }) && attempts < 50

            positions.append(position)
            toy.position = position

            // Lift so the visual base sits on the floor
            let bounds = toy.visualBounds(relativeTo: nil)
            let boundsHeight = bounds.max.y - bounds.min.y
            if boundsHeight > 0.01 {
                toy.position.y += -bounds.min.y
            }

            // Collision (required for ManipulationComponent)
            let localBounds = toy.visualBounds(relativeTo: toy)
            let size = localBounds.max - localBounds.min
            if size.x > 0.001 {
                let shape = ShapeResource.generateBox(size: size)
                toy.components.set(CollisionComponent(shapes: [shape]))
            }

            // Enable native pinch-to-grab
            ManipulationComponent.configureEntity(toy)

            rootEntity.addChild(toy)
            toyEntities.append(toy)
        }
    }

    // MARK: - Box Detection

    private func checkToysInBox() {
        let boxOpeningPos = boxDropZoneCenter()

        for toy in toyEntities {
            guard toy.isEnabled else { continue }

            let toyWorldPos = toy.position(relativeTo: nil)
            if simd_distance(toyWorldPos, boxOpeningPos) < dropZoneRadius {
                placeToyInBox(toy, at: boxOpeningPos)
            }
        }
    }

    // MARK: - Placement

    private func placeToyInBox(_ toy: Entity, at boxOpeningPos: SIMD3<Float>) {
        placedCount += 1
        toy.isEnabled = false

        toy.move(
            to: Transform(translation: boxOpeningPos),
            relativeTo: rootEntity,
            duration: 0.2,
            timingFunction: .easeOut
        )

        let count = placedCount
        let player = chimePlayer
        let synth = speechSynthesizer
        let voice = bestVoice
        let phrase = encouragements[count - 1]
        let audioPos = boxOpeningPos

        encouragementText = phrase
        showEncouragement = true

        Task {
            try? await Task.sleep(nanoseconds: 200_000_000)

            player.play(at: audioPos)
            let utterance = AVSpeechUtterance(string: phrase)
            utterance.voice = voice
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85
            synth.speak(utterance)

            if count >= 5 {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard sceneState == .active else { return }
                sceneState = .complete
                appModel.showCongratulations = true
            } else {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                showEncouragement = false
            }
        }
    }

    /// Center of the box interior — midpoint between bottom and top of the box.
    private func boxDropZoneCenter() -> SIMD3<Float> {
        guard let box = boxEntity else { return boxPosition }
        let bounds = box.visualBounds(relativeTo: nil)
        let interiorY = (bounds.min.y + bounds.max.y) / 2.0
        return SIMD3<Float>(boxPosition.x, interiorY, boxPosition.z)
    }

    // MARK: - Reset

    private func resetScene() {
        speechSynthesizer.stopSpeaking(at: .immediate)
        showEncouragement = false

        for toy in toyEntities {
            toy.removeFromParent()
        }
        toyEntities.removeAll()

        Task { await spawnToys() }

        placedCount = 0
        sceneState = .active
        appModel.showCongratulations = false
    }
}
