// Renders the app icon: a low-profile keyboard with an RGB edge glow.
//   swift tools/make_icon.swift <out.png> [size]
import AppKit
import CoreGraphics

let args = CommandLine.arguments
let out = args.count > 1 ? args[1] : "icon.png"
let S = CGFloat(args.count > 2 ? Double(args[2]) ?? 1024 : 1024)
let u = S / 1024  // design units are on a 1024 canvas

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.scaleBy(x: u, y: u)
// Flip so y grows downward like the design notes.
ctx.translateBy(x: 0, y: 1024)
ctx.scaleBy(x: 1, y: -1)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}
func linear(_ colors: [CGColor], _ locs: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: locs)!
}
let rainbow = [rgb(0xFF3B7F), rgb(0xFF8A3D), rgb(0xFFD34E), rgb(0x4EE39A), rgb(0x38C8FF), rgb(0x7A5CFF), rgb(0xFF3B7F)]

// 1. Tile: macOS icon grid (824 pt squircle inside 1024, ~185 corner).
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.35))
ctx.addPath(rounded(tile, 186)); ctx.setFillColor(rgb(0x1B1D23)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(rounded(tile, 186)); ctx.clip()
ctx.drawLinearGradient(linear([rgb(0x353945), rgb(0x1E2027), rgb(0x121318)], [0, 0.55, 1]),
                       start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])

// 2. RGB underglow: blurred rainbow bar under the keyboard.
let body = CGRect(x: 178, y: 404, width: 668, height: 300)
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 120, color: rgb(0x7A5CFF, 1))
ctx.addPath(rounded(body.insetBy(dx: 24, dy: 24), 40))
ctx.setFillColor(rgb(0x5B4BFF, 0.7)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 100, color: rgb(0xFF3B7F, 0.8))
ctx.addPath(rounded(CGRect(x: body.minX + 16, y: body.maxY - 76, width: 220, height: 60), 30))
ctx.setFillColor(rgb(0xFF3B7F, 0.5)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 100, color: rgb(0x38C8FF, 0.8))
ctx.addPath(rounded(CGRect(x: body.maxX - 236, y: body.maxY - 76, width: 220, height: 60), 30))
ctx.setFillColor(rgb(0x38C8FF, 0.5)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(rounded(body.insetBy(dx: 6, dy: 6), 36)); ctx.clip()
ctx.setAlpha(0.7)
ctx.drawLinearGradient(linear(rainbow), start: CGPoint(x: body.minX, y: 0), end: CGPoint(x: body.maxX, y: 0), options: [])
ctx.restoreGState()
// soften it
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 70, color: rgb(0x38C8FF, 0.6))
ctx.addPath(rounded(body.insetBy(dx: 80, dy: 80), 40))
ctx.setFillColor(rgb(0x38C8FF, 0.25)); ctx.fillPath()
ctx.restoreGState()

// 3. Keyboard body: brushed-aluminium slab with a rainbow side-light edge.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 18), blur: 30, color: rgb(0x000000, 0.55))
ctx.addPath(rounded(body, 40)); ctx.setFillColor(rgb(0x2A2D35)); ctx.fillPath()
ctx.restoreGState()

// rainbow edge (side light)
ctx.saveGState()
ctx.addPath(rounded(body, 40)); ctx.addPath(rounded(body.insetBy(dx: 9, dy: 9), 32))
ctx.clip(using: .evenOdd)
ctx.drawLinearGradient(linear(rainbow), start: CGPoint(x: body.minX, y: 0), end: CGPoint(x: body.maxX, y: 0), options: [])
ctx.restoreGState()

// top plate: the backlight itself, glowing between the keys
let plate = body.insetBy(dx: 9, dy: 9)
ctx.saveGState()
ctx.addPath(rounded(plate, 32)); ctx.clip()
ctx.setFillColor(rgb(0x101116)); ctx.fill(plate)
ctx.setAlpha(0.95)
ctx.drawLinearGradient(linear(rainbow), start: CGPoint(x: plate.minX, y: plate.maxY), end: CGPoint(x: plate.maxX, y: plate.minY), options: [])
ctx.setAlpha(1)
// darken toward the edges so the glow reads as light, not paint
ctx.drawRadialGradient(linear([rgb(0x000000, 0), rgb(0x000000, 0.45)]),
                       startCenter: CGPoint(x: plate.midX, y: plate.midY), startRadius: 60,
                       endCenter: CGPoint(x: plate.midX, y: plate.midY), endRadius: 420, options: [.drawsAfterEndLocation])
ctx.restoreGState()

// 4. Keys: four staggered rows plus a space row, softly lit from below.
let keyH: CGFloat = 46, gap: CGFloat = 10
let left = plate.minX + 24, right = plate.maxX - 24
func keyRow(y: CGFloat, widths: [CGFloat]) {
    let total = widths.reduce(0, +) + gap * CGFloat(widths.count - 1)
    let scale = (right - left) / total
    var x = left
    for w in widths {
        let r = CGRect(x: x, y: y, width: w * scale, height: keyH)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 4), blur: 5, color: rgb(0x000000, 0.6))
        ctx.addPath(rounded(r, 10)); ctx.setFillColor(rgb(0x1C1E24)); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(rounded(r.insetBy(dx: 2, dy: 2), 8)); ctx.clip()
        ctx.drawLinearGradient(linear([rgb(0x444955), rgb(0x2A2D35), rgb(0x23262D)], [0, 0.35, 1]),
                               start: CGPoint(x: 0, y: r.minY), end: CGPoint(x: 0, y: r.maxY), options: [])
        ctx.restoreGState()
        x += w * scale + gap * scale
    }
}
let top = plate.minY + 24
keyRow(y: top, widths: Array(repeating: 46, count: 12))
keyRow(y: top + (keyH + gap), widths: [70] + Array(repeating: 46, count: 10) + [70])
keyRow(y: top + 2 * (keyH + gap), widths: [86] + Array(repeating: 46, count: 9) + [102])
keyRow(y: top + 3 * (keyH + gap), widths: [46, 46, 56, 260, 56, 46, 46, 46])


// 5. Gloss on the tile.
ctx.saveGState()
ctx.setBlendMode(.screen)
ctx.drawLinearGradient(linear([rgb(0xFFFFFF, 0.10), rgb(0xFFFFFF, 0)]),
                       start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 420), options: [])
ctx.restoreGState()
ctx.restoreGState()  // tile clip

// tile hairline
ctx.addPath(rounded(tile.insetBy(dx: 1, dy: 1), 185)); ctx.setStrokeColor(rgb(0xFFFFFF, 0.08)); ctx.setLineWidth(2); ctx.strokePath()

let img = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: img)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out) (\(Int(S))px)")
