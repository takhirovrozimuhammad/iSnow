import AppKit
import IOKit.ps
import SwiftUI

@main
struct ISnowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var settings = Settings.shared
    @State private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(settings: settings, state: state, delegate: delegate)
        } label: {
            Image(nsImage: ISnowBrand.image(size: 18, template: true))
                .opacity(settings.paused || state.hidden ? 0.45 : 1)
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuContent: View {
    @Bindable var settings: Settings
    let state: AppState
    let delegate: AppDelegate

    private static let temperatures: [Double] = [-20, -10, -4, 0, 2, 6]

    var body: some View {
        if state.hidden {
            if let until = state.hiddenUntil {
                Button("Show Effects (until \(until.formatted(date: .omitted, time: .shortened)))") { delegate.showEffects() }
            } else {
                Button("Effektlarni ko‘rsatish") { delegate.showEffects() }
            }
        } else {
            Menu("Effektlarni yashirish") {
                Button("15 daqiqaga") { delegate.hideEffects(until: Date().addingTimeInterval(15 * 60)) }
                Button("1 soatga") { delegate.hideEffects(until: Date().addingTimeInterval(3600)) }
                Button("Ertagacha") { delegate.hideEffects(until: AppState.nextMorning()) }
                Button("O‘zim yoqqunimcha") { delegate.hideEffects(until: nil) }
            }
        }
        if state.fullscreenPaused && !state.hidden {
            Text(settings.config.fullscreenSnow < 0.02 ? LocalizedStringKey("Paused – full-screen app")
                                                         : LocalizedStringKey("Light snow – full-screen app"))
        }
        if state.batterySaverActive && !state.hidden {
            Text("Quvvat tejash yoqilgan")
        }
        Divider()
        Toggle("Qor yog‘ishi", isOn: Binding(get: { !settings.paused }, set: { settings.paused = !$0 }))
            .keyboardShortcut("s")
        Picker("Qor zichligi", selection: Binding<Intensity?>(
            get: { settings.config.preset },
            set: { if let p = $0 { settings.config.apply(p) } })) {
            ForEach(Intensity.allCases) { Text($0.title).tag(Optional($0)) }
        }
        Picker("Temperature", selection: Binding<Double>(
            get: { settings.config.temperature.rounded() },
            set: { settings.config.temperature = $0 })) {
            let f = settings.config.fahrenheit
            ForEach(Self.temperatures, id: \.self) { Text(Temp.format($0, fahrenheit: f)).tag($0) }
            if !Self.temperatures.contains(settings.config.temperature.rounded()) {
                Text(Temp.format(settings.config.temperature, fahrenheit: f)).tag(settings.config.temperature.rounded())
            }
        }
        Divider()
        Toggle("Oynalarda qor", isOn: $settings.config.onWindows)
        Toggle("Vidjetlarda qor", isOn: $settings.config.onWidgets)
        Toggle("Dock’da qor", isOn: $settings.config.onDock)
        Toggle("Avtomatik qor odam", isOn: $settings.config.snowman)
        Toggle("Ish rejimi", isOn: $settings.config.workMode)
        Button("Qor odamni o‘zim yasayman…") { delegate.prepareSnowWorkshop(); delegate.showSettings(tab: 2) }
        Toggle("Bayram rejimi", isOn: $settings.config.christmas)
        Toggle("Kursor qorni sochsin", isOn: $settings.config.mouse)
        if !settings.axTrusted && (settings.config.onDock || settings.config.onIcons || settings.config.snowman) {
            Text("Dock joyi taxminiy")
            Button("Dock va ikonlar uchun ruxsat…") { Tracker.requestAccessibility() }
        }
        Divider()
        if settings.config.christmas {
            Button("Qorboboni chaqirish") { delegate.launchSanta() }
                .disabled(state.hidden)
        }
        Button("Qorlarni silkitish") { delegate.shakeAll() }
        Button("Pastdagi qorni tozalash") { delegate.shovelBottom() }
        Button("Sozlamalar…") { delegate.showSettings() }
            .keyboardShortcut(",")
        Divider()
        Button("iSnow’dan chiqish") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings.shared
    private let state = AppState.shared
    private let tracker = Tracker()
    private var renderer: Renderer?
    private var overlays: [Overlay] = []
    private var panels: [SnowmanPanel] = []
    /// The only repeating timer: window polls, and from there the Dock probe and the power backup.
    /// While the effects are hidden it is a one-shot timer for the end of the hide period.
    private var pollTimer: Timer?
    private var screenTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var mouseMonitor: Any?
    private var settingsWindow: NSWindow?
    private var settingsHost: NSHostingController<AnyView>?
    private var settingsGeneration = 0
    private var settingsCloseObserver: NSObjectProtocol?
    private var settingsRelease: DispatchWorkItem?
    private var onBattery = false
    private var lastDock: CGRect?
    /// For the IOKit power-source callback, which cannot capture anything.
    private static weak var current: AppDelegate?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let i = CommandLine.arguments.firstIndex(of: "--studio-preview"), i + 1 < CommandLine.arguments.count {
            StudioPreview.run(directory: CommandLine.arguments[i + 1], delegate: self)
            return
        }
        if let i = CommandLine.arguments.firstIndex(of: "--promo"), i + 1 < CommandLine.arguments.count {
            // Render the README screenshots (desktop scenes and the settings window), then quit.
            Promo.run(dir: CommandLine.arguments[i + 1], delegate: self)
            return
        }
        if CommandLine.arguments.contains("--print-dock") {
            // Debug: show the Dock frame estimated without Accessibility.
            print("estimated Dock:", Tracker.estimatedDockFrame(includeMinimized: false).map { "\($0)" } ?? "none",
                  "safe area:", Tracker.estimatedDockFrame(includeMinimized: true).map { "\($0)" } ?? "none",
                  "minimized windows:", Tracker.minimizedWindowCount())
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            Snapshot.run(path: CommandLine.arguments[i + 1])
            exit(0)
        }
        guard let r = Renderer() else {
            NSLog("iSnow: Metal is not available")
            NSApp.terminate(nil)
            return
        }
        renderer = r
        Self.current = self
        checkAccessibilityAtLaunch()
        settings.onChange = { [weak self] in self?.settingsChanged() }
        startPowerMonitor()
        tracker.refreshWindows()
        rebuildOverlays()           // polls once – which also starts the poll timer and the first Dock probe

        let nc = NotificationCenter.default
        let ws = NSWorkspace.shared.notificationCenter
        let dnc = DistributedNotificationCenter.default()
        observers.append(nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.scheduleRebuild() }
        })
        observers.append(nc.addObserver(forName: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.refreshPower(pollAfter: false); self.poll(fresh: false) }   // Low Power Mode → 30 fps
        })
        // A newly frontmost app is the common change that comes without the mouse (⌘-Tab, Dock, launch).
        // Polled on the next run-loop turn so the tracker's own observers have seen it first.
        observers.append(ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self.poll() } }
        })
        // Launching or quitting an app changes the Dock: probe it every second again for a while.
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { self.dockMayChange() }
            })
        }
        // A sleeping Mac does not advance timers: re-arm them (e.g. the end of Hide Effects) on wake.
        observers.append(ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.poll() }
        })
        // A window drag cannot start without a button press: poll quicker as soon as one goes down,
        // so the drift breaks off promptly although the static desktop is polled only 2.5× per second.
        // (Mouse events need no permission for a global monitor; it never sees the event's contents.)
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { _ in
            MainActor.assumeIsolated { self.mouseWentDown() }
        }
        // Things that hide the desktop: display sleep, fast user switching, the lock screen, the screen saver.
        let pairs: [(Notification.Name, Notification.Name, String, Bool)] = [
            (NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification, "sleep", false),
            (NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification, "session", true),
        ]
        for (off, on, reason, clearsAll) in pairs {
            observers.append(ws.addObserver(forName: off, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { self.suspend(reason, true) }
            })
            observers.append(ws.addObserver(forName: on, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { self.suspend(reason, false, clearAll: clearsAll) }
            })
        }
        let distributed: [(String, String, String, Bool)] = [
            ("com.apple.screenIsLocked", "com.apple.screenIsUnlocked", "lock", true),
            ("com.apple.screensaver.didstart", "com.apple.screensaver.didstop", "saver", false),
        ]
        for (off, on, reason, clearsAll) in distributed {
            observers.append(dnc.addObserver(forName: Notification.Name(off), object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { self.suspend(reason, true) }
            })
            observers.append(dnc.addObserver(forName: Notification.Name(on), object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { self.suspend(reason, false, clearAll: clearsAll) }
            })
        }
        observers.append(ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                // Windows on the Space we left vanish from the list – they keep their snow.
                let now = CACurrentMediaTime()
                for o in self.overlays { o.sim.noteSpaceChange(now: now) }
                self.poll()
            }
        })
        if !UserDefaults.standard.bool(forKey: "winterStudioWelcomeShown") {
            UserDefaults.standard.set(true, forKey: "winterStudioWelcomeShown")
            DispatchQueue.main.async { self.showSettings(tab: 2) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        settings.saveNow()
    }

    /// Opening the app again (Finder, Spotlight) shows the settings – a way in when the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    // MARK: - Polling

    private var suspendReasons: Set<String> = []
    private var suspended: Bool { !suspendReasons.isEmpty }
    /// Interval of the repeating poll timer; 0 while there is none (hidden, suspended).
    private var pollInterval = 0.0
    private var lastMotion = -100.0            // a window last moved
    private var lastChange = 0.0               // the tracker last reported a change
    private var lastRevision: UInt64?
    private var lastPanelRects: [CGRect?] = []
    private var lastMetrics = -100.0
    private var metricsDirty = true            // settings, screens or power changed: re-read the metrics now
    private var nextAX = 0.0                   // when the next Dock / icon probe is due
    private var axProbes = 0
    private var axStable = 0                   // probes in a row that found the same Dock
    private var axLastDock: CGRect?
    private var nextPowerCheck = 0.0

    private func setPollInterval(_ t: Double) {
        guard t != pollInterval else { return }
        pollInterval = t
        pollTimer?.invalidate()
        let timer = Timer(timeInterval: t, repeats: true) { _ in MainActor.assumeIsolated { self.poll() } }
        timer.tolerance = PollSchedule.tolerance(for: t)
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    /// No repeating poll: nothing may wake the app while it is suspended or hidden.
    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        pollInterval = 0
    }

    /// While hidden: a single wake-up when the hide period runs out (none for "until I turn it back on").
    private func armHiddenTimer() {
        stopPolling()
        guard let until = state.hiddenUntil else { return }
        let t = Timer(fire: until, interval: 0, repeats: false) { _ in MainActor.assumeIsolated { self.poll() } }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t
    }

    private func suspend(_ reason: String, _ on: Bool, clearAll: Bool = false) {
        let was = suspended
        if on { suspendReasons.insert(reason) } else if clearAll { suspendReasons.removeAll() } else { suspendReasons.remove(reason) }
        guard suspended != was else { return }
        for o in overlays { o.suspended = suspended }
        if suspended {
            stopPolling()
        } else {
            metricsDirty = true
            refreshPower(pollAfter: false)
            poll()                      // restarts the timer (or the hide timer) and checks the hide period
        }
    }

    /// A mouse button went down somewhere: a window drag may start – look more often until it is released.
    private func mouseWentDown() {
        guard !suspended, !state.hidden, pollInterval > PollSchedule.pressed,
              !overlays.allSatisfy({ $0.sim.isFullscreenPaused }) else { return }
        setPollInterval(PollSchedule.pressed)
    }

    /// An app launched or quit: its Dock tile appears or goes away.
    private func dockMayChange() {
        axStable = 0
        nextAX = min(nextAX, CACurrentMediaTime() + 0.5)
    }

    /// Reads the windows (unless `fresh` is false – then only the settings are passed on), probes the Dock
    /// when due, syncs every simulation and picks the next poll interval.
    private func poll(fresh: Bool = true) {
        guard !suspended else { stopPolling(); return }
        if state.hideExpired() { showEffects(); return }
        guard !state.hidden else { armHiddenTimer(); return }
        let now = CACurrentMediaTime()
        if now >= nextPowerCheck {
            nextPowerCheck = now + PollSchedule.powerCheck
            refreshPower(pollAfter: false)
        }
        let allFullscreen = !overlays.isEmpty && overlays.allSatisfy { $0.sim.isFullscreenPaused }
        let wasAnimating = overlays.contains { $0.sim.isAnimating }
        probeAXIfDue(now: now, animating: wasAnimating, allFullscreen: allFullscreen)
        if fresh { tracker.refreshWindows() }
        if tracker.revision != lastRevision {
            lastRevision = tracker.revision
            lastChange = now
        }
        let cfg = effectiveConfig()
        if tracker.dockFrame != lastDock {
            lastDock = tracker.dockFrame
            assignSnowmanHost()
        }
        // Menu bar auto-hide, Dock size and the notch can change without a screen notification – but
        // not often: read them once a second, and at once when something says they changed.
        let screens: [CGDirectDisplayID: NSScreen]?
        if metricsDirty || now - lastMetrics >= PollSchedule.metricsEvery {
            metricsDirty = false
            lastMetrics = now
            let s = screensByID()
            applyDisplayOptions(s)
            screens = s
        } else {
            screens = nil
        }
        for o in overlays {
            if let s = screens?[o.screenID] {
                o.sim.updateMetrics(screenFrame: s.frame, visibleFrame: s.visibleFrame, safeTop: s.safeAreaInsets.top)
            }
            o.fps = cfg.fps
            o.calmAtLowerRate = cfg.calmLowerRate
            if o.sim.sync(windows: tracker.windows,
                          occluders: tracker.overlayOccluders + (settingsWindow.flatMap { $0.isVisible ? [$0.frame] : nil } ?? []),
                          dock: tracker.dockFrame,
                          icons: tracker.icons, widgets: tracker.widgets, dockEstimated: tracker.dockEstimated,
                          dockAvoid: tracker.dockAvoid,
                          // In a full-screen Space the menu bar windows stay listed (just auto-hidden), but the
                          // Dock's own window disappears – treat that as "no menu bar" for full-screen detection.
                          menuBars: tracker.dockWindowOnScreen ? tracker.menuBars : [],
                          activeWindow: tracker.activeWindow,
                          now: now, cfg: cfg) || o.sim.isAnimating || NSEvent.modifierFlags.contains(.option) {
                o.wake()
            }
            o.refreshWorkshopPanels()
        }
        let full = overlays.contains { $0.sim.isFullscreenPaused }
        if state.fullscreenPaused != full { state.fullscreenPaused = full }
        let rects = updatePanel()
        // A snowman that is built, falls or lands moves its click target: keep up with it.
        if Self.differ(rects, lastPanelRects) { lastPanelRects = rects; lastChange = now }
        // Follow a dragged window closely so the snow visibly slides off, then calm down again.
        if overlays.contains(where: { $0.sim.windowMoving }) { lastMotion = now; lastChange = now }
        let mouse = NSEvent.mouseLocation
        let atSnowman = panels.contains { $0.isDragging || $0.contains(mouse, margin: 8) }
        setPollInterval(PollSchedule.interval(
            now: now, lastChange: lastChange, lastMotion: lastMotion,
            buttonDown: NSEvent.pressedMouseButtons != 0, atSnowman: atSnowman,
            animating: overlays.contains { $0.sim.isAnimating },
            allFullscreen: !overlays.isEmpty && overlays.allSatisfy { $0.sim.isFullscreenPaused }))
    }

    /// The Dock (and every 4th time the desktop icons) via Accessibility, off the main thread: every
    /// second, every 3 s while the Dock stays put, every 5 s while nothing animates, never while
    /// full-screen apps cover every screen (neither the Dock nor the desktop is visible then).
    /// The tracker calls back only when the Dock or the icons changed.
    private func probeAXIfDue(now: Double, animating: Bool, allFullscreen: Bool) {
        guard !allFullscreen, now >= nextAX else { return }
        if tracker.dockFrame == axLastDock { axStable += 1 } else { axStable = 0; axLastDock = tracker.dockFrame }
        // A little slack so a poll that fires a bit early (timer tolerance) doesn't skip a whole round.
        nextAX = now + PollSchedule.axInterval(stableProbes: axStable, animating: animating,
                                               trusted: settings.axTrusted) - 0.1
        refreshAX()
    }

    private func refreshAX() {
        axProbes += 1
        let c = settings.config
        // Desktop icons barely move: every 4th probe.
        tracker.refreshAX(wantDock: true, wantIcons: c.onIcons && axProbes % 4 == 1) { [weak self] in
            // Only called when the Dock or the icons changed.
            guard let self else { return }
            self.axStable = 0
            self.poll()
        }
        noteAccessibilityGranted()
    }

    private func screensByID() -> [CGDirectDisplayID: NSScreen] {
        var out: [CGDirectDisplayID: NSScreen] = [:]
        for s in NSScreen.screens { out[Overlay.displayID(of: s)] = s }
        return out
    }

    // MARK: - Screens

    /// Display changes come in bursts (sleep/wake, plugging in a monitor): rebuild once things settle.
    private func scheduleRebuild() {
        screenTimer?.invalidate()
        let t = Timer(timeInterval: 0.5, repeats: false) { _ in MainActor.assumeIsolated { self.rebuildOverlays() } }
        RunLoop.main.add(t, forMode: .common)
        screenTimer = t
    }

    /// One overlay per screen. Overlays of screens that did not change are kept with all their snow.
    private func rebuildOverlays() {
        guard let renderer else { return }
        var old = overlays
        var next: [Overlay] = []
        for s in NSScreen.screens {
            if let i = old.firstIndex(where: { $0.matches(s) }) {
                next.append(old.remove(at: i))
            } else {
                let o = Overlay(screen: s, renderer: renderer, hostsSnowman: false)
                o.suspended = suspended
                if state.hidden { o.setHidden(true) }
                next.append(o)
            }
        }
        for o in old { o.close() }
        overlays = next
        lastDock = tracker.dockFrame
        assignSnowmanHost()
        metricsDirty = true
        poll()
    }

    /// The snowmen and the tree live on the screen with the Dock. While the Dock's position is unknown
    /// (hidden, no Accessibility) they stay where they are.
    private func assignSnowmanHost() {
        guard !overlays.isEmpty else { return }
        func frame(_ o: Overlay) -> CGRect { CGRect(origin: o.sim.origin, size: o.sim.size) }
        var host: Int
        if let d = tracker.dockFrame, let i = overlays.firstIndex(where: { frame($0).intersects(d) }) {
            host = i
        } else if let i = overlays.firstIndex(where: { $0.sim.hostsSnowman }) {
            host = i
        } else {
            // The screen whose visible frame is inset at the bottom, otherwise the main screen.
            let screens = screensByID()
            host = overlays.firstIndex { o in
                screens[o.screenID].map { $0.visibleFrame.minY - $0.frame.minY > 8 } ?? false
            } ?? 0
        }
        for (i, o) in overlays.enumerated() where o.sim.hostsSnowman != (i == host) {
            o.sim.hostsSnowman = i == host
            o.wake()
        }
    }

    // MARK: - Power and rendering options

    private func startPowerMonitor() {
        let callback: IOPowerSourceCallbackType = { _ in
            MainActor.assumeIsolated { AppDelegate.current?.refreshPower() }
        }
        if let src = IOPSNotificationCreateRunLoopSource(callback, nil)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        }
        onBattery = AppState.onBatteryPower()
        state.batterySaverActive = onBattery && settings.config.batterySaver
    }

    private func refreshPower(pollAfter: Bool = true) {
        onBattery = AppState.onBatteryPower()
        let saver = onBattery && settings.config.batterySaver
        guard saver != state.batterySaverActive else { return }
        state.batterySaverActive = saver
        metricsDirty = true             // Retina rendering is off on battery
        if pollAfter { poll(fresh: false) }
    }

    /// The settings as the simulations get them: lighter on battery and in Low Power Mode.
    private func effectiveConfig() -> SimConfig {
        var c = settings.config
        if c.workMode {
            c.density = min(c.density, 0.4)
            c.maxFlakes = min(c.maxFlakes, 250)
            c.fps = min(c.fps, 30)
            c.sparkle = false
            c.calmActive = true
            c.fullscreenSnow = min(c.fullscreenSnow, 0.1)
            c.snowman = false
            c.skier = false
            c.santa = false
        }
        if state.batterySaverActive {
            c.fps = min(c.fps, 30)
            c.maxFlakes = min(c.maxFlakes, 500)
            c.density *= 0.6
            c.sparkle = false
        }
        if ProcessInfo.processInfo.isLowPowerModeEnabled { c.fps = min(c.fps, 30) }
        return c
    }

    /// Render scale and screen-capture visibility follow the settings live.
    private func applyDisplayOptions(_ screens: [CGDirectDisplayID: NSScreen]) {
        let cfg = settings.config
        let retina = cfg.retina && !state.batterySaverActive
        for o in overlays {
            o.setRenderScale(retina ? (screens[o.screenID]?.backingScaleFactor ?? 2) : 1)
            o.setHiddenFromCapture(cfg.hideFromCapture)
        }
        for p in panels { p.setHiddenFromCapture(cfg.hideFromCapture) }
    }

    // MARK: - Hide effects

    /// Turn every effect off for a while (nil = until shown again). Nothing is lost.
    func hideEffects(until: Date?) {
        state.hide(until: until)
        for o in overlays { o.setHidden(true) }
        updatePanel()
        armHiddenTimer()
    }

    func showEffects() {
        state.show()
        for o in overlays { o.setHidden(false) }
        metricsDirty = true
        refreshPower(pollAfter: false)
        poll()
    }

    // MARK: - Snowmen

    private var snowmanOverlay: Overlay? { overlays.first { $0.sim.hostsSnowman } }

    /// Click targets that moved by more than 2 pt (or appeared, or went away).
    private static func differ(_ a: [CGRect?], _ b: [CGRect?]) -> Bool {
        guard a.count == b.count else { return true }
        for (x, y) in zip(a, b) {
            switch (x, y) {
            case (nil, nil): continue
            case let (x?, y?):
                if abs(x.minX - y.minX) > 2 || abs(x.minY - y.minY) > 2 || abs(x.width - y.width) > 2
                    || abs(x.height - y.height) > 2 { return true }
            default: return true
            }
        }
        return false
    }

    /// Positions the snowman panels; returns the snowmen's click targets (local coordinates).
    @discardableResult
    private func updatePanel() -> [CGRect?] {
        let rects = state.hidden || suspended ? [] : snowmanOverlay?.sim.snowmanHitRects ?? []
        while panels.count < rects.count {
            let i = panels.count
            let p = SnowmanPanel()
            p.onClick = { [weak self] pt in self?.withSnowman { o, l in o.sim.snowmanClicked(i, at: l(pt)) } }
            p.onDrag = { [weak self] pt in self?.withSnowman { o, l in o.sim.dragSnowman(i, to: l(pt)) } }
            p.onDrop = { [weak self] _ in self?.withSnowman { o, _ in o.sim.dropSnowman(i) } }
            p.setHiddenFromCapture(settings.config.hideFromCapture)
            panels.append(p)
        }
        while panels.count > rects.count { panels.removeLast().close() }
        guard let o = snowmanOverlay, settings.config.snowman else {
            panels.forEach { $0.update(nil) }
            return rects
        }
        for (i, r) in rects.enumerated() {
            panels[i].update(r.map { $0.offsetBy(dx: o.sim.origin.x, dy: o.sim.origin.y) })
        }
        return rects
    }

    /// Runs `body` with the overlay that hosts the snowmen and a global→local point converter.
    private func withSnowman(_ body: (Overlay, (CGPoint) -> CGPoint) -> Void) {
        guard let o = snowmanOverlay else { return }
        let origin = o.sim.origin
        body(o) { CGPoint(x: $0.x - origin.x, y: $0.y - origin.y) }
        o.wake()
    }

    func resetSnowmen() {
        withSnowman { o, _ in o.sim.resetSnowmen() }
    }

    private func settingsChanged() {
        if state.batterySaverActive != (onBattery && settings.config.batterySaver) {
            state.batterySaverActive = onBattery && settings.config.batterySaver
        }
        // The windows are as they were: only pass the new settings on (sliders send many changes).
        metricsDirty = true
        poll(fresh: false)
        for o in overlays { o.wake() }
    }

    func buildSnowmanNow() {
        for o in overlays where o.sim.hostsSnowman { o.sim.buildSnowmanNow(); o.wake() }
    }

    func sendPlow() {
        for o in overlays where o.sim.hostsSnowman { o.sim.sendPlow(); o.wake() }
    }

    /// Sends a skier down the first screen that has a big enough hill on a window.
    func sendSkier() {
        for o in overlays where o.sim.sendSkier() { o.wake(); break }
    }

    func launchSanta() {
        for o in overlays where o.sim.hostsSnowman { o.sim.launchSanta(); o.wake() }
    }

    func shovelBottom() {
        for o in overlays { o.sim.shovelBottom(); o.wake() }
    }

    func shakeAll() {
        for o in overlays { o.sim.shakeAll(); o.wake() }
    }

    func prepareSnowWorkshop() {
        settings.config.craftSnow = true
        settings.config.temperature = min(settings.config.temperature, -4)
        settings.paused = false
        if state.hidden { showEffects() }
        for o in overlays { o.sim.prepareWorkshop(); o.wake() }
    }

    func clearSnowWorkshop() {
        for o in overlays { o.sim.workshop.clear(); o.refreshWorkshopPanels(); o.wake() }
    }

    func showLicenses() {
        if let url = Bundle.main.url(forResource: "NOTICE", withExtension: "md") { NSWorkspace.shared.open(url) }
    }

    // MARK: - Settings window

    /// Opens the settings (or brings them to the front) on the given tab.
    func showSettings(tab: Int = 0) {
        settings.refreshLoginStatus()       // the user may have changed it in System Settings
        settingsRelease?.cancel()           // reopened right after closing: keep the window
        settingsRelease = nil
        let window: NSWindow
        if let w = settingsWindow, let host = settingsHost {
            window = w
            // A new view only when asked for another tab or reopened – otherwise keep the user's tab.
            if !w.isVisible || tab != 0 {
                settingsGeneration += 1
                host.rootView = settingsRoot(tab: tab)
            }
        } else {
            let host = NSHostingController(rootView: settingsRoot(tab: tab))
            // The tabs are scrolling forms without an intrinsic height, so the window must not size
            // itself from the content (it would collapse to the tab bar). Give it a fixed size instead.
            host.sizingOptions = []
            let w = NSWindow(contentViewController: host)
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.title = "iSnow · Winter Studio"
            w.titlebarAppearsTransparent = true
            w.backgroundColor = NSColor(red: 0.055, green: 0.068, blue: 0.13, alpha: 1)
            w.appearance = NSAppearance(named: .darkAqua)
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 900, height: 760))
            w.contentMinSize = NSSize(width: 860, height: 660)
            w.contentMaxSize = NSSize(width: 1200, height: 1400)
            w.center()
            settingsWindow = w
            settingsHost = host
            window = w
            settingsCloseObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
                MainActor.assumeIsolated { self.settingsWillClose() }
            }
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    /// A closed settings window keeps its whole SwiftUI hierarchy (five tabs of forms, ≈ 10–20 MB) –
    /// free it shortly after closing. Opening the settings again builds a fresh one.
    private func settingsWillClose() {
        settingsRelease?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.releaseSettingsWindow() }
        }
        settingsRelease = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func releaseSettingsWindow() {
        settingsRelease = nil
        guard let w = settingsWindow, !w.isVisible else { return }
        // The color panel of the snow-color picker would stay bound to the released view.
        if NSColorPanel.sharedColorPanelExists, NSColorPanel.shared.isVisible { NSColorPanel.shared.close() }
        if let o = settingsCloseObserver { NotificationCenter.default.removeObserver(o) }
        settingsCloseObserver = nil
        w.contentViewController = nil
        settingsHost = nil
        settingsWindow = nil
    }

    private func settingsRoot(tab: Int) -> AnyView {
        AnyView(SettingsView(settings: settings, delegate: self, tab: tab, activates: false).id(settingsGeneration))
    }

    // MARK: - Accessibility

    private static let axGrantedKey = "axGrantedOnce"

    private func noteAccessibilityGranted() {
        if settings.axTrusted && !UserDefaults.standard.bool(forKey: Self.axGrantedKey) {
            UserDefaults.standard.set(true, forKey: Self.axGrantedKey)
        }
    }

    private func checkAccessibilityAtLaunch() {
        settings.axTrusted = AXIsProcessTrusted()
        let d = UserDefaults.standard
        if settings.axTrusted {
            d.set(true, forKey: Self.axGrantedKey)
        } else if d.bool(forKey: Self.axGrantedKey) {
            // It worked before and now it doesn't: macOS dropped the permission (usually after an update),
            // although the switch in System Settings may still look on. Explain once per loss.
            d.set(false, forKey: Self.axGrantedKey)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                self.showAccessibilityLostAlert()
            }
        } else if settings.config.onDock || settings.config.onIcons, !d.bool(forKey: "askedAccessibility") {
            // Ask once for Accessibility (snow on the Dock and desktop icons).
            d.set(true, forKey: "askedAccessibility")
            Tracker.requestAccessibility()
        }
    }

    private func showAccessibilityLostAlert() {
        guard !AXIsProcessTrusted() else { return }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = String(localized: "iSnow lost its Accessibility permission")
        alert.informativeText = String(localized: """
            macOS stopped recognizing iSnow, which usually happens after an update. The switch in System Settings \
            may still look on, but snow on the Dock and desktop icons no longer works.

            To fix it, open Privacy & Security › Accessibility, select iSnow, remove it with the − button, \
            then add it again with + and switch it on.
            """)
        alert.addButton(withTitle: String(localized: "Open System Settings"))
        alert.addButton(withTitle: String(localized: "Not Now"))
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
