// The logo: a "J" next to a switch. Used by the menu bar (main.swift) and the app icon (scripts/make-icon).
import AppKit

/// The logo on a 23x16 grid, in `color`.
func drawLogo(color: NSColor = .black) {
    let base = NSFont.systemFont(ofSize: 13, weight: .black)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 13) } ?? base,
        .foregroundColor: color]
    let ts = ("J" as NSString).size(withAttributes: attrs)
    ("J" as NSString).draw(at: NSPoint(x: 1, y: (16 - ts.height) / 2), withAttributes: attrs)
    color.set()
    let pill = NSBezierPath(roundedRect: NSRect(x: 10, y: 4.5, width: 12, height: 7), xRadius: 3.5, yRadius: 3.5)
    pill.lineWidth = 1.6
    pill.stroke()
    NSBezierPath(ovalIn: NSRect(x: 16.5, y: 6, width: 4, height: 4)).fill()
}
