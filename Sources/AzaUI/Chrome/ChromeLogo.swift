import RealityKit
import SwiftUI
#if os(iOS)
import CoreMotion
#endif

/// A logo as a polished chrome object you can spin. Drag it and it keeps turning, then settles;
/// it leans toward the pointer, and on iPhone with the phone.
///
/// `ChromeLogo()` shows the aza mark. For another logo, make its layout with
/// `bun web/cli.ts logo.svg --only layout` and pass the file's URL.
public struct ChromeLogo: View {
    private let layout: URL
    private let studio: ChromeStudio
    private let settings: ChromeSettings
    private let interactive: Bool
    @State private var scene = ChromeScene()

    public init(studio: ChromeStudio = .monochrome, settings: ChromeSettings = .init(), interactive: Bool = true) {
        self.init(layout: Bundle.module.url(forResource: "aza", withExtension: "chromelayout")!, studio: studio, settings: settings, interactive: interactive)
    }

    public init(layout: URL, studio: ChromeStudio = .monochrome, settings: ChromeSettings = .init(), interactive: Bool = true) {
        self.layout = layout
        self.studio = studio
        self.settings = settings
        self.interactive = interactive
    }

    public var body: some View {
        RealityView { content in
            content.camera = .virtual
            content.add(scene.root)
            scene.subscribe(content)
        } update: { _ in
            scene.apply(settings)
        }
        .task(id: layout) { await scene.load(layout) }
        .task(id: studio) { await scene.light(studio) }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { scene.size = $0 }
        .gesture(drag, isEnabled: interactive)
        .onContinuousHover { phase in
            guard interactive else { return }
            switch phase {
            case .active(let p):
                let w = max(scene.size.width, 1) / 2, h = max(scene.size.height, 1) / 2
                scene.motion.pointer(x: Float((p.x - w) / w), y: Float((p.y - h) / h), settings)
            case .ended:
                scene.motion.pointerLeft()
            }
        }
        #if os(iOS)
        .task(id: interactive) {
            guard interactive else { return }
            let manager = CMMotionManager()
            guard manager.isDeviceMotionAvailable else { return }
            manager.deviceMotionUpdateInterval = 1 / 60
            manager.startDeviceMotionUpdates(to: .main) { [scene, settings] data, _ in
                guard let a = data?.attitude else { return }
                scene.motion.gyro(pitch: Float(a.pitch) * 180 / .pi, roll: Float(a.roll) * 180 / .pi, settings)
            }
            while !Task.isCancelled { try? await Task.sleep(for: .seconds(60)) }
            manager.stopDeviceMotionUpdates()
        }
        #endif
        .accessibilityElement()
        .accessibilityAddTraits(.isImage)
        .accessibilityLabel("aza")
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !scene.motion.dragging {
                    scene.motion.start()
                    scene.lastDrag = .zero
                }
                let dx = value.translation.width - scene.lastDrag.width, dy = value.translation.height - scene.lastDrag.height
                scene.motion.drag(dx: Float(dx), dy: Float(dy), size: scene.side)
                scene.lastDrag = value.translation
            }
            .onEnded { value in
                scene.motion.end(velocity: SIMD2(Float(value.velocity.width), Float(value.velocity.height)), size: scene.side)
            }
    }
}

/// The RealityKit side: the mesh, the studio light, the camera, and the per-frame motion.
final class ChromeScene {
    let root = Entity()
    let motion = ChromeMotion()
    var lastDrag: CGSize = .zero
    var size: CGSize = .zero { didSet { frame() } }
    var side: Float { Float(max(min(size.width, size.height), 1)) }

    /// Holds the camera and the logo. RealityKit's image-based light ignores its entity's
    /// rotation, so turning the studio means turning everything else the other way.
    private let rig = Entity()
    private let model = ModelEntity()
    private let light = Entity()
    private let camera = PerspectiveCamera()
    private var material = PhysicallyBasedMaterial()
    private var mesh: ChromeMesh?
    private var settings = ChromeSettings()
    private var rest = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    private var subscription: EventSubscription?
    /// Radius of the sphere the camera keeps in view, in logo units.
    private let fit: Float = 0.6

    init() {
        root.addChild(rig)
        root.addChild(light)
        rig.addChild(model)
        rig.addChild(camera)
        material.baseColor = .init(tint: .init(white: 0.95, alpha: 1))
        material.metallic = .init(floatLiteral: 1)
        apply(settings, force: true)
    }

    func subscribe(_ content: some RealityViewContentProtocol) {
        subscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            self?.tick(Float(event.deltaTime))
        }
    }

    func light(_ studio: ChromeStudio) async {
        do {
            let image = try await Task.detached { try studio.image() }.value
            let environment = try await EnvironmentResource(equirectangular: image, withName: studio.rawValue)
            light.components.set(ImageBasedLightComponent(source: .single(environment), intensityExponent: exposure(settings)))
            model.components.set(ImageBasedLightReceiverComponent(imageBasedLight: light))
        } catch {
            print("ChromeLogo studio: \(error)")
        }
    }

    func load(_ url: URL) async {
        do {
            let layout = try await Task.detached { try ChromeLayout(contentsOf: url) }.value
            let mesh = try ChromeMesh(layout: layout, settings: settings)
            self.mesh = mesh
            model.model = ModelComponent(mesh: mesh.resource, materials: [material])
        } catch {
            print("ChromeLogo: \(error)")
        }
    }

    func apply(_ s: ChromeSettings, force: Bool = false) {
        guard force || s != settings else { return }
        if s.shape != settings.shape { mesh?.update(s) }
        settings = s
        material.roughness = .init(floatLiteral: s.roughness)
        if model.model != nil { model.model?.materials = [material] }
        if var ibl = light.components[ImageBasedLightComponent.self] {
            ibl.intensityExponent = exposure(s)
            light.components.set(ibl)
        }
        let rad = Float.pi / 180
        // The quarter turn: RealityKit centres an equirectangular image 90° from where three.js does.
        rig.orientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
            * simd_quatf(angle: -s.lightAngle * rad, axis: [0, 1, 0]) * simd_quatf(angle: -s.lightHeight * rad, axis: [1, 0, 0])
        rest = simd_quatf(angle: s.yaw * rad, axis: [0, 1, 0]) * simd_quatf(angle: s.pitch * rad, axis: [1, 0, 0])
        frame()
    }

    /// RealityKit's tone mapping is a little darker than three.js's; this brings them level.
    private func exposure(_ s: ChromeSettings) -> Float {
        log2(s.exposure) + 0.4
    }

    private func tick(_ dt: Float) {
        model.orientation = motion.step(dt, settings) * rest
    }

    private func frame() {
        // The field of view spans the view's shorter side, so the logo looks the same in any shape of view.
        let distance = fit / settings.scale / sin(settings.fov * .pi / 360)
        camera.camera.fieldOfViewInDegrees = settings.fov
        camera.camera.fieldOfViewOrientation = size.width < size.height ? .horizontal : .vertical
        camera.camera.near = distance / 10
        camera.camera.far = distance * 10
        camera.position = [0, 0, distance]
    }
}

#Preview {
    ChromeLogo()
        .padding()
        .background(.black)
}
