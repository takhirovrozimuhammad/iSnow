import AppKit
import SwiftUI

/// Actual SwiftUI settings rendered in native windows, for build review without screen permissions.
@MainActor
enum StudioPreview {
    static func run(directory: String, delegate: AppDelegate) {
        do { try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true) }
        catch { print(error); exit(1) }
        let names = ["snowfall", "drifts", "workshop", "christmas", "work-energy"]
        var pending = names.count
        for (tab, name) in names.enumerated() {
            let settings = Settings(preview: SimConfig())
            let host = NSHostingView(rootView: SettingsView(settings: settings, delegate: delegate, tab: tab, activates: false))
            host.frame = CGRect(x: 0, y: 0, width: 900, height: 760)
            host.appearance = NSAppearance(named: .darkAqua)
            let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "iSnow · Winter Studio"
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = host
            window.setFrameOrigin(CGPoint(x: CGFloat(-4000 - tab * 1100), y: -4000))
            window.orderFrontRegardless()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                host.layoutSubtreeIfNeeded()
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(2) }
                host.cacheDisplay(in: host.bounds, to: rep)
                do {
                    guard let data = rep.representation(using: .png, properties: [:]) else { exit(3) }
                    try data.write(to: URL(fileURLWithPath: "\(directory)/iSnow-\(name).png"))
                } catch { print(error); exit(4) }
                window.orderOut(nil)
                print("Native preview: \(name)")
                pending -= 1
                if pending == 0 { exit(0) }
            }
        }
    }
}
