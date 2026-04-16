//
//  ContentView.swift
//  Threshold
//
//  Main window — TabView with Education and Therapy categories.
//  When appModel.showEducation is true, an overlay shows the
//  educational debrief text instead of the scene library.
//

import SwiftUI

struct ContentView: View {

    @Environment(AppModel.self) var appModel
    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace

    var body: some View {
        Group {
            if appModel.showEducation {
                EducationDetailView {
                    appModel.showEducation = false
                    await dismissImmersiveSpace()
                }
            } else if appModel.showCongratulations {
                CongratulationsView {
                    appModel.showCongratulations = false
                    await dismissImmersiveSpace()
                }
            } else if appModel.nailPhase != .inactive {
                NailSceneMainView(
                    phase: appModel.nailPhase,
                    onStrike: { appModel.strikeRequested = true },
                    onBack: { await dismissImmersiveSpace() }
                )
            } else {
                tabView
            }
        }
    }

    // MARK: - Tab View

    private var tabView: some View {
        TabView {
            Tab("Education", systemImage: "book.fill") {
                sceneCategoryView(for: .education)
            }

            Tab("Therapy", systemImage: "cross.case.fill") {
                sceneCategoryView(for: .therapy)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }

    // MARK: - Education Tab Content

    private func sceneCategoryView(for category: AppModel.SceneCategory) -> some View {
        let scenes = AppModel.SceneType.allCases.filter { $0.category == category }

        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(category.rawValue)
                        .font(.largeTitle.bold())
                    Text(category == .education
                         ? "Pain neuroscience education scenarios"
                         : "Clinical rehabilitation exercises")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)

                // Scene cards
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 260, maximum: 320))],
                    spacing: 20
                ) {
                    ForEach(scenes) { scene in
                        SceneCard(scene: scene) {
                            await launchScene(scene)
                        }
                        .disabled(appModel.immersiveSpaceState == .inTransition)
                    }
                }
            }
            .padding(40)
        }
    }

    // MARK: - Scene Launching

    private func launchScene(_ scene: AppModel.SceneType) async {
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
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: scene.systemImage)
                    .font(.system(size: 36))
                    .foregroundStyle(.tint)
                    .frame(height: 44)

                VStack(alignment: .leading, spacing: 6) {
                    Text(scene.title)
                        .font(.headline)
                    Text(scene.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 20))
    }
}

// MARK: - Education Detail View

// MARK: - Nail Scene Main View

struct NailSceneMainView: View {
    let phase: AppModel.NailPhase
    let onStrike: () -> Void
    let onBack: () async -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: phaseIcon)
                .font(.system(size: 64))
                .foregroundStyle(phaseIconColor)

            Text(phaseTitle)
                .font(.largeTitle.bold())

            Text(phaseDescription)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 500)

            // Buttons
            HStack(spacing: 16) {
                if phase == .ready {
                    Button(action: onStrike) {
                        Label("Strike", systemImage: "hammer.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.large)
                }

                if phase == .waitingForHand || phase == .gloveAppearing || phase == .ready {
                    Button {
                        Task { await onBack() }
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.bordered)
                }
            }

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var phaseIcon: String {
        switch phase {
        case .inactive: "hand.raised.fill"
        case .waitingForHand: "hand.raised.fill"
        case .gloveAppearing: "hand.raised.fill"
        case .ready: "hammer.fill"
        case .animating: "hammer.fill"
        case .revealing: "eye.fill"
        }
    }

    private var phaseIconColor: Color {
        switch phase {
        case .inactive, .waitingForHand, .gloveAppearing: .orange
        case .ready: .red
        case .animating: .red
        case .revealing: .blue
        }
    }

    private var phaseTitle: String {
        switch phase {
        case .inactive: ""
        case .waitingForHand: "Place Your Hand"
        case .gloveAppearing: "Fitting Glove…"
        case .ready: "Ready"
        case .animating: "Striking…"
        case .revealing: "Look at Your Hand"
        }
    }

    private var phaseDescription: String {
        switch phase {
        case .inactive: ""
        case .waitingForHand: "Place your right hand flat on the wall and spread your fingers wide."
        case .gloveAppearing: "A glove is being placed on your hand. Hold still."
        case .ready: "A nail is positioned above your gloved hand. When you tap Strike, a hammer will drive the nail down.\n\nKeep your hand still and watch what happens."
        case .animating: "Watch what happens to your hand…"
        case .revealing: "The glove is being removed. Look closely at your hand."
        }
    }
}

// MARK: - Education Detail View

struct EducationDetailView: View {
    let onDone: () async -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text("The Nail That Never Was")
                    .font(.largeTitle.bold())

                VStack(alignment: .leading, spacing: 12) {
                    Text("What just happened")
                        .font(.title2.bold())
                    Text("The nail appeared to pierce your hand, but it passed harmlessly between your fingers. Your brain may have anticipated pain, even though no injury occurred.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("The Original Story")
                        .font(.title2.bold())
                    Text("In 1995, a construction worker jumped onto a plank and a 15cm nail drove straight through his boot. He was in agony, rushed to A&E in severe pain, requiring sedation. But when doctors removed the boot, they found the nail had passed between his toes. There was no wound. No tissue damage. The pain was real, but it was generated entirely by the brain's expectation of injury.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("The Takeaway")
                        .font(.title2.bold())
                    Text("Pain is a protective response, not a damage report. Your brain creates pain based on perceived threat, not just what's happening in your body. Understanding this is the first step in learning to retrain your pain response.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task { await onDone() }
                } label: {
                    Label("Done", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            }
            .padding(40)
            .frame(maxWidth: 600, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Congratulations View

struct CongratulationsView: View {
    let onDone: () async -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "trophy.fill")
                .font(.system(size: 72))
                .foregroundStyle(.yellow)

            Text("You Did It!")
                .font(.largeTitle.bold())

            Text("You picked up all 5 objects and placed them in the box. Movement is safe, and your body is capable of more than you think.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)

            Button {
                Task { await onDone() }
            } label: {
                Label("Done", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
