// Draws docs/images/social-preview.png — the 1280×640 card X, Slack, Discord and the
// landing page's og:image render. Runs on the Command Line Tools alone:
//
//     swift scripts/social-card.swift
//
// The window shot on the right is docs/images/social-window.png, captured with
// AppTests/WindowCaptureTests.swift (that needs Xcode). Everything on the left is drawn
// here, in the system font, so the card can be redrawn without a designer.
//
// The card carries no number on purpose. It said "3.15 MB" from 0.16.4 to 0.21.0
// because a PNG is the one public surface claims.py cannot read, and a size that moves
// every release is a claim that goes stale on a schedule. What is drawn here is true
// for as long as the licence and the store listing are.
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let images = root.appendingPathComponent("docs/images")
let out = images.appendingPathComponent("social-preview.png")

let size = NSSize(width: 1280, height: 640)
let background = NSColor(srgbRed: 0x0F/255, green: 0x11/255, blue: 0x17/255, alpha: 1)
let left: CGFloat = 74

guard let icon = NSImage(contentsOf: images.appendingPathComponent("icon.png")),
      let window = NSImage(contentsOf: images.appendingPathComponent("social-window.png")) else {
    FileHandle.standardError.write("missing icon.png or social-window.png in \(images.path)\n".data(using: .utf8)!)
    exit(1)
}

// A flipped context: y runs down from the top, which is how the layout was measured.
let card = NSImage(size: size, flipped: true) { rect in
    background.setFill()
    rect.fill()

    // The window shot is cut from the same background colour, so it sits over it
    // seamlessly. It is placed by its top-left, bled off the right edge.
    window.draw(in: NSRect(x: 500, y: 40, width: window.size.width, height: window.size.height),
                from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)

    // The icon's rounded square fills 82% of its canvas; 92pt puts the square at 76pt.
    icon.draw(in: NSRect(x: left, y: 76, width: 92, height: 92),
              from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)

    func text(_ string: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, baseline: CGFloat) {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        let attributed = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color])
        attributed.draw(at: NSPoint(x: left, y: baseline - font.ascender))
    }
    text("ItsPaint", size: 58.5, weight: .semibold, color: .white, baseline: 257)
    let body = NSColor(srgbRed: 0xEA/255, green: 0xEA/255, blue: 0xE9/255, alpha: 1)
    text("Mark up a screenshot", size: 28, weight: .regular, color: body, baseline: 334)
    text("and drag it out.", size: 28, weight: .regular, color: body, baseline: 374)
    let green = NSColor(srgbRed: 0x77/255, green: 0xF3/255, blue: 0x96/255, alpha: 1)
    text("Numbered steps · pixelate · spotlight · clone", size: 16.5, weight: .semibold, color: green, baseline: 460)
    let grey = NSColor(srgbRed: 0xA5/255, green: 0xA5/255, blue: 0xA5/255, alpha: 1)
    text("Free on the Mac App Store · MIT", size: 16.5, weight: .regular, color: grey, baseline: 490)
    return true
}

// Rasterise at exactly 1280×640 in sRGB end to end. Drawing into a device-RGB bitmap
// converts every colour through the display profile, and the file comes out lighter.
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let cg = CGContext(data: nil, width: 1280, height: 640, bitsPerComponent: 8, bytesPerRow: 0,
                   space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: false)
card.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
let rep = NSBitmapImageRep(cgImage: cg.makeImage()!)

let png = rep.representation(using: .png, properties: [:])!
try png.write(to: out)
print("wrote \(out.path) \(rep.pixelsWide)x\(rep.pixelsHigh)")
