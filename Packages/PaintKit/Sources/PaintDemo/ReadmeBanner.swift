import Foundation
import PaintKit

/// The README hero, drawn by the app's own engine.
///
/// The page used to open with a screenshot of a window, which is a picture of
/// software rather than a piece of design, and it read as such next to any
/// well-presented repository. This is a composed banner: gradient, glow, icon,
/// wordmark, and the editor bleeding off the bottom edge.
///
/// **Generated, not hand-made in a design tool.** Every pixel comes from
/// PaintKit — the gradient is `fill`, the glow is stacked `fillEllipse` with
/// alpha, the wordmark is `TextRenderer`. So the banner is reproducible from a
/// clean checkout, it changes when the icon or the interface changes, and the
/// header of the README is itself a demonstration that the engine can compose an
/// image. A hand-edited PNG in `docs/images` would be none of those things.
///
/// One image rather than a multi-column layout, because it scales as a unit.
/// GitHub's mobile view squeezes a two-column table into two unreadable
/// columns; a single wide graphic just gets smaller.
@MainActor
enum ReadmeBanner {
    enum BannerError: LocalizedError {
        case missingIcon
        case scalingFailed

        var errorDescription: String? {
            switch self {
            case .missingIcon: "The generated 1024px app icon is missing."
            case .scalingFailed: "The source artwork could not be scaled."
            }
        }
    }

    /// 2× throughout: GitHub serves the file at container width, so drawing at
    /// twice the display size is what keeps the wordmark crisp on a Retina
    /// display instead of soft.
    ///
    /// **Short, and carrying only the lockup.** The first version was 2400×1000
    /// with the tagline, a metadata line and a screenshot of the app inside it.
    /// GitHub's phone layout renders the whole file at about 390 points wide, and
    /// everything in an image scales with the image — so the wordmark came out
    /// around ten points tall and "Free · MIT · 2.9 MB · no account, no
    /// telemetry" was simply unreadable. Text baked into a wide graphic cannot
    /// reflow, which is the whole problem.
    ///
    /// So the banner is the icon and the wordmark and nothing else, on a canvas
    /// short enough that they stay large relative to its width. Tagline, badges
    /// and the app screenshot are markdown and separate images below, where they
    /// each get the full container width and the text reflows at any size.
    static let size = (width: 2400, height: 720)

    private static func colour(_ hex: String) -> RGBA8 {
        (PaintColour(hex: hex) ?? .white).rgba8
    }

    static func run(output: URL) throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let iconURL = root.appendingPathComponent(
            "App/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png"
        )
        guard FileManager.default.fileExists(atPath: iconURL.path) else {
            throw BannerError.missingIcon
        }

        var canvas = Bitmap(width: size.width, height: size.height, fill: colour("0B0E13"))
        paintBackdrop(into: &canvas)

        let icon = try ImageCodec.decode(contentsOf: iconURL)
        guard let iconScaled = ImageTransform.scaled(icon, to: (272, 272), using: .smooth) else {
            throw BannerError.scalingFailed
        }
        canvas.composite(iconScaled, at: PixelPoint(x: (size.width - 272) / 2, y: 96))

        // 176pt in a 2400-wide image is 7.3% of the width, so it survives the
        // scale to a phone at roughly 29 points tall.
        centred("ItsPaint", y: 424, pointSize: 176, bold: true,
                hex: "FFFFFF", into: &canvas)

        try ImageCodec.write(canvas, to: output, as: .png)
        print("Wrote \(size.width)×\(size.height) README banner to \(output.path)")
    }

    // MARK: - Pieces

    /// A vertical gradient, one row at a time.
    ///
    /// PaintKit has no gradient primitive and does not need one for a paint app,
    /// so this interpolates per row and fills. A thousand one-pixel fills is
    /// nothing next to the decode this function already did.
    private static func paintBackdrop(into canvas: inout Bitmap) {
        let top = colour("11151D")
        let bottom = colour("070910")
        for y in 0..<canvas.height {
            let t = Double(y) / Double(canvas.height - 1)
            let mix = RGBA8(
                r: UInt8(Double(top.r) + (Double(bottom.r) - Double(top.r)) * t),
                g: UInt8(Double(top.g) + (Double(bottom.g) - Double(top.g)) * t),
                b: UInt8(Double(top.b) + (Double(bottom.b) - Double(top.b)) * t),
                a: 255
            )
            canvas.fill(PixelRect(x: 0, y: y, width: canvas.width, height: 1), with: mix)
        }
    }

    /// The system font, which on a Mac means SF.
    ///
    /// `"SF Pro Display"` and `"SFProDisplay-Bold"` are **not** resolvable names:
    /// `CTFontCreateWithName` silently returns Helvetica for both, so asking for
    /// them looks like it worked and quietly ships the generic face. The one name
    /// that resolves is `.AppleSystemUIFont`, which comes back as `.SFNS-Regular`,
    /// and bold has to arrive as a symbolic trait rather than in the name —
    /// `".SFNS-Bold"` resolves to *Times*.
    private static let systemFont = ".AppleSystemUIFont"

    private static func centred(
        _ text: String, y: Int, pointSize: Double, bold: Bool, hex: String,
        into canvas: inout Bitmap
    ) {
        var style = TextRenderer.Style(
            fontName: systemFont,
            pointSize: pointSize,
            colour: PaintColour(hex: hex) ?? .white
        )
        style.isBold = bold
        style.alignment = .centre
        // No rim: the backdrop is a known dark gradient, and a halo here would
        // be the legibility fix for a problem this image does not have.
        style.haloColour = nil
        TextRenderer.draw(
            text,
            in: PixelRect(x: 0, y: y, width: canvas.width, height: Int(pointSize * 1.6)),
            style: style,
            into: &canvas
        )
    }
}
