//
//  ProtectometerLabSceneView.swift
//  Threshold
//
//  Fully immersive scene: the "Protectometer Lab".
//
//  Layout
//  ──────
//  • Office 360° skybox rendered on the inside of a large sphere.
//    NOTE: UnlitMaterial is used specifically here so the equirectangular
//    panorama renders without lighting interference. This is the only
//    legitimate use-case exception to the SimpleMaterial-only convention.
//  • Office HDR used as an Image-Based Light (IBL) source so all 3D
//    objects realistically reflect the office environment.
//  • Central holographic Protectometer Gauge: a 24-segment gradient
//    semicircle (green → red) with a rotating needle driven by gaugeValue.
//  • Left tray: 3 DIM icons (red) — Chronic, Scary Report, Stress.
//  • Right tray: 3 SIM icons (green) — Tissues Heal, Laughter, Supportive Friend.
//  • Pinch-drag any icon toward the gauge to shift the needle.
//  • SIM impact → needle moves toward green + expanding safety-glow burst.
//  • DIM impact → needle moves toward red + needle shake danger-pulse.
//  • Floating info panel explains the core pain neuroscience concept.
//

import SwiftUI
import RealityKit
import RealityKitContent

// MARK: - Draggable marker component

/// Lightweight marker set on each DIM/SIM icon so the drag gesture
/// can distinguish icons from other entities in the scene.
struct DraggableTag: Component {
    init() {}
}

// MARK: - Scene view

struct ProtectometerLabSceneView: View {

    @Environment(AppModel.self) var appModel
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace

    // MARK: State

    @State private var rootEntity   = Entity()
    @State private var gaugeGroup:  Entity?
    @State private var needlePivot: Entity?
    @State private var gaugeValue:  Float = 0.5   // 0 = full green, 1 = full red

    // MARK: Layout constants

    private let gaugePosition  = SIMD3<Float>(0,     1.55, -1.65)
    private let gaugeRadius:     Float = 0.44
    private let dimTrayCenter  = SIMD3<Float>(-0.90, 1.40, -1.45)
    private let simTrayCenter  = SIMD3<Float>( 0.90, 1.40, -1.45)

    // MARK: Body

