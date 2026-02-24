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

        // Block Drop (intro/tutorial) immersive space
        ImmersiveSpace(id: AppModel.SceneType.blockDrop.rawValue) {
            BlockDropSceneView()
                .environment(appModel)
                .onAppear { appModel.immersiveSpaceState = .open }
                .onDisappear {
                    appModel.immersiveSpaceState = .closed
                    appModel.activeScene = nil
                }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)

        // Smoke (environmental) immersive space
        ImmersiveSpace(id: AppModel.SceneType.smoke.rawValue) {
            SmokeSceneView()
                .environment(appModel)
                .onAppear { appModel.immersiveSpaceState = .open }
                .onDisappear {
                    appModel.immersiveSpaceState = .closed
                    appModel.activeScene = nil
                }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)

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
    }
}
