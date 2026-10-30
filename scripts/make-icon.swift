// Draws the app icon: a battery that stops at a marked 80% line.
// Writes Resources/Assets.xcassets/AppIcon.appiconset and site/icon.png. Run: swift scripts/make-icon.swift
import AppKit

func hex(_ v: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
}
let navyTop = hex(0x22344F), navyBottom = hex(0x0A111E)
let mintLight = hex(0x5BF0B0), mintDark = hex(0x19C48A), limitMint = hex(0x7DF7C6)

/// Drawn in 1024-point units on the macOS icon grid (824-point plate). Small sizes get heavier strokes.
func drawIcon(pixels: Int) {
    let heavy: CGFloat = pixels <= 32 ? 1.7 : pixels <= 64 ? 1.25 : 1
    let plate = NSRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = NSBezierPath(roundedRect: plate, xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.3); shadow.shadowOffset = NSSize(width: 0, height: -12); shadow.shadowBlurRadius = 28
    shadow.set(); navyBottom.setFill(); squircle.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: navyTop, ending: navyBottom)!.draw(in: squircle, angle: -90)
    NSGraphicsContext.saveGraphicsState(); squircle.addClip()
    NSGradient(starting: NSColor.white.withAlphaComponent(0.14), ending: NSColor.white.withAlphaComponent(0))!.draw(in: NSRect(x: 100, y: 560, width: 824, height: 364), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    let stroke = 36 * heavy
    let body = NSRect(x: 206, y: 340, width: 572, height: 344)
    NSColor.white.setFill(); NSBezierPath(roundedRect: NSRect(x: 792, y: 452, width: 46, height: 120), xRadius: 18, yRadius: 18).fill()
    let outline = NSBezierPath(roundedRect: body, xRadius: 88, yRadius: 88); outline.lineWidth = stroke; NSColor.white.setStroke(); outline.stroke()
    let inner = body.insetBy(dx: stroke / 2 + 28, dy: stroke / 2 + 28)
    let fill = NSRect(x: inner.minX, y: inner.minY, width: inner.width * 0.8, height: inner.height)
    NSGradient(starting: mintLight, ending: mintDark)!.draw(in: NSBezierPath(roundedRect: fill, xRadius: 40, yRadius: 40), angle: 0)

    let x = fill.maxX + 2
    let line = NSBezierPath(); line.move(to: NSPoint(x: x, y: 272)); line.line(to: NSPoint(x: x, y: 752))
    line.lineWidth = 18 * heavy; line.lineCapStyle = .round; limitMint.setStroke(); line.stroke()
    let arrow = 34 * min(heavy, 1.3)
    for (tip, dir) in [(CGFloat(272), CGFloat(1)), (CGFloat(752), CGFloat(-1))] {
        let t = NSBezierPath()
        t.move(to: NSPoint(x: x - arrow, y: tip - dir * (arrow + 8))); t.line(to: NSPoint(x: x + arrow, y: tip - dir * (arrow + 8))); t.line(to: NSPoint(x: x, y: tip + dir * 12)); t.close()
        limitMint.setFill(); t.fill()
    }
}

func png(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!; NSGraphicsContext.current = ctx
    ctx.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    drawIcon(pixels: pixels)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let set = root.appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try png(pixels: points * scale).write(to: set.appendingPathComponent(name))
        images.append(["size": "\(points)x\(points)", "idiom": "mac", "filename": name, "scale": "\(scale)x"])
    }
}
let info = ["version": 1, "author": "xcode"] as [String: Any]
try JSONSerialization.data(withJSONObject: ["images": images, "info": info], options: [.prettyPrinted, .sortedKeys]).write(to: set.appendingPathComponent("Contents.json"))
try JSONSerialization.data(withJSONObject: ["info": info], options: [.prettyPrinted, .sortedKeys]).write(to: set.deletingLastPathComponent().appendingPathComponent("Contents.json"))
try png(pixels: 256).write(to: root.appendingPathComponent("site/icon.png"))
print(set.path)
