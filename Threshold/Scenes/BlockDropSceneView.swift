//
//  BlockDropSceneView.swift
//  Threshold
//
//  Immersive scene: A simple baseline/tutorial scenario. A cube floats at
//  eye level in front of the user, then drops straight down under gravity
//  when triggered. No body tracking – purely static world-space placement.
//

import SwiftUI
import RealityKit

struct BlockDropSceneView: View {

    @Environment(AppModel.self) var appModel
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace

    // MARK: - State

    @State private var rootEntity = Entity()
    @State private var cubeEntity: ModelEntity?
    @State private var floorEntity: ModelEntity?
    @State private var hasDropped = false

    // MARK: - Constants

    /// Cube edge length (metres) – matches the other scenes.
    private let cubeSize: Float = 0.10
    /// Distance in front of the user (metres).
    private let forwardDistance: Float = 1.8
    /// Starting height – roughly eye level in mixed immersion (metres).
    private let startHeight: Float = 1.5

    // MARK: - Body

    var body: some View {
        RealityView { content, attachments in
            content.add(rootEntity)

            // Invisible floor collider so the cube comes to rest
            let floor = makeFloorCollider()
            rootEntity.addChild(floor)
            floorEntity = floor

            // Floating cube
            let cube = makeCube()
            rootEntity.addChild(cube)
            cubeEntity = cube

            // Control panel attachment
            if let panel = attachments.entity(for: "controls") {
                panel.position = [0, 1.5, -1.2]
                content.add(panel)
            }
        } attachments: {
            Attachment(id: "controls") {
                SceneControlPanel(
                    sceneName: "Block Drop",
                    instruction: instructionText,
                    isReady: !hasDropped,
                    hasDropped: hasDropped,
                    onDrop: dropCube,
                    onReset: resetScene,
                    onReturn: { await dismissImmersiveSpace() }
                )
            }
        }
    }

    private var instructionText: String {
        if hasDropped { return "The block has landed." }
        return "A block is floating ahead of you. Tap Drop to release it."
    }

    // MARK: - Entity Builders

    private func makeCube() -> ModelEntity {
        let mesh = MeshResource.generateBox(size: cubeSize, cornerRadius: 0.005)
        let material = SimpleMaterial(color: .gray, roughness: 0.3, isMetallic: true)
        let cube = ModelEntity(mesh: mesh, materials: [material])

        // Position: eye level, in front of the user (negative Z is forward)
        cube.position = SIMD3<Float>(0, startHeight, -forwardDistance)

        // Physics body starts kinematic so it floats in place until triggered
        let shape = ShapeResource.generateBox(size: SIMD3<Float>(repeating: cubeSize))
        cube.components.set(CollisionComponent(shapes: [shape]))
        cube.components.set(
            PhysicsBodyComponent(
                shapes: [shape],
                mass: 2.0,
                mode: .kinematic
            )
        )

        return cube
    }

    /// An invisible static plane at floor level to catch the cube.
    private func makeFloorCollider() -> ModelEntity {
        let floor = ModelEntity()
        floor.position = .zero
        let shape = ShapeResource.generateBox(
            width: 6, height: 0.02, depth: 6
        )
        floor.components.set(CollisionComponent(shapes: [shape]))
        floor.components.set(
            PhysicsBodyComponent(shapes: [shape], mass: 0, mode: .static)
        )
        return floor
    }

    // MARK: - Actions

    private func dropCube() {
        guard let cube = cubeEntity else { return }
        hasDropped = true

        // Switch from kinematic to dynamic so RealityKit gravity takes over
        let shape = ShapeResource.generateBox(size: SIMD3<Float>(repeating: cubeSize))
        cube.components.set(
            PhysicsBodyComponent(
                shapes: [shape],
                mass: 2.0,
                mode: .dynamic
            )
        )
    }

    private func resetScene() {
        guard let cube = cubeEntity else { return }
        hasDropped = false

        // Snap back to kinematic at the original position
        let shape = ShapeResource.generateBox(size: SIMD3<Float>(repeating: cubeSize))
        cube.components.set(
            PhysicsBodyComponent(
                shapes: [shape],
                mass: 2.0,
                mode: .kinematic
            )
        )
        cube.position = SIMD3<Float>(0, startHeight, -forwardDistance)

        // Clear any residual velocity
        cube.components.set(PhysicsMotionComponent())
    }
}
