import Foundation
import Observation
import ServiceManagement

/// Quick intensity presets (set density, flake count and wind).
enum Intensity: Int, CaseIterable, Identifiable, Sendable {
    case light, normal, blizzard, storm
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .light: String(localized: "Yengil")
        case .normal: String(localized: "Sokin")
        case .blizzard: String(localized: "Bo‘ron")
        case .storm: String(localized: "Qattiq bo‘ron")
        }
    }
    var density: Double { [0.45, 1.25, 4.0, 8.1][rawValue] }
    var maxFlakes: Double { [310, 875, 2500, 5000][rawValue] }
    var wind: Double { [0.6, 1.0, 1.6, 2.6][rawValue] }
}

/// All simulation settings. Stored as JSON; missing keys fall back to defaults.
struct SimConfig: Codable, Equatable, Sendable {
    // Snowfall
    var density: Double = 1.25         // multiple of 28 flakes/s per 1000 pt of width
    var maxFlakes: Double = 875
    var flakeSize: Double = 1.25
    var fallSpeed: Double = 1.0
    var wind: Double = 1.0
    var sparkle: Bool = false
    var tint: [Double] = [1, 1, 1]
    // Drifts
    var onWindows = true
    var onDock = true
    var onIcons = true
    var onWidgets = true
    var onMenuBar = true
    var unlimitedDrifts = true         // drifts keep growing into hills (only the screen top limits them)
    var windowDepth: Double = 36       // max drift height on a window, in points (when limited)
    var groundDepth: Double = 34
    var accumulation: Double = 3.5     // how fast snow piles up
    var temperature: Double = -4       // °C: above zero snow melts, below zero windows frost over
    var windowFrost = true
    var calmActive = true              // flakes fade to a light dusting over the frontmost window
    var icicles = true
    var icicleLength: Double = 1.0
    // Snowman
    var snowman = true
    var snowmanSize: Double = 1.3
    var snowmanCount: Double = 1
    var snowmanGhost = true            // fade a snowman that covers a window
    var snowmanBreak: Double = 2.0     // minutes between snowmen
    var snowballs = true
    var throwEvery: Double = 30        // seconds
    // Christmas
    var christmas = false
    var christmasTree = true
    var christmasGarland = true
    var christmasHats = true
    var lightStyle = 0                 // Christmas.LightStyle
    var treeSize: Double = 1.3
    var lightSize: Double = 1.0        // size of the Christmas light bulbs
    var lightGlow: Double = 1.0        // how strongly they shine (0 = no glow)
    var snowplow = true                // drive a snowplow along the bottom with ⌥⌘ + ←/→
    var autoPlow = true                // the snowplow clears the bottom by itself now and then
    var autoPlowEvery: Double = 15     // (unused since 1.1 – the plow now comes by snow height)
    var autoPlowHeight: Double = 60    // the plow comes when the snow at the bottom is this high (points)
    var santa = true                   // Santa's sleigh flies by now and then in Christmas mode
    var skier = true                   // a skier rides down the snow hills on windows now and then
    var skierEvery: Double = 6         // (unused since 1.1 – see skierInterval)
    var skierInterval: Double = 2      // minutes between groups of skiers
    var skierCount: Double = 3         // how many skiers ride together (one after another)
    var lightsWhilePaused = false      // keep the Christmas lights twinkling while the snow is paused
    // Other
    var mouse = true
    var craftSnow = true               // Option rolls real drift snow into a ball; Option+Shift shovels
    var workMode = false               // effective settings are capped without overwriting the user's sliders
    var frost = false
    var pauseFullscreen = true         // detect full-screen apps (hide decorations there)
    var fullscreenSnow: Double = 0.3   // opacity of the snowfall over full-screen apps (0 = no snow)
    var fahrenheit = Locale.current.measurementSystem == .us
    var batterySaver = true            // on battery: 30 fps, 1× rendering, fewer flakes, no sparkle
    var retina = false                 // render at the screen's full Retina resolution (costs battery)
    var hideFromCapture = false        // keep the snow out of screenshots and screen sharing
    var fps: Int = 60
    var calmLowerRate = false          // draw calm snowfall at 30 fps (saves power)
    // Runtime only (not persisted)
    var paused = false

    private enum CodingKeys: String, CodingKey {
        case density, maxFlakes, flakeSize, fallSpeed, wind, sparkle, tint, onWindows, onDock, onIcons, onWidgets, onMenuBar,
             unlimitedDrifts, windowDepth, groundDepth, accumulation, temperature, windowFrost, icicles, icicleLength, snowman,
             snowmanSize, snowmanCount, snowmanGhost, craftSnow, workMode,
             snowmanBreak, snowballs, throwEvery, christmas, christmasTree, christmasGarland, christmasHats, lightStyle,
             treeSize, lightSize, lightGlow, santa, skier, skierEvery, skierInterval, skierCount, snowplow, autoPlow, autoPlowEvery, autoPlowHeight, lightsWhilePaused, calmActive, fahrenheit, batterySaver, retina, hideFromCapture, mouse, frost, pauseFullscreen, fullscreenSnow, fps, calmLowerRate
    }

