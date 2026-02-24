//
//  ContentView.swift
//  Threshold
//
//  Scene library – the main window that lists available near-miss scenarios.
//

import SwiftUI

struct ContentView: View {

    @Environment(AppModel.self) var appModel
    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace

    var body: some View {
        VStack(spacing: 32) {

            // Header
            VStack(spacing: 8) {
                Text("Reframe")
                    .font(.largeTitle.bold())
                Text("Pain Neuroscience Education")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("Experience near-miss scenarios to understand the difference between anticipated pain and actual harm.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }

            // Scene cards
            HStack(spacing: 24) {
                ForEach(AppModel.SceneType.allCases) { scene in
                    SceneCard(scene: scene) {
                        await launchScene(scene)
                    }
                    .disabled(appModel.immersiveSpaceState == .inTransition)
                }
            }
        }
        .padding(40)
    }

    // MARK: - Scene Launching

    private func launchScene(_ scene: AppModel.SceneType) async {
        // Close any already-open immersive space first
        if appModel.immersiveSpaceState == .open {
            await dismissImmersiveSpace()
        }

        appModel.immersiveSpaceState = .inTransition

        let result = await openImmersiveSpace(id: scene.rawValue)
        switch result {
        case .opened:
            appModel.activeScene = scene
        case .userCancelled, .error:
            fallthrough
        @unknown default:
            appModel.immersiveSpaceState = .closed
            appModel.activeScene = nil
        }
    }
}

// MARK: - Scene Card

struct SceneCard: View {
    let scene: AppModel.SceneType
    let action: () async -> Void

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            VStack(spacing: 16) {
                Image(systemName: scene.systemImage)
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                    .frame(height: 56)

                VStack(spacing: 6) {
                    Text(scene.title)
                        .font(.headline)
                    Text(scene.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
            }
            .frame(width: 220, height: 190)
            .padding()
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 20))
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
