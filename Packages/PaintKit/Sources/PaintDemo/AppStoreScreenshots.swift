import Foundation
import PaintKit

/// Composes Mac App Store screenshots from window captures in this repository.
///
/// Apple accepts exactly four Mac sizes; 2880×1800 is the 16:10 Retina one,
/// and a 2024×1304 window capture sits inside it at native scale with room for
/// a caption. Every pixel is opaque — App Store Connect rejects transparency.
///
/// Run from the repository root, after `scripts/appstore-screenshots.sh` has
/// produced the reel frame:
///
///     swift run --package-path Packages/PaintKit paint-demo \
///       --appstore <reel-final-frame.png> <output-dir>
@MainActor
enum AppStoreScreenshots {
    static let size = (width: 2880, height: 1800)

    struct Scene {
        let window: String        // path relative to the repository root, or absolute
        let headline: String
        let subtitle: String
        let output: String
    }

    static func run(reelFrame: URL, outputDir: URL) throws {
        let scenes = [
            Scene(
                window: "docs/images/editor-window.png",
                headline: "A focused paint app for your Mac",
                subtitle: "Twelve tools, fifteen shapes — no account, no cloud, no telemetry.",
                output: "01-hero.png"
            ),
            Scene(
                window: reelFrame.path,
                headline: "Number the steps. Pixelate the token.",
                subtitle: "The markup jobs the built-in tools skip.",
                output: "02-markup.png"
            ),
            Scene(
                window: "docs/images/transparency-window.png",
                headline: "Instant Alpha knocks out a background",
                subtitle: "Deterministic, with a tolerance you control — no model deciding for you.",
                output: "03-instant-alpha.png"
            ),
            Scene(
                window: "docs/images/quick-sketch-window.png",
                headline: "Open, edit, export, move on",
                subtitle: "PNG, JPEG, TIFF, BMP, GIF, HEIC, AVIF, PDF, and ICO.",
                output: "04-export.png"
            ),
        ]

        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        func colour(_ hex: String) -> PaintColour { PaintColour(hex: hex) ?? .white }

        for scene in scenes {
            let window = try ImageCodec.decode(contentsOf: URL(fileURLWithPath: scene.window))
            var canvas = Bitmap(
                width: size.width, height: size.height, fill: colour("151922").rgba8
            )

            TextRenderer.draw(
                scene.headline,
                in: PixelRect(x: 0, y: 96, width: size.width, height: 96),
                style: TextRenderer.Style(
                    fontName: "Helvetica-Bold",
                    pointSize: 72,
                    colour: colour("FFFFFF"),
                    alignment: .centre
                ),
                into: &canvas
            )
            TextRenderer.draw(
                scene.subtitle,
                in: PixelRect(x: 0, y: 214, width: size.width, height: 56),
                style: TextRenderer.Style(
                    fontName: "Helvetica",
                    pointSize: 34,
                    colour: colour("9BA7B5"),
                    alignment: .centre
                ),
                into: &canvas
            )

            canvas.composite(
                window,
                at: PixelPoint(x: (size.width - window.width) / 2, y: 336)
            )

            let output = outputDir.appendingPathComponent(scene.output)
            try ImageCodec.write(canvas, to: output, as: .png)
            print("Wrote \(canvas.width)×\(canvas.height) to \(output.path)")
        }
    }
}
