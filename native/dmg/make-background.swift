// Draws dmg/background.tiff: Burrow's paper, a title, and an arrow from the app
// to Applications, at 1x and 2x (660×420 points). Colors are the Paper file's tokens.
//   swift native/dmg/make-background.swift native/dmg/background.tiff
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "background.tiff"
func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

func render(scale: CGFloat) -> NSBitmapImageRep {
    let size = NSSize(width: 660, height: 420)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    color(0xF0F0E9).setFill()
    NSRect(origin: .zero, size: size).fill()
    // y is from the bottom here; Finder's icon centers are at y = 196 from the top.
    let title = NSAttributedString(string: "Drag Burrow into Applications", attributes: [
        .font: NSFont(name: "Helvetica Neue Bold", size: 22) ?? .boldSystemFont(ofSize: 22), .foregroundColor: color(0x151716), .kern: -0.4])
    title.draw(at: NSPoint(x: (size.width - title.size().width) / 2, y: 420 - 62))
    let sub = NSAttributedString(string: "Then open it and turn on Full Disk Access when it asks.", attributes: [
        .font: NSFont(name: "Helvetica Neue", size: 13) ?? .systemFont(ofSize: 13), .foregroundColor: color(0x595D5A)])
    sub.draw(at: NSPoint(x: (size.width - sub.size().width) / 2, y: 420 - 86))
    // Arrow between the icons.
    let y = 420 - 196.0
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 262, y: y)); path.line(to: NSPoint(x: 392, y: y))
    path.move(to: NSPoint(x: 378, y: y + 12)); path.line(to: NSPoint(x: 394, y: y)); path.line(to: NSPoint(x: 378, y: y - 12))
    path.lineWidth = 3; path.lineCapStyle = .square; path.lineJoinStyle = .miter
    color(0x31564E).setStroke(); path.stroke()
    // The cyan square from the Tunnel mark.
    color(0x00D1F1).setFill()
    NSRect(x: 402, y: y + 14, width: 7, height: 7).fill()
    // Rule and credit at the foot.
    color(0xBAC3BC).setFill()
    NSRect(x: 40, y: 54, width: 580, height: 1).fill()
    let foot = NSAttributedString(string: "Burrow by Jamak · cleaning by Mole (tw93, GPL-3.0), installed separately with Homebrew", attributes: [
        .font: NSFont(name: "Helvetica Neue", size: 11) ?? .systemFont(ofSize: 11), .foregroundColor: color(0x6B706C)])
    foot.draw(at: NSPoint(x: (size.width - foot.size().width) / 2, y: 30))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// 1x and 2x PNGs, joined the way Daybook's README does it (tiffutil -cathidpicheck).
let tmp = FileManager.default.temporaryDirectory
let one = tmp.appendingPathComponent("burrow-bg.png"), two = tmp.appendingPathComponent("burrow-bg@2x.png")
try! render(scale: 1).representation(using: .png, properties: [:])!.write(to: one)
try! render(scale: 2).representation(using: .png, properties: [:])!.write(to: two)
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/tiffutil")
p.arguments = ["-cathidpicheck", one.path, two.path, "-out", out]
try! p.run(); p.waitUntilExit()
print("Wrote \(out)")
