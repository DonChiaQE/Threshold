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

        // Nail in the Glove — pain neuroscience education
        ImmersiveSpace(id: AppModel.SceneType.nail.rawValue) {
            NailSceneView()
                .environment(appModel)
                .onAppear { appModel.immersiveSpaceState = .open }
                .onDisappear {
                    appModel.immersiveSpaceState = .closed
                    appModel.activeScene = nil
                    appModel.nailPhase = .inactive
                }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
        .upperLimbVisibility(.hidden)

        // Object Pickup — therapy rehabilitation
        ImmersiveSpace(id: AppModel.SceneType.objectPickup.rawValue) {
            ObjectPickupSceneView()
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
