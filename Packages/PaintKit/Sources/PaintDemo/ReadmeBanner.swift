import Foundation
import PaintKit

/// The README hero, drawn by the app's own engine.
///
/// Every pixel comes from PaintKit — the light field is written per pixel, the
/// icon is `ImageTransform.scaled` and composited, the wordmark is
/// `TextRenderer`. So the page header is reproducible from a clean checkout, it
/// moves when the icon moves, and the header of the README is itself a
/// demonstration that the engine composes images. A hand-edited PNG sitting in
/// `docs/images` would be none of those things.
///
/// **It carries the lockup and nothing else.** An earlier version baked the
/// tagline, a metadata line and a screenshot of the app into the image. GitHub
/// renders a README at about 390 points wide on a phone, and everything inside an
/// image scales with the image — so the wordmark arrived around thirteen points
/// tall and "Free · MIT · 2.9 MB · no account, no telemetry" was three, which is
/// texture rather than words. Text baked into a wide raster cannot reflow, and
/// that is not fixable by enlarging it inside the same composition. Tagline and
/// badges are markdown now, where they reflow at any width.
///
/// **Two files, one composition.** GitHub honours `prefers-color-scheme` inside
/// `<picture>`, and a single near-black PNG is a full-width black slab above a
/// white page for everyone reading in the light theme.
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

    /// 2× the size it is displayed at, so the wordmark stays crisp rather than
    /// soft. The README shows it at `width="760"` rather than letting it fill the
    /// column, which is what the well-presented repositories do with a wordmark
    /// hero — Biome 700, Prisma 680, Warp 1024.
    static let size = (width: 2400, height: 660)

    /// Named weights, because the ladder is the difference between a lockup and a
    /// label.
    ///
    /// 188pt in **Bold** is the weight a UI button uses, and at display size it
    /// reads generic even though it genuinely is SF.
    ///
    /// These dot-prefixed names are the only route to the system font, and every
    /// wrong one fails silently. `"SF Pro Display"` and `"SFProDisplay-Bold"`
    /// return **Helvetica**. `".SFNS-Black"` returns **Times New Roman**.
    /// `".AppleSystemUIFontSemibold"` returns Helvetica, because the ladder has
    /// holes — there is no Semibold by name and Regular is the bare name.
    /// Verified by comparing `CTFontCopyPostScriptName` against the request;
    /// nothing throws, so a wrong name ships looking like it worked.
    ///
    /// At this size every one of these resolves with `opsz = 96`, the SF Pro
    /// Display optical variant, which applies display-grade tracking on its own.
    /// That matters concretely rather than as branding: `TextRenderer.Style`
    /// exposes no tracking control, so a big wordmark cannot be hand-tightened.
    private enum Face {
        /// `.SFNS-Black`, wght 1000.
        static let black = ".AppleSystemUIFontBlack"
    }

    struct Palette {
        let field: RGBA8
        let lift: RGBA8
        let ink: RGBA8

        static let dark = Palette(
            field: RGBA8(r: 11, g: 14, b: 19, a: 255),
            lift: RGBA8(r: 44, g: 91, b: 217, a: 255),
            ink: RGBA8(r: 255, g: 255, b: 255, a: 255)
        )

        static let light = Palette(
            field: RGBA8(r: 246, g: 247, b: 250, a: 255),
            lift: RGBA8(r: 37, g: 99, b: 235, a: 255),
            ink: RGBA8(r: 12, g: 16, b: 24, a: 255)
        )
    }

    static func run(output: URL, palette: Palette = .dark) throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let iconURL = root.appendingPathComponent(
            "App/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png"
        )
        guard FileManager.default.fileExists(atPath: iconURL.path) else {
            throw BannerError.missingIcon
        }

        var canvas = Bitmap(width: size.width, height: size.height, fill: palette.field)
        paintLight(into: &canvas, palette: palette)

        let icon = try ImageCodec.decode(contentsOf: iconURL)
        let side = 256
        guard let iconScaled = ImageTransform.scaled(icon, to: (side, side), using: .smooth) else {
            throw BannerError.scalingFailed
        }
        let iconY = 132
        canvas.composite(iconScaled, at: PixelPoint(x: (size.width - side) / 2, y: iconY))

        // The gap between the icon and the word is deliberately smaller than the
        // air around them. They were equal, at 120 each, and equal spacing is why
        // the two read as separately centred objects rather than one lockup.
        centred("ItsPaint", y: 418, pointSize: 188, colour: palette.ink, into: &canvas)

        try ImageCodec.write(canvas, to: output, as: .png)
        print("Wrote \(size.width)×\(size.height) banner to \(output.path)")
    }

    // MARK: - Pieces

    /// One light source, written per pixel.
    ///
    /// The backdrop used to be a vertical ramp from `11151D` to `070910`: a
    /// 13-level delta nobody perceives as light, whose only visible effect was
    /// **33 horizontal bands**, because red, green and blue each cross their
    /// rounding boundary on a different row. Stripes across a flat dark field are
    /// about the most "generated by a developer" artefact an image can carry.
    ///
    /// A radial falloff instead, so the icon sits *in* something rather than on
    /// it, tinted toward the product's own accent so the composition contains one
    /// deliberate colour. `Bitmap.map` cannot do this — it is handed a colour and
    /// not a position — so the field is written directly.
    ///
    /// The `(x ^ y) & 1` term is an ordered dither of ±0.5 of a level. Any smooth
    /// ramp quantised to 8 bits bands somewhere; alternating per pixel breaks the
    /// boundary into a checker too fine to resolve, so there is nothing left that
    /// reads as a stripe.
    private static func paintLight(into canvas: inout Bitmap, palette: Palette) {
        let centreX = Double(canvas.width) / 2
        let centreY = Double(canvas.height) * 0.40
        let reach = Double(canvas.width) * 0.60
        let peak = 0.20

        for y in 0..<canvas.height {
            for x in 0..<canvas.width {
                let dx = Double(x) - centreX
                // Squashed vertically: a circular falloff on a 3.6:1 canvas puts
                // its edge inside the frame top and bottom and reads as a disc.
                let dy = (Double(y) - centreY) * 1.7
                let distance = (dx * dx + dy * dy).squareRoot()
                let t = max(0, 1 - distance / reach)
                let amount = t * t * peak
                let dither = Double((x ^ y) & 1) - 0.5

                func channel(_ base: UInt8, _ toward: UInt8) -> UInt8 {
                    let raised = Double(base) + (Double(toward) - Double(base)) * amount
                    return UInt8(min(255, max(0, (raised + dither).rounded())))
                }

                canvas.setPixel(
                    RGBA8(
                        r: channel(palette.field.r, palette.lift.r),
                        g: channel(palette.field.g, palette.lift.g),
                        b: channel(palette.field.b, palette.lift.b),
                        a: 255
                    ),
                    at: PixelPoint(x: x, y: y)
                )
            }
        }
    }

    // There is deliberately no contact shadow.
    //
    // Six stacked ellipses under the icon read as a dark ellipse rather than as
    // shadow: against a field the radial light has already lifted, the outermost
    // ring has a visible edge, and what you see is a smudge sitting behind the
    // icon. The light does the grounding on its own — the icon is at the bright
    // centre of it — and one fewer object is the better composition.

    private static func centred(
        _ text: String, y: Int, pointSize: Double, colour: RGBA8, into canvas: inout Bitmap
    ) {
        var style = TextRenderer.Style(
            fontName: Face.black,
            pointSize: pointSize,
            colour: PaintColour(
                red: Double(colour.r) / 255,
                green: Double(colour.g) / 255,
                blue: Double(colour.b) / 255
            )
        )
        style.alignment = .centre
        // The named weight already is the weight. Asking for the bold trait on
        // top of Black is how you end up with a synthesised face.
        style.isBold = false
        style.haloColour = nil
        TextRenderer.draw(
            text,
            in: PixelRect(x: 0, y: y, width: canvas.width, height: Int(pointSize * 1.6)),
            style: style,
            into: &canvas
        )
    }
}
