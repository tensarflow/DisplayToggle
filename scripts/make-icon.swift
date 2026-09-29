// Renders Resources/AppIcon.icns: two monitors on a blue squircle, the back one switched off.
// Run: swift scripts/make-icon.swift
import AppKit

func drawIcon(size: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
        let s = size / 1024
        // Squircle body on Apple's 1024 grid (824 pt body, 100 pt margin).
        let body = NSBezierPath(roundedRect: NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s),
                                xRadius: 185 * s, yRadius: 185 * s)
        NSGradient(colors: [NSColor(srgbRed: 0.42, green: 0.55, blue: 1.00, alpha: 1),
                            NSColor(srgbRed: 0.20, green: 0.24, blue: 0.78, alpha: 1)])!
            .draw(in: body, angle: -60)

        func monitor(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, lit: Bool, stand: Bool = true) {
            let bezel = NSBezierPath(roundedRect: NSRect(x: x * s, y: y * s, width: w * s, height: h * s),
                                     xRadius: 34 * s, yRadius: 34 * s)
            (lit ? NSColor(white: 0.97, alpha: 1) : NSColor(srgbRed: 0.10, green: 0.12, blue: 0.30, alpha: 1)).setFill()
            bezel.fill()
            let screen = NSRect(x: (x + 26) * s, y: (y + 26) * s, width: (w - 52) * s, height: (h - 52) * s)
            let screenPath = NSBezierPath(roundedRect: screen, xRadius: 14 * s, yRadius: 14 * s)
            if lit {
                NSGradient(colors: [NSColor(srgbRed: 0.55, green: 0.80, blue: 1.00, alpha: 1),
                                    NSColor(srgbRed: 0.30, green: 0.50, blue: 1.00, alpha: 1)])!
                    .draw(in: screenPath, angle: -90)
            } else {
                NSColor(srgbRed: 0.05, green: 0.06, blue: 0.16, alpha: 1).setFill()
                screenPath.fill()
            }
            guard stand else { return }
            // Stand
            let neckColor = lit ? NSColor(white: 0.97, alpha: 1) : NSColor(srgbRed: 0.10, green: 0.12, blue: 0.30, alpha: 1)
            neckColor.setFill()
            NSBezierPath(rect: NSRect(x: (x + w / 2 - 22) * s, y: (y - 60) * s, width: 44 * s, height: 62 * s)).fill()
            NSBezierPath(roundedRect: NSRect(x: (x + w / 2 - 95) * s, y: (y - 78) * s, width: 190 * s, height: 26 * s),
                         xRadius: 13 * s, yRadius: 13 * s).fill()
        }

        monitor(x: 430, y: 470, w: 400, h: 270, lit: false, stand: false)   // back: switched off
        monitor(x: 190, y: 330, w: 480, h: 320, lit: true)    // front: on

        // Power glyph on the dark screen: open ring + bar.
        let center = NSPoint(x: 737 * s, y: 590 * s)
        let ring = NSBezierPath()
        ring.appendArc(withCenter: center, radius: 44 * s, startAngle: 125, endAngle: 415)
        ring.lineWidth = 16 * s
        ring.lineCapStyle = .round
        NSColor(srgbRed: 0.45, green: 0.52, blue: 0.95, alpha: 1).setStroke()
        ring.stroke()
        let bar = NSBezierPath()
        bar.move(to: NSPoint(x: center.x, y: center.y + 8 * s))
        bar.line(to: NSPoint(x: center.x, y: center.y + 62 * s))
        bar.lineWidth = 16 * s
        bar.lineCapStyle = .round
        bar.stroke()
        return true
    }
}

func png(_ image: NSImage, pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try png(drawIcon(size: CGFloat(base)), pixels: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try png(drawIcon(size: CGFloat(base * 2)), pixels: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try png(drawIcon(size: 1024), pixels: 1024).write(to: root.appendingPathComponent("docs/images/icon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns and docs/images/icon.png" : "iconutil failed")
