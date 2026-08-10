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
    static let size = (width: 2400, height: 1000)

    private static func colour(_ hex: String) -> RGBA8 {
        (PaintColour(hex: hex) ?? .white).rgba8
    }

    static func run(windowCapture: URL, output: URL) throws {
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
        guard let iconScaled = ImageTransform.scaled(icon, to: (208, 208), using: .smooth) else {
            throw BannerError.scalingFailed
        }
        canvas.composite(iconScaled, at: PixelPoint(x: (size.width - 208) / 2, y: 96))

        centred("ItsPaint", y: 330, pointSize: 116, weight: "Helvetica-Bold",
                hex: "FFFFFF", into: &canvas)
        centred("MS Paint for the Mac.", y: 476, pointSize: 46, weight: "Helvetica",
                hex: "AFBBCB", into: &canvas)
        centred("Free  ·  MIT  ·  2.9 MB  ·  no account, no telemetry",
                y: 552, pointSize: 27, weight: "Helvetica", hex: "6B7A8E", into: &canvas)

        try placeWindow(from: windowCapture, into: &canvas)

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

    /// The editor window, centred and running off the bottom edge.
    ///
    /// Bleeding off the frame rather than sitting inside it with a margin: a
    /// screenshot with air under it reads as a screenshot, and one that continues
    /// past the edge reads as a window you are looking at.
    private static func placeWindow(from capture: URL, into canvas: inout Bitmap) throws {
        let window = try ImageCodec.decode(contentsOf: capture)
        let targetWidth = 1680
        let scale = Double(targetWidth) / Double(window.width)
        let targetHeight = Int((Double(window.height) * scale).rounded())
        guard let scaled = ImageTransform.scaled(
            window, to: (targetWidth, targetHeight), using: .smooth
        ) else { throw BannerError.scalingFailed }

        let x = (canvas.width - targetWidth) / 2
        let y = 648

        // A cast shadow, from a few offset translucent slabs. Cheaper than a
        // blur and, at this size, indistinguishable from one.
        for inset in stride(from: 26, through: 2, by: -6) {
            canvas.blend(
                PixelRect(x: x + inset / 2, y: y + inset, width: targetWidth - inset, height: 80),
                with: RGBA8(r: 0, g: 0, b: 0, a: 10)
            )
        }

        canvas.composite(scaled, at: PixelPoint(x: x, y: y))

        // A hairline above the window so it separates from the backdrop even
        // where the artwork inside it happens to be dark.
        Raster.strokeRect(
            PixelRect(x: x, y: y, width: targetWidth, height: canvas.height - y),
            brush: Brush(shape: .square, size: 2),
            colour: RGBA8(r: 255, g: 255, b: 255, a: 28),
            into: &canvas
        )
    }

    private static func centred(
        _ text: String, y: Int, pointSize: Double, weight: String, hex: String,
        into canvas: inout Bitmap
    ) {
        var style = TextRenderer.Style(
            fontName: weight,
            pointSize: pointSize,
            colour: PaintColour(hex: hex) ?? .white
        )
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
