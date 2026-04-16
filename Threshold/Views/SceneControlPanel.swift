//
//  SceneControlPanel.swift
//  Threshold
//
//  Reusable floating control panel shown as a RealityView attachment
//  during immersive scenes. Provides action, reset, and return controls.
//

import SwiftUI

struct SceneControlPanel: View {

    let sceneName: String
    let instruction: String
    let isReady: Bool
    let hasDropped: Bool
    let actionLabel: String
    let actionIcon: String
    let resetLabel: String
    let onMark: (() -> Void)?
    let onDrop: () -> Void
    let onReset: () -> Void
    let onReturn: () async -> Void

    /// Convenience init with defaults matching the drop-style scenes.
    init(
        sceneName: String,
        instruction: String,
        isReady: Bool,
        hasDropped: Bool,
        actionLabel: String = "Drop",
        actionIcon: String = "arrow.down.circle.fill",
        resetLabel: String = "Reset",
        onMark: (() -> Void)? = nil,
        onDrop: @escaping () -> Void,
        onReset: @escaping () -> Void,
        onReturn: @escaping () async -> Void
    ) {
        self.sceneName = sceneName
        self.instruction = instruction
        self.isReady = isReady
        self.hasDropped = hasDropped
        self.actionLabel = actionLabel
        self.actionIcon = actionIcon
        self.resetLabel = resetLabel
        self.onMark = onMark
        self.onDrop = onDrop
        self.onReset = onReset
        self.onReturn = onReturn
    }

    var body: some View {
        VStack(spacing: 20) {
            // Title
            Text(sceneName)
                .font(.title.bold())

            // Contextual instruction
            Text(instruction)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            // Action buttons
            HStack(spacing: 14) {
                if isReady {
                    Button(action: onDrop) {
                        Label(actionLabel, systemImage: actionIcon)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }

                if hasDropped {
                    Button(action: onReset) {
                        Label(resetLabel, systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task { await onReturn() }
                    } label: {
                        Label("Library", systemImage: "square.grid.2x2")
                    }
                    .buttonStyle(.bordered)
                }

                // Pre-action state: show Mark (if provided) and Back
                if !isReady && !hasDropped {
                    if let onMark {
                        Button(action: onMark) {
                            Label("Mark Foot", systemImage: "scope")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                    }
                    Button {
                        Task { await onReturn() }
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(36)
        .frame(width: 500)
        .glassBackgroundEffect()
    }
}

// MARK: - Previews

#Preview("Nail — Pre-action") {
    SceneControlPanel(
        sceneName: "Nail in the Glove",
        instruction: "Place your right hand flat on the wall and spread your fingers wide.",
        isReady: false,
        hasDropped: false,
        onDrop: { },
        onReset: { },
        onReturn: { }
    )
}

#Preview("Nail — Ready") {
    SceneControlPanel(
        sceneName: "Nail in the Glove",
        instruction: "Hold still. Tap Strike when ready.",
        isReady: true,
        hasDropped: false,
        actionLabel: "Strike",
        actionIcon: "hammer.fill",
        onDrop: { },
        onReset: { },
        onReturn: { }
    )
}

#Preview("Nail — Post-action") {
    SceneControlPanel(
        sceneName: "Nail in the Glove",
        instruction: "Check the main window for what just happened.",
        isReady: false,
        hasDropped: true,
        onDrop: { },
        onReset: { },
        onReturn: { }
    )
}

#Preview("Pickup — Active") {
    SceneControlPanel(
        sceneName: "Object Pickup",
        instruction: "Pinch objects with your right hand and place them in the box. (2/5)",
        isReady: false,
        hasDropped: false,
        onDrop: { },
        onReset: { },
        onReturn: { }
    )
}

#Preview("Pickup — Complete") {
    SceneControlPanel(
        sceneName: "Object Pickup",
        instruction: "All objects collected! Check the main window.",
        isReady: false,
        hasDropped: true,
        onDrop: { },
        onReset: { },
        onReturn: { }
    )
}
