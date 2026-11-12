import AppKit
import QuartzCore

final class MetalView: NSView {
    /// Pixels per point of the drawable (1 by default; the backing scale for Retina rendering).
    var renderScale: CGFloat = 1
    override func makeBackingLayer() -> CALayer { CAMetalLayer() }
    override var isFlipped: Bool { false }
    var metalLayer: CAMetalLayer { layer as! CAMetalLayer }
    // AppKit resets the layer's scale when the window's backing changes – keep ours.
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if metalLayer.contentsScale != renderScale { metalLayer.contentsScale = renderScale }
    }
}

/// Transparent full-screen window; all clicks pass through it.
@MainActor
final class Overlay: NSObject {
    let screenID: CGDirectDisplayID
    let window: NSWindow
    let view: MetalView
    let sim: Simulation
    private let renderer: Renderer
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var particles: [Particle] = []
    private var mesh: [Vertex] = []
    private var buffers = FrameBuffers()
    private var renderScale: CGFloat = 0
    /// Drawable size for the current render scale (kept while the GPU memory is released).
    private var drawableSize: CGSize = .zero
    /// Drawables and vertex buffers were given back while nothing can be shown.
    private var released = false
    /// The effects are hidden: window ordered out, no frames.
    private(set) var hidden = false
    /// Screen asleep or locked: no frames, but the window stays.
    var suspended = false {
        didSet {
            guard suspended != oldValue else { return }
            if suspended {
                sim.workshop.finishRolling()
                for panel in workshopPanels.values { panel.update(nil) }
                sleep()
                releaseGPUMemory()
            } else if !hidden {
                restoreGPUMemory()
                wake()                  // redraw the kept state (paused drifts would otherwise stay blank)
            }
        }
    }
    /// The user's frame rate – the maximum. Ambient snowfall runs at `ambientFPS` (see `tick`).
    var fps = 60 { didSet { if fps != oldValue { applyRate() } } }
    /// Draw calm snowfall at the lower ambient rate (an option – off by default, the snow then always
    /// falls at `fps`).
    var calmAtLowerRate = false
    /// Rate for plain snowfall, faded full-screen snow and twinkling lights. Divides 60 and 120 Hz evenly.
    static let ambientFPS = 30
    /// How long the simulation must report "nothing fast" before the rate drops (a splash must not flip it twice).
    private static let lowerAfter: CFTimeInterval = 0.75
    /// Running at `fps` (true) or at `min(fps, ambientFPS)`.
    private var fullRate = true
    /// When the simulation started to report that nothing fast is on screen (0 = it currently does).
    private var calmSince: CFTimeInterval = 0
    private var workshopPanels: [UUID: SnowmanPanel] = [:]
    private var optionHeld: Double = 0
    private var captureHidden = false

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// Whether this overlay still fits `screen` (same display, same frame) and can be kept.
    func matches(_ screen: NSScreen) -> Bool {
        screenID == Self.displayID(of: screen) && sim.origin == screen.frame.origin && sim.size == screen.frame.size
    }

