// Generates Resources/AppIcon.icns. Usage: swift scripts/make_icon.swift
import AppKit

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size) / 1024.0
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: s, y: s)

    // Icon squircle (macOS standard: 824pt within 1024pt)
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    // Drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28,
                  color: NSColor.black.withAlphaComponent(0.35).cgColor)
    NSColor.black.setFill()
    bodyPath.fill()
    ctx.restoreGState()

    // Background gradient
    ctx.saveGState()
    bodyPath.addClip()
    NSGradient(colors: [
        NSColor(red: 0.20, green: 0.24, blue: 0.48, alpha: 1),
        NSColor(red: 0.05, green: 0.07, blue: 0.16, alpha: 1)
    ])!.draw(in: body, angle: -60)
    ctx.restoreGState()

    // Terminal window body
    let win = NSRect(x: 200, y: 260, width: 624, height: 504)
    let winPath = NSBezierPath(roundedRect: win, xRadius: 52, yRadius: 52)
    NSColor(red: 0.04, green: 0.05, blue: 0.10, alpha: 0.92).setFill()
    winPath.fill()
    NSColor.white.withAlphaComponent(0.14).setStroke()
    winPath.lineWidth = 4
    winPath.stroke()

    // Titlebar dots (traffic lights)
    let dotColors = [
        NSColor(red: 1.00, green: 0.37, blue: 0.34, alpha: 1),
        NSColor(red: 1.00, green: 0.74, blue: 0.18, alpha: 1),
        NSColor(red: 0.16, green: 0.79, blue: 0.25, alpha: 1)
    ]
    for (i, c) in dotColors.enumerated() {
        c.setFill()
        NSBezierPath(ovalIn: NSRect(x: 244 + CGFloat(i) * 56, y: 700, width: 34, height: 34)).fill()
    }

    // Terminal prompt ">_"
    let green = NSColor(red: 0.35, green: 0.95, blue: 0.62, alpha: 1)
    let font = NSFont.monospacedSystemFont(ofSize: 300, weight: .heavy)
    let text = NSAttributedString(string: ">_", attributes: [
        .font: font, .foregroundColor: green
    ])
    let ts = text.size()
    text.draw(at: NSPoint(x: win.midX - ts.width / 2, y: 330 - (ts.height - 300) / 2 + 25))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)

let variants: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]
for (name, px) in variants {
    try! render(size: px).write(to: iconset.appendingPathComponent("\(name).png"))
}

let resources = root.appendingPathComponent("Resources")
try! fm.createDirectory(at: resources, withIntermediateDirectories: true)
let out = resources.appendingPathComponent("AppIcon.icns")

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try! p.run()
p.waitUntilExit()
print(p.terminationStatus == 0 ? "✅ \(out.path)" : "❌ iconutil failed")

