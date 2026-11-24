// Renders the app icon into an .iconset folder: swift scripts/make-icon.swift <out.iconset>
import AppKit

// Drawn on Apple's 1024pt icon grid (824pt body, ~185pt corner radius).
func drawIcon() {
    let body = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    NSGradient(starting: NSColor(srgbRed: 0.27, green: 0.42, blue: 0.95, alpha: 1),
               ending: NSColor(srgbRed: 0.45, green: 0.26, blue: 0.85, alpha: 1))!.draw(in: body, angle: -90)

    let base = NSFont.systemFont(ofSize: 290, weight: .heavy)
    let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 290) } ?? base
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
    let ts = ("JDK" as NSString).size(withAttributes: attrs)
    let textY: CGFloat = 470
    ("JDK" as NSString).draw(at: NSPoint(x: (1024 - ts.width) / 2, y: textY), withAttributes: attrs)

    let cfg = NSImage.SymbolConfiguration(pointSize: 140, weight: .bold).applying(.init(paletteColors: [.white]))
    if let arrows = NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
        let s = arrows.size
        arrows.draw(in: NSRect(x: (1024 - s.width) / 2, y: textY + 20 - s.height, width: s.width, height: s.height))
    }
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
