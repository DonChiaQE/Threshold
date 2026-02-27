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

    // MARK: - Scene Definitions

    /// Each scene type maps to a registered ImmersiveSpace ID.
    enum SceneType: String, CaseIterable, Identifiable {
        case blockDrop = "BlockDropScene"
        case smoke = "SmokeScene"
        case hammer = "HammerScene"
        case dumbbell = "DumbbellScene"
        case protectometerLab = "ProtectometerLabScene"
        case gloves = "gloves"
        case cactus = "cactus"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .blockDrop: "Block Drop"
            case .smoke: "Smoke"
            case .hammer: "Hammer (Arm)"
            case .dumbbell: "Dumbbell (Foot)"
            case .protectometerLab: "Protectometer Lab"
            case .gloves: "The Glove"
            case .cactus: "The Cactus"
            }
        }

        var subtitle: String {
            switch self {
            case .blockDrop: "Watch a block fall in front of you. A simple intro to get started."
            case .smoke: "Smoke fills the space around you. An environmental threat scenario."
            case .hammer: "Uses hand tracking to position a near-miss drop beside your arm."
            case .dumbbell: "Mark your foot position with gaze, then watch a near-miss drop."
            case .protectometerLab: "Drag DIM and SIM cards onto the Protectometer to explore how the brain weighs danger and safety."
            case .gloves: "Your brain predicts danger from a worn glove."
            case .cactus: "Hurt does not equal harm."
            }
        }

        var systemImage: String {
            switch self {
            case .blockDrop: "cube.fill"
            case .smoke: "smoke.fill"
            case .hammer: "hammer.fill"
            case .dumbbell: "dumbbell.fill"
            case .protectometerLab: "gauge.with.needle.fill"
            case .gloves: "hand.raised.fill"
            case .cactus: "leaf.fill"
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
}