    var preset: Intensity? {
        Intensity.allCases.first { abs($0.density - density) < 0.01 && abs($0.maxFlakes - maxFlakes) < 1 }
    }

    /// Melting in points per minute: nothing below zero (the snowplow keeps the bottom clear),
    /// fast thaw above zero.
    var meltBase: Float {
        let t = Float(temperature)
        return t > 0 ? 4 + t * 4 : 0
    }

    mutating func apply(_ p: Intensity) {
        density = p.density
        maxFlakes = p.maxFlakes
        wind = p.wind
    }

    /// Reads the stored config. A key with a wrong type only falls back to its own default (the other keys
    /// are kept), and every value is clamped to the range the settings UI allows.
    static func load(from d: UserDefaults) -> SimConfig {
        guard let data = d.data(forKey: "config") else { return SimConfig() }
        var cfg = decodeLeniently(data)
        // The plow used to come at 30 pt – let the hill grow higher now (one-time update of the old default).
        if !d.bool(forKey: "plowHeight60") {
            d.set(true, forKey: "plowHeight60")
            if cfg.autoPlowHeight == 30 { cfg.autoPlowHeight = 60 }
        }
        return cfg
    }

    /// Merges the stored JSON into the defaults key by key, keeping only the keys that decode.
    static func decodeLeniently(_ data: Data) -> SimConfig {
        let decoder = JSONDecoder()
        guard let stored = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let defData = try? JSONEncoder().encode(SimConfig()),
              var merged = try? JSONSerialization.jsonObject(with: defData) as? [String: Any] else { return SimConfig() }
        let known = Set(merged.keys)
        // Fast path: everything decodes.
        var all = merged
        for (k, v) in stored where known.contains(k) { all[k] = v }
        if let out = try? JSONSerialization.data(withJSONObject: all),
           let cfg = try? decoder.decode(SimConfig.self, from: out) {
            return cfg.clamped()
        }
        // Slow path: try each stored key on its own and drop the ones that don't decode.
        for (k, v) in stored where known.contains(k) {
            var trial = merged
            trial[k] = v
            if let out = try? JSONSerialization.data(withJSONObject: trial),
               (try? decoder.decode(SimConfig.self, from: out)) != nil {
                merged = trial
            }
        }
        guard let out = try? JSONSerialization.data(withJSONObject: merged),
              let cfg = try? decoder.decode(SimConfig.self, from: out) else { return SimConfig() }
        return cfg.clamped()
    }

    /// The config with every value inside the range the settings UI allows (non-finite values get the default).
    func clamped() -> SimConfig {
        let def = SimConfig()
        var c = self
        func fit(_ v: Double, _ r: ClosedRange<Double>, _ fallback: Double) -> Double {
            v.isFinite ? min(max(v, r.lowerBound), r.upperBound) : fallback
        }
        c.density = fit(density, Ranges.density, def.density)
        c.autoPlowEvery = fit(autoPlowEvery, 2...120, def.autoPlowEvery)
        c.autoPlowHeight = fit(autoPlowHeight, 10...150, def.autoPlowHeight)
        c.fullscreenSnow = fit(fullscreenSnow, 0...1, def.fullscreenSnow)
        c.lightSize = fit(lightSize, 0.5...2.5, def.lightSize)
        c.lightGlow = fit(lightGlow, 0...2.5, def.lightGlow)
        c.maxFlakes = fit(maxFlakes, Ranges.maxFlakes, def.maxFlakes)
        c.flakeSize = fit(flakeSize, Ranges.flakeSize, def.flakeSize)
        c.fallSpeed = fit(fallSpeed, Ranges.fallSpeed, def.fallSpeed)
        c.wind = fit(wind, Ranges.wind, def.wind)
        c.windowDepth = fit(windowDepth, Ranges.windowDepth, def.windowDepth)
        c.groundDepth = fit(groundDepth, Ranges.groundDepth, def.groundDepth)
        c.accumulation = fit(accumulation, Ranges.accumulation, def.accumulation)
        c.temperature = fit(temperature, Ranges.temperature, def.temperature)
        c.icicleLength = fit(icicleLength, Ranges.icicleLength, def.icicleLength)
        c.snowmanSize = fit(snowmanSize, Ranges.snowmanSize, def.snowmanSize)
        c.snowmanCount = fit(snowmanCount, Ranges.snowmanCount, def.snowmanCount).rounded()
        c.snowmanBreak = fit(snowmanBreak, Ranges.snowmanBreak, def.snowmanBreak)
        c.throwEvery = fit(throwEvery, Ranges.throwEvery, def.throwEvery)
        c.treeSize = fit(treeSize, Ranges.treeSize, def.treeSize)
        c.skierEvery = fit(skierEvery, Ranges.skierEvery, def.skierEvery)
        c.skierInterval = fit(skierInterval, Ranges.skierEvery, def.skierInterval)
        c.skierCount = fit(skierCount, 1...5, def.skierCount).rounded()
        c.fps = Ranges.fps.min { abs($0 - fps) < abs($1 - fps) } ?? def.fps
        c.lightStyle = min(max(lightStyle, Ranges.lightStyle.lowerBound), Ranges.lightStyle.upperBound)
        c.tint = (0..<3).map { i in i < tint.count ? fit(tint[i], 0...1, 1) : 1 }
        return c
    }