    init(screen: NSScreen, renderer: Renderer, hostsSnowman: Bool) {
        screenID = Self.displayID(of: screen)
        self.renderer = renderer
        sim = Simulation(screenFrame: screen.frame, visibleFrame: screen.visibleFrame, hostsSnowman: hostsSnowman,
                         safeTop: screen.safeAreaInsets.top)
        window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        view = MetalView(frame: CGRect(origin: .zero, size: screen.frame.size))
        super.init()

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.animationBehavior = .none
        view.wantsLayer = true
        view.layerContentsRedrawPolicy = .never
        window.contentView = view
        window.setFrame(screen.frame, display: false)
        renderer.configure(view.metalLayer)
        setRenderScale(1)
        window.orderFrontRegardless()

        let dl = view.displayLink(target: self, selector: #selector(tick(_:)))
        dl.add(to: .main, forMode: .common)
        link = dl
        applyRate()
    }

    private func applyRate() {
        if fullRate || fps <= Self.ambientFPS {
            let maxRate = Float(fps)
            link?.preferredFrameRateRange = CAFrameRateRange(minimum: min(24, maxRate), maximum: maxRate, preferred: maxRate)
        } else {
            let r = Float(Self.ambientFPS)
            link?.preferredFrameRateRange = CAFrameRateRange(minimum: r, maximum: r, preferred: r)
        }
    }

    /// Full rate while something fast is on screen; the ambient rate once it has been calm for a moment.
    /// Raises at once, lowers only after `lowerAfter`.
    private func updateRate(now: CFTimeInterval) {
        // Over a full-screen app only faded snow is drawn – never worth more than the ambient rate.
        let fast = (sim.wantsFullFrameRate || !calmAtLowerRate) && !sim.isFullscreenPaused
        if fast {
            calmSince = 0
        } else if calmSince == 0 {
            calmSince = now
        }
        let full = fast || now - calmSince < Self.lowerAfter
        guard full != fullRate else { return }
        fullRate = full
        if fps > Self.ambientFPS { applyRate() }
    }

    /// Drawable resolution: 1 pixel per point (cheap) or the screen's backing scale (Retina).
    func setRenderScale(_ scale: CGFloat) {
        guard scale > 0, scale != renderScale else { return }
        renderScale = scale
        view.renderScale = scale
        view.metalLayer.contentsScale = scale
        drawableSize = CGSize(width: (sim.size.width * scale).rounded(), height: (sim.size.height * scale).rounded())
        if !released { view.metalLayer.drawableSize = drawableSize }
        wake()
    }

    /// Nothing can be shown (hidden, display asleep, locked): give back the drawables and vertex buffers.
    /// Not for a merely sleeping link – paused snow with visible drifts needs its last frame.
    private func releaseGPUMemory() {
        guard !released else { return }
        released = true
        particles = []
        mesh = []
        view.metalLayer.drawableSize = CGSize(width: 1, height: 1)
        // Shrinking the size alone keeps the full-size drawables alive: replace them by empty 1×1 frames
        // (the layer holds on to the previous one until a second frame follows).
        for _ in 0..<2 {
            renderer.draw(layer: view.metalLayer, size: view.bounds.size, particles: [], mesh: [], buffers: &buffers)
        }
        buffers = FrameBuffers()
    }

    private func restoreGPUMemory() {
        guard released else { return }
        released = false
        view.metalLayer.drawableSize = drawableSize
    }

    /// Keep the snow out of screenshots and screen sharing.
    func setHiddenFromCapture(_ on: Bool) {
        let t: NSWindow.SharingType = on ? .none : .readOnly
        if window.sharingType != t { window.sharingType = t }
        captureHidden = on
        for panel in workshopPanels.values { panel.setHiddenFromCapture(on) }
    }

    /// Hide all effects (the simulation keeps its state) or bring them back.
    func setHidden(_ on: Bool) {
        guard on != hidden else { return }
        hidden = on
        if on {
            sim.workshop.finishRolling()
            for panel in workshopPanels.values { panel.update(nil) }
            sleep()
            releaseGPUMemory()          // while still ordered in, so the empty frame is taken
            window.orderOut(nil)
        } else {
            if !suspended { restoreGPUMemory() }
            window.orderFrontRegardless()
            wake()                      // draw at least one frame with the kept state
        }
    }

    func wake() {
        guard !hidden, !suspended, let link, link.isPaused else { return }
        last = 0
        link.isPaused = false
    }

    func sleep() { link?.isPaused = true }

    func close() {
        for panel in workshopPanels.values { panel.close() }
        workshopPanels.removeAll()
        link?.invalidate()
        link = nil
        window.orderOut(nil)
        window.close()
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = last == 0 ? 1.0 / 60 : min(1.0 / 20, now - last)
        last = now
        let m = NSEvent.mouseLocation
        let local = CGPoint(x: m.x - sim.origin.x, y: m.y - sim.origin.y)
        let inside = local.x >= 0 && local.y >= 0 && local.x <= sim.size.width && local.y <= sim.size.height
        let mods = NSEvent.modifierFlags
        let option = mods.contains(.option) && !mods.contains(.command) && !mods.contains(.control)
        optionHeld = option ? optionHeld + dt : 0
        let shovel = option && (mods.contains(.shift) || !sim.optionRollsSnow)
        let craft = optionHeld > 0.25 && !shovel
        sim.step(dt: dt, now: CACurrentMediaTime(), mouse: inside ? local : nil, shovel: shovel, craft: craft)
        refreshWorkshopPanels()
        updateRate(now: now)
        particles.removeAll(keepingCapacity: true)
        mesh.removeAll(keepingCapacity: true)
        sim.buildParticles(into: &particles)
        sim.buildMesh(into: &mesh)
        // The tint the simulation was synced with (`buildMesh` publishes it) – no settings read per frame.
        let t = Mesh.tint
        renderer.tint = SIMD3(t.0, t.1, t.2)
        renderer.draw(layer: view.metalLayer, size: view.bounds.size, particles: particles, mesh: mesh, buffers: &buffers)
        if (!sim.isAnimating && !option) || hidden || suspended { link.isPaused = true }
    }

    /// One tiny click target per creation. The full-screen snowfall remains click-through.
    func refreshWorkshopPanels() {
        let targets = hidden || suspended ? [] : sim.workshopTargets
        let ids = Set(targets.map(\.id))
        for id in Array(workshopPanels.keys) where !ids.contains(id) {
            workshopPanels.removeValue(forKey: id)?.close()
        }
        for target in targets {
            let panel: SnowmanPanel
            if let existing = workshopPanels[target.id] { panel = existing } else {
                panel = SnowmanPanel()
                let id = target.id
                panel.onClick = { [weak self] p in
                    guard let self else { return }
                    sim.clickCraft(id, at: localPoint(p)); wake()
                }
                panel.onDrag = { [weak self] p in
                    guard let self else { return }
                    let p = localPoint(p)
                    sim.workshop.drag(id, to: SIMD2(Float(p.x), Float(p.y))); wake()
                }
                panel.onDrop = { [weak self] _ in self?.sim.workshop.drop(id); self?.wake() }
                panel.setHiddenFromCapture(captureHidden)
                workshopPanels[id] = panel
            }
            panel.update(target.rect.offsetBy(dx: sim.origin.x, dy: sim.origin.y))
        }
    }

    private func localPoint(_ global: CGPoint) -> CGPoint {
        CGPoint(x: min(max(global.x - sim.origin.x, 4), sim.size.width - 4),
                y: min(max(global.y - sim.origin.y, 4), sim.size.height - 4))
    }
}

/// Small panel right above a snowman – the only place that catches clicks.
/// A click knocks the snowman; dragging carries it somewhere else.
@MainActor
final class SnowmanPanel {
    private let panel: NSPanel
    private let view = ClickView()
    var onClick: ((CGPoint) -> Void)?
    var onDrag: ((CGPoint) -> Void)?
    var onDrop: ((CGPoint) -> Void)?

