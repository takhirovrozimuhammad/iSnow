import CoreGraphics
import Foundation

/// A snapshot of a real, visible snow surface. Ball physics never queries other apps.
struct CraftSurface {
    var key: Int
    var rect: CGRect
    var heights: [Float]
    var visible: [Bool]
    var binWidth: Float = 4

    func top(at x: Float) -> Float? {
        let i = Int((x - Float(rect.minX)) / binWidth)
        guard x >= Float(rect.minX), x <= Float(rect.maxX), heights.indices.contains(i),
              visible.indices.contains(i), visible[i] else { return nil }
        return Float(rect.maxY) + max(0, heights[i])
    }
}

/// Hand rolled snow is separate from the automatic characters: toggling the latter never deletes it.
@MainActor
final class SnowWorkshop {
    struct Ball {
        let id: UUID
        var x, y, radius: Float
        var vy: Float = 0
        var falling = true
        var parent: UUID?
        var hostKey: Int?
        var hostRect: CGRect?
        var ignoredSupport: Int?
        var justDropped = true
        var hidden = false
        var rect: CGRect {
            CGRect(x: CGFloat(x - radius - 3), y: CGFloat(y - radius - 3),
                   width: CGFloat(radius * 2 + 6), height: CGFloat(radius * 2 + 6))
        }
    }
    struct Figure {
        let id: UUID
        var snowman: Snowman
        var ignoredSupport: Int?
        var justDropped = true
    }
    struct Target { let id: UUID; let rect: CGRect }

    static let maxBalls = 18
    static let maxFigures = 6
    static let maxRadius: Float = 42
    private(set) var balls: [Ball] = []
    private(set) var figures: [Figure] = []
    private(set) var rolling: Ball?
    private(set) var dragged: UUID?
    private var lastRoll: SIMD2<Float>?
    private var dragOffset = SIMD2<Float>.zero
    private var rollArea: Float = 0
    private var hint: (x: Float, y: Float, radius: Float)?

    var isMoving: Bool {
        rolling != nil || dragged != nil || balls.contains { $0.falling }
            || figures.contains { $0.snowman.isMoving }
    }

    var hasCreations: Bool { !balls.isEmpty || !figures.isEmpty }

    /// Option + pointer movement removes actual drift area and packs it into a growing ball.
    /// No ball is created over empty air, and holding still does not manufacture snow.
    func roll(at point: SIMD2<Float>?, active: Bool,
              collect: (SIMD2<Float>, Float, Float) -> Float) {
        guard active, dragged == nil, let point, balls.count < Self.maxBalls else {
            finishRolling()
            return
        }
        defer { lastRoll = point }
        guard let previous = lastRoll else { return }
        let distance = hypot(point.x - previous.x, point.y - previous.y)
        if distance > 0.3 {
            let steps = min(24, max(1, Int(ceil(distance / 8))))
            let travel = min(distance, 160) / Float(steps)
            for i in 1...steps {
                let p = previous + (point - previous) * (Float(i) / Float(steps))
                let room = max(0, Float.pi * Self.maxRadius * Self.maxRadius - rollArea)
                guard room > 0 else { break }
                let got = collect(p, max(16, (rolling?.radius ?? 6) * 0.9), min(room, travel * 55))
                rollArea += max(0, min(room, got))
            }
        }
        if rollArea > 12 {
            let radius = min(Self.maxRadius, sqrt(rollArea / .pi))
            if rolling == nil { rolling = Ball(id: UUID(), x: point.x, y: point.y, radius: radius) }
            rolling?.radius = radius
        }
        if let r = rolling?.radius {
            rolling?.x = point.x + r * 0.35
            rolling?.y = point.y + r * 0.35
        }
    }

    func finishRolling() {
        if let ball = rolling, ball.radius >= 6, balls.count < Self.maxBalls {
            balls.append(ball)
            drop(ball.id)
        }
        rolling = nil
        rollArea = 0
        lastRoll = nil
    }

    /// Keep the cursor-to-object offset, so even a large ball never jumps when first grabbed.
    func drag(_ id: UUID, to p: SIMD2<Float>) {
        if let i = balls.firstIndex(where: { $0.id == id }) {
            if dragged != id {
                dragOffset = SIMD2(balls[i].x, balls[i].y) - p
                balls[i].parent = nil
                balls[i].ignoredSupport = nil
            }
            dragged = id
            balls[i].x = p.x + dragOffset.x
            balls[i].y = p.y + dragOffset.y
            balls[i].falling = false
            balls[i].vy = 0
            alignChildren()
            hint = snapCandidate(for: id).map { parent in
                (parent.x, parent.y + (parent.radius + balls[i].radius) * 0.82, balls[i].radius)
            }
        } else if let i = figures.firstIndex(where: { $0.id == id }) {
            if dragged != id {
                dragOffset = SIMD2(figures[i].snowman.anchorX, figures[i].snowman.baseY) - p
                figures[i].ignoredSupport = nil
            }
            dragged = id
            figures[i].snowman.anchorX = p.x + dragOffset.x
            figures[i].snowman.baseY = p.y + dragOffset.y
            figures[i].snowman.carried = true
            figures[i].snowman.falling = false
        }
    }

