// Generates Resources/Mundane.icns. Run: swift Tools/make-icon.swift
//
// Drawn in code rather than exported from a design tool so it needs no Xcode and
// no asset catalog (actool is Xcode-only). Two pieces of artwork: the detailed
// card-and-seal for 64px and up, and a simplified silhouette for 16 and 32, which
// an .icns can carry separately.
import AppKit

// Compiled together with Sources/Mundane/Palette.swift (see ./make.sh icon), so
// these are the app's own values rather than a second copy that can drift.
let shu   = nsColor(Ink.shu.light)
let grey  = nsColor(Ink.iconDots.light)
let edge  = nsColor(Ink.edge.light)
let paper = nsColor(Ink.paper.light)

/// Big Sur icon grid: the body is 824 of a 1024 canvas, radius 185.4.
let bodyFraction: CGFloat = 824.0 / 1024.0
let radiusFraction: CGFloat = 185.4 / 824.0

func rounded(_ r: NSRect, _ rad: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: r, xRadius: rad, yRadius: rad)
}

/// Draws using mockup coordinates: 0-100, y measured from the top of the body.
struct Pen {
    let body: NSRect
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        let s = body.width / 100
        return NSRect(x: body.minX + x * s,
                      y: body.minY + body.height - (y + h) * s,
                      width: w * s, height: h * s)
    }
    var scale: CGFloat { body.width / 100 }
}

func draw(size: CGFloat, detailed: Bool) -> NSBitmapImageRep {
    let px = Int(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high

    let inset = size * (1 - bodyFraction) / 2
    let body = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let p = Pen(body: body)

    paper.setFill()
    rounded(body, body.width * radiusFraction).fill()

    if detailed {
        // inner card — white on white, held together by a hairline
        let card = p.rect(11, 18, 66, 64)
        paper.setFill(); rounded(card, 10 * p.scale).fill()
        edge.setStroke()
        let stroke = rounded(card, 10 * p.scale)
        stroke.lineWidth = max(1, 2 * p.scale); stroke.stroke()

        for row in 0..<3 {
            for col in 0..<4 {
                let today = (row == 1 && col == 2)
                (today ? shu : grey).setFill()
                rounded(p.rect(19 + CGFloat(col) * 14.5, 29 + CGFloat(row) * 15.5, 10.5, 10.5),
                        3.2 * p.scale).fill()
            }
        }

        // seal straddling the card's right edge, as it does in the app
        let seal = p.rect(62, 33, 30, 30)
        paper.setFill(); rounded(seal, 8 * p.scale).fill()
        shu.setStroke()
        let ring = rounded(seal, 8 * p.scale)
        ring.lineWidth = 4.5 * p.scale; ring.stroke()

        let fontSize = 17 * p.scale
        let font = NSFont(name: "HiraMaruProN-W4", size: fontSize)
            ?? NSFont.systemFont(ofSize: fontSize)
        let glyph = NSAttributedString(string: "暦", attributes: [
            .font: font, .foregroundColor: shu])
        let gs = glyph.size()
        glyph.draw(at: NSPoint(x: seal.midX - gs.width / 2, y: seal.midY - gs.height / 2))
    } else {
        // small sizes: silhouette only, nothing to read
        for row in 0..<3 {
            grey.setFill()
            rounded(p.rect(14, 25 + CGFloat(row) * 19, 44, 13), 4.5 * p.scale).fill()
        }
        shu.setFill()
        rounded(p.rect(14, 44, 13, 13), 4.5 * p.scale).fill()
        rounded(p.rect(60, 34, 30, 30), 8.5 * p.scale).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// name -> (pixels, detailed)
let slots: [(String, CGFloat, Bool)] = [
    ("icon_16x16",      16,   false),
    ("icon_16x16@2x",   32,   false),
    ("icon_32x32",      32,   false),
    ("icon_32x32@2x",   64,   true),
    ("icon_128x128",    128,  true),
    ("icon_128x128@2x", 256,  true),
    ("icon_256x256",    256,  true),
    ("icon_256x256@2x", 512,  true),
    ("icon_512x512",    512,  true),
    ("icon_512x512@2x", 1024, true),
]

let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)
let iconset = root.appendingPathComponent("build-icon/Mundane.iconset")
try? fm.removeItem(at: iconset.deletingLastPathComponent())
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

for (name, px, detailed) in slots {
    let rep = draw(size: px, detailed: detailed)
    let data = rep.representation(using: .png, properties: [:])!
    try data.write(to: iconset.appendingPathComponent("\(name).png"))
    print(String(format: "  %-18@ %4dpx  %@", name as NSString, Int(px),
                 (detailed ? "detailed" : "simplified") as NSString))
}

let out = root.appendingPathComponent("Resources/Mundane.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try task.run(); task.waitUntilExit()
try? fm.removeItem(at: iconset.deletingLastPathComponent())
// preview sheet, so the icon can be eyeballed without installing it
let sheetW = 620, sheetH = 210
let sheet = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: sheetW, pixelsHigh: sheetH,
                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                             isPlanar: false, colorSpaceName: .deviceRGB,
                             bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
NSColor(srgbRed: 0.93, green: 0.93, blue: 0.92, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: sheetW, height: sheetH).fill()
NSColor(srgbRed: 0.16, green: 0.16, blue: 0.15, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: sheetW, height: sheetH / 2).fill()
for half in 0..<2 {
    var x: CGFloat = 20
    let yBase = CGFloat(half) * CGFloat(sheetH) / 2
    for (px, detailed) in [(CGFloat(128), true), (64, true), (32, false), (16, false)] {
        let rep = draw(size: px, detailed: detailed)
        let img = NSImage(size: NSSize(width: px, height: px))
        img.addRepresentation(rep)
        img.draw(at: NSPoint(x: x, y: yBase + (CGFloat(sheetH) / 2 - px) / 2),
                 from: .zero, operation: .sourceOver, fraction: 1)
        x += px + 22
    }
}
NSGraphicsContext.restoreGraphicsState()
try sheet.representation(using: .png, properties: [:])!
    .write(to: root.appendingPathComponent("build-icon-preview.png"))

print(task.terminationStatus == 0
      ? "wrote Resources/Mundane.icns"
      : "iconutil failed (\(task.terminationStatus))")
