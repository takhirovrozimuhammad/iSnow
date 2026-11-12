import AppKit

@main
struct IconGenerator {
    static func main() throws {
        let out = CommandLine.arguments[1]
        let set = out + "/AppIcon.iconset"
        try FileManager.default.createDirectory(atPath: set, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let px = base * scale
                let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                    bytesPerRow: 0, bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                ISnowBrand.draw(in: CGRect(x: 0, y: 0, width: CGFloat(px), height: CGFloat(px)))
                NSGraphicsContext.restoreGraphicsState()
                let suffix = scale == 2 ? "@2x" : ""
                let path = "\(set)/icon_\(base)x\(base)\(suffix).png"
                try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
                if px == 1024 {
                    try rep.representation(using: .png, properties: [:])!.write(to:
                        URL(fileURLWithPath: "\(out)/iSnow-icon.png"))
                }
            }
        }
    }
}
