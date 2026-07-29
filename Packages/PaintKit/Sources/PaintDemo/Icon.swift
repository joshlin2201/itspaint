import Foundation
import PaintKit

/// Generates the app icon by driving the real paint engine.
///
/// The icon is literally made with the tools it advertises — a highlighter
/// stroke, an arrow, a shape — so it cannot drift away from what the app
/// actually draws. Run with `swift run -c release paint-demo --icon <dir>`.
@MainActor
enum IconGenerator {

    /// macOS icons are a rounded "squircle" inset inside the full tile; the
    /// system draws no mask for us, so the artwork must carry its own.
    static func run(into directory: URL) throws {
        let size = 1024
        let engine = PaintEngine(canvas: Bitmap(width: size, height: size, fill: .clear))

        func colour(_ hex: String) -> PaintColour { PaintColour(hex: hex) ?? .black }

        // Rounded-square body, drawn as a filled rounded rectangle in the
        // engine's own rasteriser.
        let inset = Int(Double(size) * 0.09)
        let body = PixelRect(
            x: inset, y: inset, width: size - inset * 2, height: size - inset * 2
        )
        engine.settings.tool = .shape
        engine.settings.shapeKind = .roundedRectangle
        engine.settings.shapeStyle = .filled
        engine.settings.brushSize = 1
        engine.settings.cornerRadius = Int(Double(size) * 0.205)
        engine.colours.background = colour("FDFDFE")
        engine.beginStroke(at: PixelPoint(x: body.minX - 1, y: body.minY - 1))
        engine.endStroke(at: PixelPoint(x: body.maxX, y: body.maxY))

        // A highlighter sweep — the tool that most distinguishes this app from
        // the thing it replaces.
        engine.settings.tool = .highlighter
        engine.settings.brushSize = 132
        engine.settings.highlighterOpacity = 0.55
        engine.colours.foreground = colour("FFD400")
        engine.beginStroke(at: PixelPoint(x: 250, y: 620))
        for x in stride(from: 250, through: 780, by: 12) {
            engine.continueStroke(to: PixelPoint(x: x, y: 620))
        }
        engine.endStroke()

        // A brush ribbon across the middle.
        engine.settings.tool = .brush
        engine.settings.brushShape = .soft
        engine.settings.brushSize = 78
        engine.colours.foreground = colour("2E6BE6")
        engine.beginStroke(at: PixelPoint(x: 250, y: 430))
        for x in stride(from: 250, through: 790, by: 10) {
            engine.continueStroke(
                to: PixelPoint(x: x, y: 430 + Int(70 * sin(Double(x - 250) / 118)))
            )
        }
        engine.endStroke()

        // The arrow — the one primitive the original never had.
        engine.settings.tool = .shape
        engine.settings.shapeKind = .arrow
        engine.settings.shapeStyle = .outline
        engine.settings.brushSize = 34
        engine.colours.foreground = colour("E5484D")
        engine.beginStroke(at: PixelPoint(x: 300, y: 810))
        engine.endStroke(at: PixelPoint(x: 745, y: 675))

        let master = engine.canvas
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )

        // Every size AppKit asks for, resampled from the one master.
        let variants: [(name: String, pixels: Int)] = [
            ("icon_16x16", 16), ("icon_16x16@2x", 32),
            ("icon_32x32", 32), ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256),
            ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512), ("icon_512x512@2x", 1024),
        ]
        for variant in variants {
            guard let scaled = ImageTransform.scaled(
                master, to: (variant.pixels, variant.pixels), using: .smooth
            ) else { continue }
            try ImageCodec.write(
                scaled, to: directory.appendingPathComponent("\(variant.name).png"), as: .png
            )
        }
        print("Wrote \(variants.count) icon sizes to \(directory.path)")
    }
}