    func drop(_ id: UUID) {
        if let i = balls.firstIndex(where: { $0.id == id }) {
            balls[i].justDropped = true
            if let parent = snapCandidate(for: id) {
                balls[i].parent = parent.id
                balls[i].falling = false
                balls[i].hostKey = nil
                alignChildren()
                assemble(containing: id)
            } else {
                balls[i].falling = true
                balls[i].hostKey = nil
                balls[i].vy = 0
            }
        } else if let i = figures.firstIndex(where: { $0.id == id }) {
            figures[i].justDropped = true
            figures[i].snowman.carried = false
            figures[i].snowman.falling = true
            figures[i].snowman.vy = 0
        }
        dragged = nil
        hint = nil
    }

    private func descendants(of id: UUID) -> Set<UUID> {
        var result: Set<UUID> = [id]
        for _ in 0..<Self.maxBalls {
            let old = result.count
            for b in balls where b.parent.map({ result.contains($0) }) == true { result.insert(b.id) }
            if old == result.count { break }
        }
        return result
    }

    private func snapCandidate(for id: UUID) -> Ball? {
        guard let b = balls.first(where: { $0.id == id }) else { return nil }
        let family = descendants(of: id)
        return balls.filter { other in
            !family.contains(other.id) && !other.hidden && other.radius >= b.radius * 0.8
                && !balls.contains(where: { $0.parent == other.id && $0.id != id })
                && abs(other.x - b.x) < max(18, other.radius * 0.95)
                && b.y > other.y + other.radius * 0.4
                && abs(b.y - (other.y + (other.radius + b.radius) * 0.82)) < max(30, b.radius * 1.6)
        }.min { abs($0.x - b.x) + abs($0.y - b.y) < abs($1.x - b.x) + abs($1.y - b.y) }
    }

    private func alignChildren() {
        for _ in 0..<3 {
            for i in balls.indices {
                guard let parent = balls[i].parent,
                      let base = balls.first(where: { $0.id == parent }) else { continue }
                balls[i].x = base.x
                balls[i].y = base.y + (base.radius + balls[i].radius) * 0.82
                balls[i].falling = false
            }
        }
    }

    private func assemble(containing id: UUID) {
        guard figures.count < Self.maxFigures else { return }
        var root = id
        for _ in 0..<Self.maxBalls {
            guard let p = balls.first(where: { $0.id == root })?.parent else { break }
            root = p
        }
        var stack: [Ball] = []
        var next: UUID? = root
        while let id = next, let b = balls.first(where: { $0.id == id }), stack.count < 4 {
            stack.append(b)
            next = balls.first(where: { $0.parent == id })?.id
        }
        guard stack.count == 3 else { return }
        var snowman = Snowman()
        snowman.handmadeRadii = stack.map(\.radius)
        snowman.sizeScale = stack[0].radius / Snowman.radii.0
        snowman.anchorX = stack[0].x
        snowman.baseY = stack[0].y - stack[0].radius * 0.92
        snowman.hostKey = stack[0].hostKey ?? -1
        snowman.hostRect = stack[0].hostRect
        snowman.offsetX = snowman.anchorX - Float(snowman.hostRect?.minX ?? 0)
        snowman.phase = .dressing
        snowman.userPlaced = true
        snowman.falling = stack[0].falling
        snowman.life = .greatestFiniteMagnitude
        snowman.wave = 1.6
        let ids = Set(stack.map(\.id))
        balls.removeAll { ids.contains($0.id) }
        figures.append(Figure(id: root, snowman: snowman))
    }

