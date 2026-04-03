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
