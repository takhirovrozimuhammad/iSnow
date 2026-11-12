import AppKit

/// Original edition artwork: snow pearls, an orbital ribbon and a northern star.
enum ISnowBrand {
    static func image(size: CGFloat, template: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            draw(in: rect, template: template)
            return true
        }
        image.isTemplate = template
        return image
    }

    static func draw(in rect: CGRect, template: Bool = false) {
        let s = rect.width
        NSGraphicsContext.saveGraphicsState()
        let frame = rect.insetBy(dx: template ? 0 : s * 0.065, dy: template ? 0 : s * 0.065)
        if !template {
            let tile = NSBezierPath(roundedRect: frame, xRadius: s * 0.22, yRadius: s * 0.22)
            NSGradient(colors: [NSColor(red: 0.31, green: 0.32, blue: 0.73, alpha: 1),
                                NSColor(red: 0.12, green: 0.16, blue: 0.39, alpha: 1),
                                NSColor(red: 0.04, green: 0.07, blue: 0.19, alpha: 1)])!
                .draw(in: tile, angle: -75)
            NSColor(white: 1, alpha: 0.15).setStroke()
            tile.lineWidth = s * 0.008; tile.stroke()
        }
        let ink = template ? NSColor.black : NSColor.white
        for (cx, cy, r) in [(0.47, 0.31, 0.155), (0.47, 0.52, 0.117), (0.47, 0.685, 0.084)] {
            let ball = NSBezierPath(ovalIn: CGRect(x: rect.minX + s * (cx - r), y: rect.minY + s * (cy - r),
                                                  width: s * r * 2, height: s * r * 2))
            if template { ink.setFill(); ball.fill() } else {
                NSGradient(colors: [.white, NSColor(red: 0.68, green: 0.78, blue: 1, alpha: 1)])!
                    .draw(in: ball, angle: -55)
            }
        }
        if !template {
            let orbit = NSBezierPath()
            orbit.move(to: CGPoint(x: s * 0.19, y: s * 0.40))
            orbit.curve(to: CGPoint(x: s * 0.80, y: s * 0.50), controlPoint1: CGPoint(x: s * 0.40, y: s * 0.22),
                        controlPoint2: CGPoint(x: s * 0.77, y: s * 0.28))
            NSColor(red: 0.64, green: 0.62, blue: 1, alpha: 1).setStroke()
            orbit.lineWidth = s * 0.038; orbit.lineCapStyle = .round; orbit.stroke()
        }
        let star = NSBezierPath()
        let cx = rect.minX + s * 0.75, cy = rect.minY + s * 0.73, r = s * 0.08
        star.move(to: CGPoint(x: cx, y: cy + r))
        for (x, y) in [(0.22, 0.22), (1.0, 0.0), (0.22, -0.22), (0.0, -1.0),
                       (-0.22, -0.22), (-1.0, 0.0), (-0.22, 0.22)] {
            star.line(to: CGPoint(x: cx + r * x, y: cy + r * y))
        }
        star.close(); ink.setFill(); star.fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}
