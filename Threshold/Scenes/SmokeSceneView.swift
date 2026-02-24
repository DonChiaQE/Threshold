//
//  SmokeSceneView.swift
//  Threshold
//
//  Immersive scene: Smoke gradually fills the space around the user.
//  Uses RealityKit particle emitters placed in a ring at floor level
//  to create a rising, volumetric smoke effect.
//
//  This is an environmental threat scenario – it creates mild unease
//  about air quality but is completely harmless. Teaches that
//  environmental threat perception doesn't equal actual danger.
//

import SwiftUI
import RealityKit

struct SmokeSceneView: View {

    @Environment(AppModel.self) var appModel
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace

    // MARK: - State

    @State private var rootEntity = Entity()
    @State private var emitterEntities: [Entity] = []
    @State private var hasTriggered = false
    @State private var isFilled = false
    @State private var fillTask: Task<Void, Never>?

    // MARK: - Constants

    /// Total time for smoke to visually fill the space (seconds).
    private let fillDuration: TimeInterval = 12.0

    /// Emitter positions: ring around the user at floor level.
    /// Spread across front, sides, and behind to surround the user.
    private let emitterPositions: [SIMD3<Float>] = [
        [ 1.2, 0.05, -1.2],   // front-right
        [-1.2, 0.05, -1.2],   // front-left
        [ 1.2, 0.05,  1.2],   // back-right
        [-1.2, 0.05,  1.2],   // back-left
        [ 0.0, 0.05, -1.8],   // directly ahead
        [ 0.0, 0.05,  1.8],   // directly behind
    ]

    // MARK: - Body

    var body: some View {
        RealityView { content, attachments in
            content.add(rootEntity)

            if let panel = attachments.entity(for: "controls") {
                panel.position = [0, 1.5, -1.2]
                content.add(panel)
            }
        } attachments: {
            Attachment(id: "controls") {
                SceneControlPanel(
                    sceneName: "Smoke",
                    instruction: instructionText,
                    isReady: !hasTriggered,
                    hasDropped: hasTriggered,
                    actionLabel: "Start",
                    actionIcon: "play.circle.fill",
                    resetLabel: "Clear",
                    onDrop: startSmoke,
                    onReset: clearSmoke,
                    onReturn: { await dismissImmersiveSpace() }
                )
            }
        }
    }

    private var instructionText: String {
        if isFilled {
            return "The space is filled with smoke. It's completely harmless."
        }
        if hasTriggered {
            return "Smoke is filling the space around you…"
        }
        return "Tap Start to release smoke into the environment."
    }

    // MARK: - Smoke Control

    private func startSmoke() {
        hasTriggered = true

        // Create emitters around the user
        for position in emitterPositions {
            let emitter = makeSmokeEmitter()
            emitter.position = position
            rootEntity.addChild(emitter)
            emitterEntities.append(emitter)
        }

        // Mark as filled after the fill duration
        fillTask = Task {
            try? await Task.sleep(for: .seconds(fillDuration))
            guard !Task.isCancelled else { return }
            isFilled = true
        }
    }

    private func clearSmoke() {
        // Cancel any pending fill timer
        fillTask?.cancel()
        fillTask = nil

        // Remove all emitters (particles vanish immediately)
        for entity in emitterEntities {
            entity.removeFromParent()
        }
        emitterEntities.removeAll()

        hasTriggered = false
        isFilled = false
    }

    // MARK: - Particle Emitter

    private func makeSmokeEmitter() -> Entity {
        let entity = Entity()

        var emitter = ParticleEmitterComponent()

        // Emission shape: flat box at floor level, ~2 m² area per emitter
        emitter.emitterShape = .box
        emitter.emitterShapeSize = [1.8, 0.02, 1.8]
        emitter.birthLocation = .surface
        emitter.birthDirection = .normal

        // Particle behaviour
        emitter.mainEmitter.birthRate = 30
        emitter.mainEmitter.lifeSpan = 7.0
        emitter.mainEmitter.size = 0.20
        emitter.mainEmitter.acceleration = [0, 0.08, 0]         // upward drift drives motion
        emitter.mainEmitter.noiseStrength = 0.25                 // turbulence
        emitter.mainEmitter.vortexStrength = 0.15                // swirling motion

        // Appearance: gray/white, semi-transparent, fading out
        emitter.mainEmitter.color = .evolving(
            start: .single(.init(white: 0.82, alpha: 0.40)),
            end:   .single(.init(white: 0.60, alpha: 0.0))
        )
        emitter.mainEmitter.blendMode = .alpha

        emitter.isEmitting = true

        entity.components.set(emitter)
        return entity
    }
}
