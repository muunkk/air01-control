// Builds the README images from the app's own offscreen snapshots:
//   docs/screenshot.png  light and dark windows side by side, with macOS window chrome
//   docs/icon.png        the app icon at 256 pt (512 px)
// Run tools/make_readme_images.sh rather than calling this directly.
//   swift tools/make_readme_images.swift <snapshot dir> <AppIcon.icns> <docs dir>
import AppKit

let args = CommandLine.arguments
guard args.count == 4 else {
    print("usage: make_readme_images.swift <snapshot dir> <AppIcon.icns> <docs dir>")
    exit(1)
}
let snapDir = URL(fileURLWithPath: args[1])
let icnsURL = URL(fileURLWithPath: args[2])
let docs = URL(fileURLWithPath: args[3])
let scale: CGFloat = 2

func load(_ name: String) -> NSBitmapImageRep {
    let url = snapDir.appendingPathComponent(name)
    guard let data = try? Data(contentsOf: url), let rep = NSBitmapImageRep(data: data) else {
        print("missing \(url.path)"); exit(1)
    }
    return rep
}

func canvas(_ size: NSSize, _ draw: () -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                               pixelsHigh: Int(size.height * scale), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ rep: NSBitmapImageRep, _ name: String) {
    let url = docs.appendingPathComponent(name)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print("wrote \(url.path)")
}

let titleBar: CGFloat = 28
let radius: CGFloat = 10

/// Draws one app window (title bar, traffic lights, content) with its shadow.
func drawWindow(_ shot: NSBitmapImageRep, at origin: NSPoint, dark: Bool) {
    let content = shot.size
    let frame = NSRect(x: origin.x, y: origin.y, width: content.width, height: content.height + titleBar)
    let shape = NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)

    // Shadow, drawn once under the window body.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.55 : 0.30)
    shadow.shadowBlurRadius = 36
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.set()
    // The title bar matches the content's top edge, as in a unified macOS window.
    (shot.colorAt(x: 4, y: 4) ?? .windowBackgroundColor).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    shot.draw(in: NSRect(x: frame.minX, y: frame.minY, width: content.width, height: content.height))

    // Traffic lights.
    let lights: [NSColor] = [
        NSColor(red: 1.00, green: 0.37, blue: 0.34, alpha: 1),
        NSColor(red: 1.00, green: 0.74, blue: 0.18, alpha: 1),
        NSColor(red: 0.16, green: 0.78, blue: 0.25, alpha: 1),
    ]
    for (i, c) in lights.enumerated() {
        let r = NSRect(x: frame.minX + 14 + CGFloat(i) * 20, y: frame.maxY - titleBar / 2 - 6, width: 12, height: 12)
        c.setFill()
        NSBezierPath(ovalIn: r).fill()
        NSColor.black.withAlphaComponent(0.12).setStroke()
        let ring = NSBezierPath(ovalIn: r.insetBy(dx: 0.25, dy: 0.25))
        ring.lineWidth = 0.5
        ring.stroke()
    }

    // Title.
    let title = NSAttributedString(string: "Air01 Control", attributes: [
        .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
        .foregroundColor: dark ? NSColor(white: 0.88, alpha: 1) : NSColor(white: 0.18, alpha: 1),
    ])
    let ts = title.size()
    title.draw(at: NSPoint(x: frame.midX - ts.width / 2, y: frame.maxY - titleBar / 2 - ts.height / 2))
    NSGraphicsContext.restoreGraphicsState()

    // Hairline border.
    (dark ? NSColor.white.withAlphaComponent(0.16) : NSColor.black.withAlphaComponent(0.14)).setStroke()
    let border = NSBezierPath(roundedRect: frame.insetBy(dx: 0.25, dy: 0.25), xRadius: radius, yRadius: radius)
    border.lineWidth = 0.5
    border.stroke()
}

// MARK: Screenshot

let light = load("readme-light.png")
let dark = load("readme-dark.png")
let win = NSSize(width: light.size.width, height: light.size.height + titleBar)
let margin: CGFloat = 48
let overlap: CGFloat = 34
let drop: CGFloat = 48
let size = NSSize(width: margin * 2 + win.width * 2 - overlap, height: margin * 2 + win.height + drop)
let shot = canvas(size) {
    drawWindow(light, at: NSPoint(x: margin, y: margin + drop), dark: false)
    drawWindow(dark, at: NSPoint(x: margin + win.width - overlap, y: margin), dark: true)
}
write(shot, "screenshot.png")

// MARK: Icon

guard let icon = NSImage(contentsOf: icnsURL) else { print("missing \(icnsURL.path)"); exit(1) }
let iconRep = canvas(NSSize(width: 256, height: 256)) {
    icon.draw(in: NSRect(x: 0, y: 0, width: 256, height: 256))
}
write(iconRep, "icon.png")
