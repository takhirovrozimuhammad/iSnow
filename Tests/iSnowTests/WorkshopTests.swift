import Foundation
import Testing
@testable import iSnow

@MainActor
private func rolled(_ w: SnowWorkshop, radius: Float, x: Float, y: Float) -> UUID {
    var area = Float.pi * radius * radius
    w.roll(at: SIMD2(x - 100, y), active: true) { _, _, _ in 0 }
    w.roll(at: SIMD2(x, y), active: true) { _, _, budget in
        let take = min(area, budget)
        area -= take
        return take
    }
    w.finishRolling()
    return w.balls.last!.id
}

@MainActor
private func move(_ w: SnowWorkshop, _ id: UUID, x: Float, y: Float) {
    let b = w.balls.first { $0.id == id }!
    w.drag(id, to: SIMD2(b.x, b.y))
    w.drag(id, to: SIMD2(x, y))
    w.drop(id)
}

private func surface(_ key: Int = -1, x: CGFloat = 0, y: CGFloat = -1, width: CGFloat = 1200) -> CraftSurface {
    CraftSurface(key: key, rect: CGRect(x: x, y: y, width: width, height: 1),
                 heights: Array(repeating: 0, count: Int(width / 4)),
                 visible: Array(repeating: true, count: Int(width / 4)))
}

@MainActor
private func advance(_ w: SnowWorkshop, frames: Int = 120, surfaces: [CraftSurface] = [surface()]) {
    var debris: [Debris] = [], shards: [Shard] = []
    for _ in 0..<frames {
        w.step(dt: 1 / 60, surfaces: surfaces, mouse: nil, temperature: -4, paused: false,
               debris: &debris, shards: &shards)
    }
}

@Test @MainActor func emptyAirDoesNotMakeSnow() {
    let w = SnowWorkshop()
    w.roll(at: SIMD2(20, 20), active: true) { _, _, _ in 0 }
    w.roll(at: SIMD2(300, 20), active: true) { _, _, _ in 0 }
    w.finishRolling()
    #expect(w.balls.isEmpty)
}

@Test @MainActor func holdingStillDoesNotCollect() {
    let w = SnowWorkshop()
    var reads = 0
    for _ in 0..<100 { w.roll(at: SIMD2(20, 20), active: true) { _, _, _ in reads += 1; return 200 } }
    #expect(reads == 0)
    #expect(w.rolling == nil)
}

@Test @MainActor func rollingConservesCollectedArea() {
    let w = SnowWorkshop()
    _ = rolled(w, radius: 22, x: 150, y: 200)
    #expect(abs(w.balls[0].radius - 22) < 0.01)
    #expect(w.rolling == nil)
}

@Test @MainActor func ballRadiusAndCountAreBounded() {
    let w = SnowWorkshop()
    for i in 0..<30 {
        w.roll(at: SIMD2(Float(i * 100), 250), active: true) { _, _, budget in budget }
        w.roll(at: SIMD2(Float(i * 100 + 300), 250), active: true) { _, _, budget in budget }
        w.finishRolling()
    }
    #expect(w.balls.count <= SnowWorkshop.maxBalls)
    #expect(w.balls.allSatisfy { $0.radius <= SnowWorkshop.maxRadius })
}

@Test @MainActor func twoBallsStayAStack() {
    let w = SnowWorkshop()
    let base = rolled(w, radius: 25, x: 150, y: 200)
    let middle = rolled(w, radius: 18, x: 450, y: 200)
    let b = w.balls.first { $0.id == base }!
    move(w, middle, x: b.x, y: b.y + 35)
    #expect(w.balls.count == 2)
    #expect(w.figures.isEmpty)
    #expect(w.balls.first { $0.id == middle }?.parent == base)
}

@Test @MainActor func threeBallsBecomeOneSnowmanWithTheirOwnSizes() {
    let w = SnowWorkshop()
    let base = rolled(w, radius: 25, x: 150, y: 200)
    let middle = rolled(w, radius: 18, x: 450, y: 200)
    let head = rolled(w, radius: 12, x: 750, y: 200)
    let b = w.balls.first { $0.id == base }!
    move(w, middle, x: b.x, y: b.y + 35)
    let m = w.balls.first { $0.id == middle }!
    move(w, head, x: m.x, y: m.y + 25)
    #expect(w.balls.isEmpty)
    #expect(w.figures.count == 1)
    let s = w.figures[0].snowman
    #expect(abs(s.R(0) - 25) < 0.01)
    #expect(abs(s.R(1) - 18) < 0.01)
    #expect(abs(s.R(2) - 12) < 0.01)
    #expect(s.phase == .dressing)
    advance(w)
    #expect(w.figures[0].snowman.phase == .standing)
}

@Test @MainActor func rollingReleaseCanSnapWithoutAnotherDrag() {
    let w = SnowWorkshop()
    let base = rolled(w, radius: 24, x: 150, y: 200)
    let b = w.balls.first { $0.id == base }!
    _ = rolled(w, radius: 16, x: b.x - 16 * 0.35, y: b.y + 32 - 16 * 0.35)
    #expect(w.balls.last?.parent == base)
}