    /// The ranges of the settings sliders – also used to clamp a loaded config.
    enum Ranges {
        static let density: ClosedRange<Double> = 0.1...10
        static let maxFlakes: ClosedRange<Double> = 50...6000
        static let flakeSize: ClosedRange<Double> = 0.4...3
        static let fallSpeed: ClosedRange<Double> = 0.2...3
        static let wind: ClosedRange<Double> = 0...4
        static let windowDepth: ClosedRange<Double> = 4...90
        static let groundDepth: ClosedRange<Double> = 4...120
        static let accumulation: ClosedRange<Double> = 0.3...8
        static let temperature: ClosedRange<Double> = -25...10          // °C
        static let icicleLength: ClosedRange<Double> = 0.3...3
        static let snowmanSize: ClosedRange<Double> = 0.5...3.5
        static let snowmanCount: ClosedRange<Double> = 1...6
        static let snowmanBreak: ClosedRange<Double> = 0.2...20        // minutes
        static let throwEvery: ClosedRange<Double> = 3...180           // seconds
        static let treeSize: ClosedRange<Double> = 0.5...3
        static let skierEvery: ClosedRange<Double> = 0.5...60          // minutes (from 30 s)
        static let fps = [30, 60, 120]
        static let lightStyle: ClosedRange<Int> = 0...2
    }
}

/// Temperature conversion and formatting. Values are stored in °C.
enum Temp {
    static func toFahrenheit(_ c: Double) -> Double { c * 9 / 5 + 32 }
    static func toCelsius(_ f: Double) -> Double { (f - 32) * 5 / 9 }

    /// "−4 °C" / "25 °F": whole degrees with a true minus sign.
    static func format(_ celsius: Double, fahrenheit: Bool) -> String {
        let v = fahrenheit ? toFahrenheit(celsius) : celsius
        let n = v.isFinite ? Int(v.rounded()) : 0
        let number = n < 0 ? "\u{2212}\(-n)" : "\(n)"
        return number + (fahrenheit ? " °F" : " °C")
    }
}

@MainActor @Observable
final class Settings {
    static let shared = Settings()

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var persists = true

    var config: SimConfig {
        didSet {
            guard config != oldValue else { return }
            scheduleSave()
            onChange?()
        }
    }

    var paused: Bool {
        get { config.paused }
        set { config.paused = newValue }
    }

    /// Whether the app has Accessibility permission (Dock and desktop icons).
    /// Assigning the same value again does not notify observers (the tracker sets it every second).
    var axTrusted: Bool {
        get { axTrustedValue }
        set { if axTrustedValue != newValue { axTrustedValue = newValue } }
    }
    private var axTrustedValue = false

    /// Whether iSnow is registered as a login item (also true while it waits for approval).
    private(set) var launchAtLogin = false
    /// The login item's state as reported by the system.
    private(set) var loginStatus: SMAppService.Status = .notRegistered
    /// Why the last attempt to change the login item failed, for the settings window.
    private(set) var loginError: String?

    private init() {
        config = SimConfig.load(from: .standard)
        refreshLoginStatus()
    }

    /// A throwaway instance for screenshots – never touches the user's saved settings.
    init(preview: SimConfig) {
        config = preview
        persists = false
        axTrustedValue = true
    }

    func resetToDefaults() {
        let p = config.paused
        config = SimConfig()
        config.paused = p
    }

    private func scheduleSave() {
        // Sliders change values continuously – save with a short delay.
        guard persists else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            self.write()
        }
    }

    /// Cancels the pending delayed save and writes the settings right away (call on quit).
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        write()
    }

    private func write() {
        guard persists, let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: "config")
    }

    // MARK: Launch at login

    /// Re-reads the login item's state (it can be changed in System Settings at any time).
    func refreshLoginStatus() {
        guard persists else { return }
        let status = SMAppService.mainApp.status
        if loginStatus != status { loginStatus = status }
        let on = status == .enabled || status == .requiresApproval
        if launchAtLogin != on { launchAtLogin = on }
        if on, loginError != nil { loginError = nil }
    }

    func setLaunchAtLogin(_ on: Bool) {
        guard persists else { return }
        loginError = nil
        if on, let reason = Self.cannotRegisterReason() {
            loginError = reason
            refreshLoginStatus()
            return
        }
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("iSnow: login item – \(error.localizedDescription)")
            loginError = error.localizedDescription
        }
        refreshLoginStatus()
    }

    /// A copy started from the disk image or quarantined in Downloads runs from a temporary or read-only
    /// location – a login item would point there.
    private static func cannotRegisterReason() -> String? {
        let url = Bundle.main.bundleURL
        let readOnly = (try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly ?? false
        if url.path.contains("/AppTranslocation/") || readOnly {
            return String(localized: "Move iSnow to the Applications folder and open it from there first.")
        }
        return nil
    }
}
