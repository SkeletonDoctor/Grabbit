// Renders the app icon to an .iconset folder. Usage: swift make_icon.swift <out.iconset>
//
// The mark is a download arrow whose stem is a pair of rabbit ears, sitting on a tray line.
// The same geometry is drawn in the app by `GrabbitMark` (Sources/Grabbit/Styles.swift).
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ size: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = size * 0.1
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let plate = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGradient(colors: [NSColor(red: 1.0, green: 0.45, blue: 0.33, alpha: 1),
                        NSColor(red: 0.95, green: 0.22, blue: 0.50, alpha: 1),
                        NSColor(red: 0.52, green: 0.26, blue: 0.95, alpha: 1)])!
        .draw(in: plate, angle: -55)
    // Soft highlight
    NSGraphicsContext.current?.saveGraphicsState()
    plate.addClip()
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.26), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2), angle: -90)
    NSGraphicsContext.current?.restoreGraphicsState()

    // The mark, laid out in a unit square (origin top-left) and mapped into the plate.
    let box = rect.insetBy(dx: rect.width * 0.12, dy: rect.width * 0.12)
    func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: box.minX + x * box.width, y: box.maxY - y * box.height) }
    let u = box.width

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowBlurRadius = size * 0.025
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
    shadow.set()
    // One transparency layer, so the whole mark casts a single shadow instead of each piece shading the next.
    let cg = NSGraphicsContext.current!.cgContext
    cg.beginTransparencyLayer(auxiliaryInfo: nil)
    NSColor.white.setFill()
    NSColor.white.setStroke()

    for (cx, angle) in [(CGFloat(0.40), CGFloat(7)), (0.60, -7)] {
        let w = 0.13 * u, h = 0.44 * u
        let ear = NSBezierPath(roundedRect: NSRect(x: -w / 2, y: -h / 2, width: w, height: h), xRadius: w / 2, yRadius: w / 2)
        var t = AffineTransform(translationByX: pt(cx, 0.31).x, byY: pt(cx, 0.31).y)
        t.rotate(byDegrees: angle)
        ear.transform(using: t)
        ear.fill()
    }
    let head = NSBezierPath()
    head.move(to: pt(0.25, 0.50)); head.line(to: pt(0.75, 0.50)); head.line(to: pt(0.5, 0.75)); head.close()
    head.lineJoinStyle = .round
    head.lineWidth = 0.09 * u
    head.fill(); head.stroke()
    let tray = NSBezierPath(roundedRect: NSRect(x: pt(0.26, 0).x, y: pt(0, 0.955).y, width: 0.48 * u, height: 0.075 * u),
                            xRadius: 0.0375 * u, yRadius: 0.0375 * u)
    tray.fill()
    cg.endTransparencyLayer()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try render(CGFloat(base * scale)).write(to: out.appendingPathComponent(name))
    }
}