    /// The user is carrying the snowman right now.
    var isDragging: Bool { view.dragging }

    /// Whether the panel is on screen and contains the global point `p` (plus a margin).
    func contains(_ p: CGPoint, margin: CGFloat = 0) -> Bool {
        panel.isVisible && panel.frame.insetBy(dx: -margin, dy: -margin).contains(p)
    }

    /// Keep the click panel out of screenshots and screen sharing.
    func setHiddenFromCapture(_ on: Bool) {
        let t: NSWindow.SharingType = on ? .none : .readOnly
        if panel.sharingType != t { panel.sharingType = t }
    }

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = NSColor(white: 1, alpha: 0.002)   // almost transparent, but still clickable
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        view.onClick = { [weak self] p in self?.onClick?(p) }
        view.onDrag = { [weak self] p in self?.onDrag?(p) }
        view.onDrop = { [weak self] p in self?.onDrop?(p) }
        panel.contentView = view
    }

    /// `rect` in global coordinates, nil = hide.
    func update(_ rect: CGRect?) {
        guard let rect else {
            view.cancelInteraction()
            if panel.isVisible { panel.orderOut(nil) }
            return
        }
        if view.dragging { return }            // keep the panel still while dragging
        if abs(panel.frame.minX - rect.minX) > 1 || abs(panel.frame.minY - rect.minY) > 1
            || abs(panel.frame.width - rect.width) > 1 || abs(panel.frame.height - rect.height) > 1 {
            panel.setFrame(rect, display: false)
        }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func close() { view.cancelInteraction(); panel.orderOut(nil) }

    final class ClickView: NSView {
        var onClick: ((CGPoint) -> Void)?
        var onDrag: ((CGPoint) -> Void)?
        var onDrop: ((CGPoint) -> Void)?
        private(set) var dragging = false
        private var start: CGPoint = .zero
        private var holding = false

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            start = NSEvent.mouseLocation
            dragging = false
            holding = true
            NSCursor.closedHand.push()
        }

        override func mouseDragged(with event: NSEvent) {
            let p = NSEvent.mouseLocation
            if !dragging && hypot(p.x - start.x, p.y - start.y) > 4 { dragging = true }
            if dragging { onDrag?(p) }
        }

        override func mouseUp(with event: NSEvent) {
            guard holding else { return }
            holding = false
            NSCursor.pop()
            let p = NSEvent.mouseLocation
            if dragging {
                dragging = false
                onDrop?(p)
            } else {
                onClick?(p)
            }
        }

        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

        func cancelInteraction() {
            guard holding else { return }
            holding = false
            NSCursor.pop()
            if dragging { dragging = false; onDrop?(NSEvent.mouseLocation) }
        }
    }
}
