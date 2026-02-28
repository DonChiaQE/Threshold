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
        case hammer = "HammerScene"
        case dumbbell = "DumbbellScene"
        case cactus = "cactus"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .hammer: "Hammer (Arm)"
            case .dumbbell: "Dumbbell (Foot)"
            case .cactus: "The Cactus"
            }
        }

        var subtitle: String {
            switch self {
            case .hammer: "Uses hand tracking to position a near-miss drop beside your arm."
            case .dumbbell: "Mark your foot position with gaze, then watch a near-miss drop."
            case .cactus: "Hurt does not equal harm."
            }
        }

        var systemImage: String {
            switch self {
            case .hammer: "hammer.fill"
            case .dumbbell: "dumbbell.fill"
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