    var body: some View {
        RealityView { (content: inout RealityViewContent, attachments: RealityViewAttachments) in
            content.add(rootEntity)

            if let info = attachments.entity(for: "info") {
                info.position = SIMD3<Float>(0, 0.88, -1.65)
                content.add(info)
            }
            if let nav = attachments.entity(for: "nav") {
                nav.position = SIMD3<Float>(0, 2.10, -1.65)
                content.add(nav)
            }
        } attachments: {
            Attachment(id: "info") {
                ProtectometerInfoPanel()
            }
            Attachment(id: "nav") {
                Button {
                    Task { await dismissImmersiveSpace() }
                } label: {
                    Label("Library", systemImage: "square.grid.2x2")
                }
                .buttonStyle(.bordered)
                .padding(16)
                .glassBackgroundEffect()
            }
        }
        // Pinch-drag icons toward the gauge
        .gesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .onChanged { value in
                    guard value.entity.components[DraggableTag.self] != nil else { return }
                    if let parent = value.entity.parent {
                        value.entity.position = value.convert(
                            value.location3D, from: .local, to: parent)
                    }
                }
                .onEnded { value in
                    guard value.entity.components[DraggableTag.self] != nil else { return }
                    checkIconDroppedOnGauge(entity: value.entity)
                }
        )
        .task {
            await buildScene()
        }
    }

    // MARK: - Scene construction

    private func buildScene() async {
        addSkybox()
        await applyIBL()
        buildGaugeGroup()
        spawnIcons()
    }

    // MARK: Skybox

    /// Renders the office 360° JPEG on the inside of a 500 m sphere.
    /// UnlitMaterial is used intentionally so the panorama is not affected
    /// by scene lighting. All other scene geometry uses SimpleMaterial.
    private func addSkybox() {
        guard
            let uiImage = UIImage(named: "office"),
            let cgImage  = uiImage.cgImage,
            let texture  = try? TextureResource.generate(
                from: cgImage,
                options: TextureResource.CreateOptions(semantic: .color))
        else { return }

        var mat = UnlitMaterial()
        mat.color = .init(texture: .init(texture))

        let sky = ModelEntity(
            mesh: MeshResource.generateSphere(radius: 500),
            materials: [mat])
        sky.scale = SIMD3<Float>(-1, 1, 1)   // invert normals → renders from inside
        sky.name  = "skybox"
        rootEntity.addChild(sky)
    }

    // MARK: IBL

    private func applyIBL() async {
        guard let env = try? await EnvironmentResource(
            named: "office", in: realityKitContentBundle)
        else { return }

        let ibl = ImageBasedLightComponent(
            source: .single(env), intensityExponent: 8.0)
        rootEntity.components.set(ibl)
    }

    // MARK: Gauge

    private func buildGaugeGroup() {
        let group = Entity()
        group.name = "gaugeRoot"

        // ── Glass backing plate ──────────────────────────────────────────
        // Thin cylinder standing upright; semi-transparent metallic = glass-morphism
        let plateMesh = MeshResource.generateCylinder(
            height: 0.012, radius: gaugeRadius + 0.06)
        let plateMat  = SimpleMaterial(
            color: UIColor(white: 0.88, alpha: 0.12),
            roughness: 0.0, isMetallic: true)
        let plate = ModelEntity(mesh: plateMesh, materials: [plateMat])
        plate.components.set(ImageBasedLightReceiverComponent(imageBasedLight: rootEntity))
        plate.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        plate.position    = [0, 0, -0.018]
        group.addChild(plate)

        // ── Arc segments (green → yellow → orange → red) ─────────────────
        let segCount = 24
        for i in 0..<segCount {
            let t     = Float(i) / Float(segCount - 1)
            let angle = Float.pi * (1.0 - t)   // π (green/left) → 0 (red/right)
            let x     = gaugeRadius * cos(angle)
            let y     = gaugeRadius * sin(angle)

            let mesh = MeshResource.generateBox(
                width: 0.054, height: 0.022, depth: 0.030, cornerRadius: 0.004)
            let mat  = SimpleMaterial(
                color: UIColor(segmentColor(at: t)),
                roughness: 0.15, isMetallic: true)
            let seg  = ModelEntity(mesh: mesh, materials: [mat])
            seg.components.set(ImageBasedLightReceiverComponent(imageBasedLight: rootEntity))
            seg.position    = SIMD3<Float>(x, y, 0)
            seg.orientation = simd_quatf(angle: angle, axis: [0, 0, 1])
            group.addChild(seg)
        }

        // ── End-cap labels (GREEN / RED) ──────────────────────────────────
        addEndLabel("SAFE",   position: SIMD3<Float>(-gaugeRadius - 0.08, -0.04, 0), color: .systemGreen, to: group)
        addEndLabel("DANGER", position: SIMD3<Float>( gaugeRadius + 0.02, -0.04, 0), color: .systemRed,   to: group)

        // ── Center hub ────────────────────────────────────────────────────
        let hub = ModelEntity(
            mesh: MeshResource.generateSphere(radius: 0.022),
            materials: [SimpleMaterial(color: UIColor(white: 0.95, alpha: 1), roughness: 0.05, isMetallic: true)])
        hub.components.set(ImageBasedLightReceiverComponent(imageBasedLight: rootEntity))
        hub.position = [0, 0, 0.016]
        group.addChild(hub)

        // ── Needle (pivots at base = center of arc) ───────────────────────
        let pivot  = Entity()
        pivot.position = [0, 0, 0.022]

        let needle = ModelEntity(
            mesh: MeshResource.generateBox(
                width: 0.007, height: 0.34, depth: 0.007, cornerRadius: 0.002),
            materials: [SimpleMaterial(color: UIColor(white: 0.95, alpha: 1), roughness: 0.05, isMetallic: true)])
        needle.components.set(ImageBasedLightReceiverComponent(imageBasedLight: rootEntity))
        needle.position = [0, 0.17, 0]   // offset so rotation origin is at needle base
        pivot.addChild(needle)
        group.addChild(pivot)
        needlePivot = pivot

        // Collision sphere for drop-zone detection (driven by code, not gesture)
        group.components.set(
            CollisionComponent(shapes: [.generateSphere(radius: 0.60)]))

        group.position = gaugePosition
        rootEntity.addChild(group)
        gaugeGroup = group

        applyNeedleRotation(animated: false)
    }

    /// 3-letter end-cap label rendered as 3-D extruded text.
    private func addEndLabel(_ text: String, position: SIMD3<Float>, color: UIColor, to parent: Entity) {
        let mesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.003,
            font: MeshResource.Font.boldSystemFont(ofSize: 0.028),
            containerFrame: CGRect(x: 0, y: 0, width: 0.14, height: 0.04),
            alignment: .left,
            lineBreakMode: .byTruncatingTail)
        let label = ModelEntity(mesh: mesh,
                                materials: [SimpleMaterial(color: color, roughness: 0.6, isMetallic: false)])
        label.position = position
        parent.addChild(label)
    }

    // MARK: Needle rotation

    /// Rotates the needle pivot so the needle points at the current gaugeValue
    /// position on the arc.
    ///   gaugeValue 0.0 → full left  (green)  → −90° from vertical
    ///   gaugeValue 0.5 → straight up (centre) →   0°
    ///   gaugeValue 1.0 → full right (red)     → +90° from vertical
    private func applyNeedleRotation(animated: Bool) {
        let targetAngle = (gaugeValue - 0.5) * Float.pi
        let targetQuat  = simd_quatf(angle: -targetAngle, axis: [0, 0, 1])

        if animated, let pivot = needlePivot {
            var t = pivot.transform
            t.rotation = targetQuat
            pivot.move(to: t, relativeTo: pivot.parent, duration: 0.45, timingFunction: .easeInOut)
        } else {
            needlePivot?.orientation = targetQuat
        }
    }

    // MARK: Gradient helper

    private func segmentColor(at t: Float) -> Color {
        switch t {
        case ..<0.33:
            let s = t / 0.33
            return Color(red: Double(s * 0.85), green: 0.78, blue: 0.0)
        case 0.33..<0.66:
            let s = (t - 0.33) / 0.33
            return Color(red: 0.95, green: Double(0.78 - s * 0.38), blue: 0.0)
        default:
            let s = (t - 0.66) / 0.34
            return Color(red: 1.0, green: Double(0.40 - s * 0.36), blue: 0.0)
        }
    }

    // MARK: - Icon spawning

    private func spawnIcons() {
        let dims: [(String, String)] = [
            ("DIM:Chronic", "Chronic"),
            ("DIM:Report",  "Scary Report"),
            ("DIM:Stress",  "Stress")
        ]
        let sims: [(String, String)] = [
            ("SIM:Tissues",   "Tissues Heal"),
            ("SIM:Laughter",  "Laughter"),
            ("SIM:Friend",    "Supportive Friend")
        ]

        for (i, (name, label)) in dims.enumerated() {
            let icon   = makeIcon(name: name, label: label, isDIM: true)
            let offset = SIMD3<Float>(Float(i - 1) * 0.24, 0, 0)
            icon.setPosition(dimTrayCenter + offset, relativeTo: rootEntity)
            rootEntity.addChild(icon)
        }
        for (i, (name, label)) in sims.enumerated() {
            let icon   = makeIcon(name: name, label: label, isDIM: false)
            let offset = SIMD3<Float>(Float(i - 1) * 0.24, 0, 0)
            icon.setPosition(simTrayCenter + offset, relativeTo: rootEntity)
            rootEntity.addChild(icon)
        }
    }

    private func makeIcon(name: String, label: String, isDIM: Bool) -> Entity {
        let parent = Entity()
        parent.name = name
        parent.components.set(DraggableTag())

        let radius:    Float   = 0.062
        let baseColor: UIColor = isDIM
            ? UIColor(red: 0.85, green: 0.12, blue: 0.12, alpha: 1.0)
            : UIColor(red: 0.10, green: 0.82, blue: 0.36, alpha: 1.0)
        let glowColor: UIColor = isDIM
            ? UIColor(red: 1.0,  green: 0.08, blue: 0.08, alpha: 0.22)
            : UIColor(red: 0.06, green: 1.0,  blue: 0.30, alpha: 0.22)

        // Core sphere
        let core = ModelEntity(
            mesh: MeshResource.generateSphere(radius: radius),
            materials: [SimpleMaterial(color: baseColor, roughness: 0.22, isMetallic: true)])
        core.components.set(ImageBasedLightReceiverComponent(imageBasedLight: rootEntity))
        parent.addChild(core)

        // Outer glow halo
        let glow = ModelEntity(
            mesh: MeshResource.generateSphere(radius: radius * 1.65),
            materials: [SimpleMaterial(color: glowColor, roughness: 1.0, isMetallic: false)])
        parent.addChild(glow)

        // 3-D label (name) above the sphere
        let labelMesh = MeshResource.generateText(
            label,
            extrusionDepth: 0.004,
            font: MeshResource.Font.systemFont(ofSize: 0.030),
            containerFrame: CGRect(x: -0.13, y: 0, width: 0.26, height: 0.06),
            alignment: .center,
            lineBreakMode: .byWordWrapping)
        let labelEnt = ModelEntity(
            mesh: labelMesh,
            materials: [SimpleMaterial(
                color: isDIM ? UIColor(red: 1, green: 0.35, blue: 0.35, alpha: 1)
                             : UIColor(red: 0.25, green: 1, blue: 0.55, alpha: 1),
                roughness: 0.5, isMetallic: false)])
        labelEnt.position = SIMD3<Float>(-0.13, radius + 0.025, 0)
        parent.addChild(labelEnt)

        // "DIM" / "SIM" tag below the sphere
        let tagText = isDIM ? "DIM" : "SIM"
        let tagMesh = MeshResource.generateText(
            tagText,
            extrusionDepth: 0.003,
            font: MeshResource.Font.boldSystemFont(ofSize: 0.022),
            containerFrame: CGRect(x: -0.04, y: 0, width: 0.08, height: 0.03),
            alignment: .center)
        let tagEnt = ModelEntity(
            mesh: tagMesh,
            materials: [SimpleMaterial(
                color: isDIM ? UIColor(red: 1, green: 0.3, blue: 0.3, alpha: 1)
                             : UIColor(red: 0.3, green: 1, blue: 0.5, alpha: 1),
                roughness: 0.5, isMetallic: false)])
        tagEnt.position = SIMD3<Float>(-0.04, -(radius + 0.040), 0)
        parent.addChild(tagEnt)

        // Input / collision (required for drag gesture + hover)
        parent.components.set(
            CollisionComponent(shapes: [.generateSphere(radius: radius * 1.6)]))
        parent.components.set(
            InputTargetComponent(allowedInputTypes: .indirect))
        parent.components.set(HoverEffectComponent())

        return parent
    }

    // MARK: - Drop detection

    private func checkIconDroppedOnGauge(entity: Entity) {
        guard let gaugePos = gaugeGroup?.position(relativeTo: rootEntity) else { return }
        let iconPos = entity.position(relativeTo: rootEntity)
        let dist    = length(iconPos - gaugePos)
        guard dist < 0.68 else { return }   // within gauge collision sphere

        let isDIM: Bool = entity.name.hasPrefix("DIM:")

        // Shift gauge value
        let delta: Float = isDIM ? 0.22 : -0.22
        gaugeValue = max(0, min(1, gaugeValue + delta))
        applyNeedleRotation(animated: true)

        // Remove icon
        entity.removeFromParent()

        // Feedback
        let impactPos = gaugePos + SIMD3<Float>(0, 0.30, 0)
        if isDIM {
            Task { await triggerDangerPulse() }
        } else {
            triggerSafetyGlow(at: impactPos)
        }

        // Zone-level bonus feedback
        if gaugeValue <= 0.20 {
            triggerSafetyGlow(at: gaugePos + SIMD3<Float>(0, 0.0, 0))
        } else if gaugeValue >= 0.85 {
            Task { await triggerDangerPulse() }
        }
    }

    // MARK: - Feedback effects

    /// Expanding green sphere burst — "SIM Juice" explosion.
    private func triggerSafetyGlow(at position: SIMD3<Float>) {
        let glow = ModelEntity(
            mesh: MeshResource.generateSphere(radius: 0.10),
            materials: [SimpleMaterial(
                color: UIColor(red: 0.08, green: 1.0, blue: 0.42, alpha: 0.50),
                roughness: 1.0, isMetallic: false)])
        glow.position = position
        glow.scale    = .init(repeating: 0.01)
        rootEntity.addChild(glow)

        var expanded = glow.transform
        expanded.scale = .init(repeating: 2.6)
        glow.move(to: expanded, relativeTo: rootEntity, duration: 0.50, timingFunction: .easeOut)

        let localRoot = rootEntity
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            var faded       = glow.transform
            faded.scale     = .init(repeating: 0.01)
            glow.move(to: faded, relativeTo: localRoot, duration: 0.35, timingFunction: .easeIn)
            try? await Task.sleep(nanoseconds: 380_000_000)
            glow.removeFromParent()
        }
    }

    /// High-frequency needle shake — "Danger Pulse" for a DIM impact.
    private func triggerDangerPulse() async {
        guard let pivot = needlePivot else { return }
        let base: simd_quatf = pivot.orientation
        let shake: Float     = 0.07

        for _ in 0..<4 {
            var left        = pivot.transform
            left.rotation   = simd_quatf(angle:  shake, axis: [0, 0, 1]) * base
            pivot.move(to: left,  relativeTo: pivot.parent, duration: 0.04, timingFunction: .linear)
            try? await Task.sleep(nanoseconds: 45_000_000)

            var right       = pivot.transform
            right.rotation  = simd_quatf(angle: -shake, axis: [0, 0, 1]) * base
            pivot.move(to: right, relativeTo: pivot.parent, duration: 0.04, timingFunction: .linear)
            try? await Task.sleep(nanoseconds: 45_000_000)
        }

        var reset     = pivot.transform
        reset.rotation = base
        pivot.move(to: reset, relativeTo: pivot.parent, duration: 0.14, timingFunction: .easeOut)
    }
}

// MARK: - Info panel

private struct ProtectometerInfoPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("The Protectometer")
                .font(.title3.bold())

            Text("Pain is the brain's protector. It turns the volume up when it perceives danger (DIMs) and turns it down when it perceives safety (SIMs).")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 24) {
                Label("Danger In Me",  systemImage: "circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption.bold())
                Label("Safety In Me", systemImage: "circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption.bold())
            }

            Text("Drag the icons toward the gauge to shift the needle.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(width: 460)
        .glassBackgroundEffect()
    }
}
