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
                .font(.title2.bold())

            // Contextual instruction
            Text(instruction)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

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
        .padding(28)
        .frame(width: 380)
        .glassBackgroundEffect()
    }
}
