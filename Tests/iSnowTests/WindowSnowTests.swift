import CoreGraphics
import Testing
@testable import iSnow

private let snowWindow = TrackedWindow(id: 101, frame: CGRect(x: 160, y: 350, width: 400, height: 180))

@MainActor private func windowScene(_ windows: [TrackedWindow] = [snowWindow], safeTop: CGFloat = 0)
    -> (Simulation, SimConfig) {
    let sim = Simulation(screenFrame: CGRect(x: 0, y: 0, width: 1200, height: 800),
                         visibleFrame: CGRect(x: 0, y: 60, width: 1200, height: 712),
                         hostsSnowman: false, safeTop: safeTop)
    var cfg = SimConfig()
    cfg.paused = true
    cfg.snowman = false; cfg.onDock = false; cfg.onIcons = false; cfg.onWidgets = false
    cfg.onMenuBar = false; cfg.icicles = false; cfg.windowFrost = false; cfg.frost = false
    cfg.christmas = false; cfg.skier = false
    sim.sync(windows: windows, occluders: [], dock: nil, icons: [], now: 0, cfg: cfg)
    return (sim, cfg)
}

@MainActor private func mesh(_ sim: Simulation) -> [Vertex] {
    var vertices: [Vertex] = []; sim.buildMesh(into: &vertices); return vertices
}

@MainActor private func particles(_ sim: Simulation) -> [Particle] {
    var result: [Particle] = []; sim.buildParticles(into: &result); return result
}

@Test @MainActor func regularWindowsCollectVisibleSnow() {
    let (sim, _) = windowScene()
    #expect(mesh(sim).isEmpty)
    sim.addWindowSnow()
    let vertices = mesh(sim)
    #expect(!vertices.isEmpty)
    #expect(vertices.allSatisfy { $0.y >= 529 && $0.y <= 543 })
}

@Test @MainActor func onePixelMoveDetachesSnowAtItsPreviousLocation() {
    let (sim, cfg) = windowScene()
    sim.addWindowSnow()
    let shifted = TrackedWindow(id: 101, frame: snowWindow.frame.offsetBy(dx: 1, dy: 0))
    sim.sync(windows: [shifted], occluders: [], dock: nil, icons: [], now: 0.1, cfg: cfg)
    #expect(mesh(sim).isEmpty)
    let chunks = particles(sim).filter { $0.size < 0 }
    #expect(!chunks.isEmpty)
    #expect(chunks.allSatisfy { $0.y >= 530 && $0.y <= 543 })
    for i in 0..<20 { sim.step(dt: 1 / 60, now: 0.1 + Double(i) / 60) }
    #expect(particles(sim).contains { $0.size < 0 && $0.y < 520 })
    #expect(mesh(sim).allSatisfy { $0.y < 529 })
}

@Test @MainActor func fallingSnowLandsOnALowerWindowButNotItsSource() {
    let (sim, cfg) = windowScene()
    sim.addWindowSnow()
    let lower = TrackedWindow(id: 102, frame: CGRect(x: 60, y: 80, width: 900, height: 120))
    let shifted = TrackedWindow(id: 101, frame: snowWindow.frame.offsetBy(dx: 1, dy: 0))
    sim.sync(windows: [shifted, lower], occluders: [], dock: nil, icons: [], now: 0.1, cfg: cfg)
    for i in 0..<150 { sim.step(dt: 1 / 60, now: 0.1 + Double(i) / 60) }
    let vertices = mesh(sim)
    #expect(vertices.contains { $0.y >= 200 && $0.y < 300 })
    #expect(!vertices.contains { $0.y >= 529 })
}

@Test @MainActor func resizingAWindowReleasesTheOldDrift() {
    let (sim, cfg) = windowScene()
    sim.addWindowSnow()
    let resized = TrackedWindow(id: 101, frame: CGRect(x: 160, y: 350, width: 600, height: 180))
    sim.sync(windows: [resized], occluders: [], dock: nil, icons: [], now: 0.1, cfg: cfg)
    #expect(mesh(sim).isEmpty)
    #expect(!particles(sim).isEmpty)
}

@Test @MainActor func closingSeveralWindowsDropsTheirSnow() {
    let other = TrackedWindow(id: 102, frame: CGRect(x: 650, y: 250, width: 400, height: 180))
    let (sim, cfg) = windowScene([snowWindow, other])
    sim.addWindowSnow()
    sim.sync(windows: [], occluders: [], dock: nil, icons: [], now: 0.1, cfg: cfg)
    #expect(!particles(sim).isEmpty)
    #expect(mesh(sim).isEmpty)
}

@Test @MainActor func aSpaceSwitchPreservesTheDriftInsteadOfDroppingIt() {
    let (sim, cfg) = windowScene()
    sim.addWindowSnow()
    sim.noteSpaceChange(now: 0.1)
    sim.sync(windows: [], occluders: [], dock: nil, icons: [], now: 0.2, cfg: cfg)
    #expect(particles(sim).isEmpty)
    sim.sync(windows: [snowWindow], occluders: [], dock: nil, icons: [], now: 0.3, cfg: cfg)
    #expect(!mesh(sim).isEmpty)
}

@Test @MainActor func fullscreenWindowsCannotCollectSnowEvenWithTheGlobalPauseOff() {
    let (sim, base) = windowScene([], safeTop: 32)
    var cfg = base; cfg.pauseFullscreen = false
    let full = TrackedWindow(id: 201, frame: CGRect(x: 0, y: 0, width: 1200, height: 768))
    sim.sync(windows: [full], occluders: [], dock: nil, icons: [], now: 0.1, cfg: cfg)
    sim.addWindowSnow()
    #expect(mesh(sim).isEmpty)
}

@Test @MainActor func revealingTheMenuBarDoesNotResumeSnowOverNotchedFullscreen() {
    let (sim, cfg) = windowScene(safeTop: 32)
    sim.addWindowSnow()
    let full = TrackedWindow(id: 101, frame: CGRect(x: 0, y: 0, width: 1200, height: 768))
    let bar = CGRect(x: 0, y: 772, width: 1200, height: 28)
    sim.sync(windows: [full], occluders: [], dock: nil, icons: [], menuBars: [bar], now: 0.1, cfg: cfg)
    #expect(sim.isFullscreenPaused)
    #expect(mesh(sim).isEmpty)
    #expect(particles(sim).isEmpty)
    sim.sync(windows: [snowWindow], occluders: [], dock: nil, icons: [], now: 0.2, cfg: cfg)
    #expect(!mesh(sim).isEmpty)
}

@Test @MainActor func turningWindowSnowOffClearsItWithoutAnExtraSnowShower() {
    let (sim, base) = windowScene()
    sim.addWindowSnow()
    var cfg = base; cfg.onWindows = false
    sim.sync(windows: [snowWindow], occluders: [], dock: nil, icons: [], now: 0.1, cfg: cfg)
    #expect(mesh(sim).isEmpty)
    #expect(particles(sim).isEmpty)
}
