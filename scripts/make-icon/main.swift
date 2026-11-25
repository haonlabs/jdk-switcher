// Renders the app icon into an .iconset folder. build.sh compiles it with Sources/Logo.swift.
import AppKit

// Drawn on Apple's 1024pt icon grid (824pt body, ~185pt corner radius).
func drawIcon() {
    let body = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    NSGradient(starting: NSColor(srgbRed: 0.27, green: 0.42, blue: 0.95, alpha: 1),
               ending: NSColor(srgbRed: 0.45, green: 0.26, blue: 0.85, alpha: 1))!.draw(in: body, angle: -90)

    // The 23x16 logo from Sources/Logo.swift, scaled to fill ~70% of the body width.
    let scale: CGFloat = 25
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.saveGState()
    ctx.translateBy(x: (1024 - 23 * scale) / 2, y: (1024 - 16 * scale) / 2)
    ctx.scaleBy(x: scale, y: scale)
    drawLogo(color: .white)
    ctx.restoreGState()
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current!.cgContext.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
        drawIcon()
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
    }
}