@Test @MainActor func distantBallsDoNotAssemble() {
    let w = SnowWorkshop()
    _ = rolled(w, radius: 24, x: 150, y: 200)
    _ = rolled(w, radius: 18, x: 450, y: 200)
    _ = rolled(w, radius: 12, x: 750, y: 200)
    #expect(w.balls.count == 3)
    #expect(w.figures.isEmpty)
}

@Test @MainActor func stackedBallCannotAttachToItsOwnChild() {
    let w = SnowWorkshop()
    let base = rolled(w, radius: 24, x: 150, y: 200)
    let top = rolled(w, radius: 20, x: 450, y: 200)
    let b = w.balls.first { $0.id == base }!
    move(w, top, x: b.x, y: b.y + 36)
    let t = w.balls.first { $0.id == top }!
    move(w, base, x: t.x, y: t.y + 36)
    #expect(w.balls.first { $0.id == base }?.parent == nil)
}

@Test @MainActor func movedWindowDropsItsBallInsteadOfCarryingIt() {
    let w = SnowWorkshop()
    _ = rolled(w, radius: 20, x: 150, y: 400)
    let window = surface(9, x: 80, y: 199, width: 400)
    advance(w, frames: 60, surfaces: [surface(), window])
    #expect(w.balls[0].hostKey == 9)
    let oldY = w.balls[0].y
    advance(w, frames: 10, surfaces: [surface(), surface(9, x: 90, y: 199, width: 400)])
    #expect(w.balls[0].y < oldY)
    #expect(w.balls[0].falling)
    advance(w)
    #expect(w.balls[0].hostKey == -1)
}

@Test @MainActor func invisibleSurfaceDoesNotCatchBalls() {
    let w = SnowWorkshop()
    _ = rolled(w, radius: 20, x: 150, y: 400)
    var hidden = surface(9, x: 80, y: 199, width: 400)
    hidden.visible = hidden.visible.map { _ in false }
    advance(w, surfaces: [surface(), hidden])
    #expect(w.balls[0].hostKey == -1)
}

@Test @MainActor func panelsHideUnderMenus() {
    let w = SnowWorkshop()
    _ = rolled(w, radius: 20, x: 150, y: 200)
    advance(w)
    #expect(w.targets.count == 1)
    w.updateVisibility(occluders: [w.balls[0].rect], windows: [])
    #expect(w.targets.isEmpty)
}

@Test @MainActor func configKeepsOldPreferencesAndNewDefaults() throws {
    let cfg = SimConfig.decodeLeniently(Data(#"{"density":2.5,"snowman":false}"#.utf8))
    #expect(cfg.density == 2.5)
    #expect(!cfg.snowman)
    #expect(cfg.craftSnow)
    #expect(!cfg.workMode)
    let encoded = try JSONEncoder().encode(cfg)
    #expect(try JSONDecoder().decode(SimConfig.self, from: encoded) == cfg)
}

@Test @MainActor func fullscreenHidesWorkshopTargetsAndRestoresThem() {
    let frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
    let sim = Simulation(screenFrame: frame, visibleFrame: frame, hostsSnowman: false)
    var cfg = SimConfig(); cfg.snowman = false; cfg.fullscreenSnow = 0
    sim.sync(windows: [], occluders: [], dock: nil, icons: [], now: 0, cfg: cfg)
    _ = rolled(sim.workshop, radius: 20, x: 150, y: 200)
    advance(sim.workshop)
    #expect(sim.workshopTargets.count == 1)
    sim.sync(windows: [TrackedWindow(id: 90, frame: frame)], occluders: [], dock: nil, icons: [],
             menuBars: [], now: 1, cfg: cfg)
    #expect(sim.isFullscreenPaused)
    #expect(sim.workshopTargets.isEmpty)
    #expect(sim.workshop.balls.count == 1)
    sim.sync(windows: [], occluders: [], dock: nil, icons: [], now: 2, cfg: cfg)
    #expect(!sim.isFullscreenPaused)
    #expect(sim.workshopTargets.count == 1)
}

@Test @MainActor func realDriftCanBeRolledAndEmptyDriftCannot() {
    let frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
    let sim = Simulation(screenFrame: frame, visibleFrame: frame, hostsSnowman: false)
    var cfg = SimConfig(); cfg.snowman = false; cfg.paused = true
    sim.sync(windows: [], occluders: [], dock: nil, icons: [], now: 0, cfg: cfg)
    for i in 0..<30 { sim.step(dt: 1 / 60, now: Double(i) / 60, mouse: CGPoint(x: CGFloat(100 + i * 8), y: 15), craft: true) }
    sim.step(dt: 1 / 60, now: 1, craft: false)
    #expect(sim.workshop.balls.isEmpty)
    sim.prepareWorkshop()
    for i in 0..<30 { sim.step(dt: 1 / 60, now: 2 + Double(i) / 60, mouse: CGPoint(x: CGFloat(100 + i * 8), y: 15), craft: true) }
    sim.step(dt: 1 / 60, now: 3, craft: false)
    #expect(sim.workshop.balls.count == 1)
    #expect(sim.workshop.balls[0].radius > 6)
}