    func step(dt: Float, surfaces: [CraftSurface], mouse: SIMD2<Float>?, temperature: Float,
              paused: Bool, debris: inout [Debris], shards: inout [Shard]) {
        for i in balls.indices where balls[i].id != dragged && balls[i].parent == nil {
            if !balls[i].falling {
                if let surface = surfaces.first(where: { $0.key == balls[i].hostKey }),
                   surface.rect == balls[i].hostRect, let top = surface.top(at: balls[i].x) {
                    balls[i].y = top + balls[i].radius
                } else {
                    balls[i].ignoredSupport = balls[i].hostKey
                    balls[i].falling = true; balls[i].vy = 0
                }
            }
            if balls[i].falling {
                // A freshly released ball may already overlap a drift (especially a big ball held
                // right at the bottom). Resolve that contact once instead of tunnelling through it.
                let old = balls[i].y + (balls[i].justDropped ? balls[i].radius : -balls[i].radius)
                balls[i].justDropped = false
                balls[i].vy -= 900 * dt
                balls[i].y += balls[i].vy * dt
                let bottom = balls[i].y - balls[i].radius
                if let support = landing(x: balls[i].x, old: old, new: bottom, surfaces: surfaces,
                                         ignoring: balls[i].ignoredSupport) {
                    balls[i].y = support.top + balls[i].radius
                    balls[i].vy = 0
                    balls[i].falling = false
                    balls[i].hostKey = support.surface.key
                    balls[i].hostRect = support.surface.rect
                    balls[i].ignoredSupport = nil
                }
            }
            if temperature > 0 && !paused { balls[i].radius = max(0, balls[i].radius - temperature * dt * 0.08) }
        }
        let removed = Set(balls.filter { $0.radius < 3 || $0.y < -150 }.map(\.id))
        balls.removeAll { removed.contains($0.id) }
        for i in balls.indices where balls[i].parent.map({ removed.contains($0) }) == true {
            balls[i].parent = nil; balls[i].falling = true
        }
        alignChildren()
        for i in figures.indices {
            var s = figures[i].snowman
            s.lookAt = mouse
            s.temperature = temperature
            if !s.carried {
                if !s.falling {
                    if let surface = surfaces.first(where: { $0.key == s.hostKey }), surface.rect == s.hostRect,
                       let top = surface.top(at: s.anchorX) { s.baseY = top }
                    else { figures[i].ignoredSupport = s.hostKey; s.falling = true; s.vy = 0 }
                }
                if s.falling {
                    let old = s.baseY + (figures[i].justDropped ? s.R(0) * 1.84 : 0)
                    figures[i].justDropped = false
                    s.vy -= 900 * dt; s.baseY += s.vy * dt
                    if let support = landing(x: s.anchorX, old: old, new: s.baseY, surfaces: surfaces,
                                             ignoring: figures[i].ignoredSupport) {
                        s.baseY = support.top; s.falling = false; s.vy = 0; s.wobble = 1
                        s.hostKey = support.surface.key; s.hostRect = support.surface.rect
                        figures[i].ignoredSupport = nil
                    }
                }
            }
            if !paused || s.phase == .dressing { _ = s.step(dt: dt, debris: &debris, shards: &shards) }
            figures[i].snowman = s
        }
        figures.removeAll { $0.snowman.phase == .absent || $0.snowman.baseY < -200 }
    }

    private func landing(x: Float, old: Float, new: Float, surfaces: [CraftSurface], ignoring: Int? = nil)
        -> (surface: CraftSurface, top: Float)? {
        surfaces.compactMap { s -> (surface: CraftSurface, top: Float)? in
            guard s.key != ignoring, let top = s.top(at: x), old >= top - 1, new <= top else { return nil }
            return (s, top)
        }.max { $0.top < $1.top }
    }

    func click(_ id: UUID, at point: SIMD2<Float>, debris: inout [Debris]) {
        guard let i = figures.firstIndex(where: { $0.id == id }) else { return }
        _ = figures[i].snowman.hit(at: point, debris: &debris)
    }

    func updateVisibility(occluders: [CGRect], windows: [(key: Int, rect: CGRect)]) {
        for i in balls.indices {
            let b = balls[i]
            balls[i].hidden = b.id != dragged && (occluders.contains { $0.intersects(b.rect) }
                || (!b.falling && windows.contains { $0.key != b.hostKey && $0.rect.intersects(b.rect.insetBy(dx: 4, dy: 4)) }))
        }
        for i in figures.indices {
            guard let r = figures[i].snowman.bodyRect else { continue }
            let s = figures[i].snowman
            figures[i].snowman.hidden = !s.carried && occluders.contains { $0.intersects(r) }
            figures[i].snowman.ghost = !s.carried && windows.contains { $0.key != s.hostKey && $0.rect.intersects(r) }
        }
    }

    var targets: [Target] {
        balls.filter { !$0.hidden && !$0.falling }.map { Target(id: $0.id, rect: $0.rect) }
            + figures.compactMap { f in
                guard !f.snowman.hidden, let rect = f.snowman.hitRect else { return nil }
                return Target(id: f.id, rect: rect)
            }
    }

    func build(into out: inout [Vertex]) {
        for b in balls where !b.hidden { drawBall(b, into: &out) }
        if let b = rolling { drawBall(b, into: &out) }
        for f in figures where !f.snowman.hidden { f.snowman.build(into: &out) }
        if let h = hint {
            for i in 0..<24 {
                let a = Float(i) / 24 * .pi * 2, b = Float(i + 1) / 24 * .pi * 2
                Mesh.line(&out, (h.x + cos(a) * h.radius, h.y + sin(a) * h.radius),
                          (h.x + cos(b) * h.radius, h.y + sin(b) * h.radius), width: 1.5, color: (0.6, 0.72, 1, 0.8))
            }
        }
    }

    private func drawBall(_ b: Ball, into out: inout [Vertex]) {
        Mesh.circle(&out, cx: b.x, cy: b.y, r: b.radius, center: (1, 1, 1, 1), rim: (0.75, 0.83, 0.98, 1))
    }

    func clear() { balls = []; figures = []; rolling = nil; dragged = nil; hint = nil; rollArea = 0; lastRoll = nil }
}
