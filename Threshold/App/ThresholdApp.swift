//
//  ThresholdApp.swift
//  Threshold
//
//  Created by Don Chia on 13/2/26.
//

import SwiftUI

@main
struct ThresholdApp: App {

    @State private var appModel = AppModel()

    var body: some Scene {

        // Main window – scene library
        WindowGroup {
            ContentView()
                .environment(appModel)
        }

        // Hammer (Arm) immersive space
        ImmersiveSpace(id: AppModel.SceneType.hammer.rawValue) {
            HammerSceneView()
                .environment(appModel)
                .onAppear { appModel.immersiveSpaceState = .open }
                .onDisappear {
                    appModel.immersiveSpaceState = .closed
                    appModel.activeScene = nil
                }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)

        // Dumbbell (Foot) immersive space
        ImmersiveSpace(id: AppModel.SceneType.dumbbell.rawValue) {
            DumbbellSceneView()
                .environment(appModel)
                .onAppear { appModel.immersiveSpaceState = .open }
                .onDisappear {
                    appModel.immersiveSpaceState = .closed
                    appModel.activeScene = nil
                }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)

        // Cactus – proximity threat/reappraisal sequence with glove
        ImmersiveSpace(id: AppModel.SceneType.cactus.rawValue) {
            CactusSceneView()
                .environment(appModel)
                .onAppear { appModel.immersiveSpaceState = .open }
                .onDisappear {
                    appModel.immersiveSpaceState = .closed
                    appModel.activeScene = nil
                }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
        .upperLimbVisibility(.hidden)

        // Sack — floor pickup with grip gesture for upper body exposure therapy
        ImmersiveSpace(id: AppModel.SceneType.sack.rawValue) {
            SackSceneView()
                .environment(appModel)
                .onAppear { appModel.immersiveSpaceState = .open }
                .onDisappear {
                    appModel.immersiveSpaceState = .closed
                    appModel.activeScene = nil
                }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
