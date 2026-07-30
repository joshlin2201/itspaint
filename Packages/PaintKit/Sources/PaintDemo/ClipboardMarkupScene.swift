import Foundation
import PaintKit

@MainActor
enum ClipboardMarkupScene {
    static let canvasSize = (width: 1000, height: 640)

    static func render() -> Bitmap {
        let engine = PaintEngine(canvas: unmarkedSource())
        applyAnnotations(
            to: engine,
            navy: colour("17324D"),
            coral: colour("E5534B")
        )
        return engine.canvas
    }

    static func unmarkedSource() -> Bitmap {
        let navy = colour("17324D")
        let warmWhite = colour("FFFDF8")
        let ocean = colour("4D9FC3")
        let sky = colour("A9D8E8")
        let sand = colour("E6BE7A")
        let coral = colour("E86C5D")
        let slate = colour("617184")

        var source = Bitmap(
            width: canvasSize.width,
            height: canvasSize.height,
            fill: colour("F6F2EA").rgba8
        )

        // A compact header from the fictional screenshot being annotated.
        fillRoundedRect(
            PixelRect(x: 48, y: 34, width: 904, height: 76),
            radius: 18,
            colour: warmWhite.rgba8,
            into: &source
        )
        TextRenderer.draw(
            "Saturday plan",
            in: PixelRect(x: 64, y: 50, width: 420, height: 46),
            style: .init(fontName: "Helvetica-Bold", pointSize: 30, colour: navy),
            into: &source
        )

        drawTravelPhoto(
            in: PixelRect(x: 48, y: 132, width: 430, height: 448),
            navy: navy,
            warmWhite: warmWhite,
            ocean: ocean,
            sky: sky,
            sand: sand,
            slate: slate,
            into: &source
        )

        Raster.fillEllipse(
            in: PixelRect(x: 378, y: 341, width: 20, height: 20),
            colour: coral.rgba8,
            into: &source
        )
        Raster.fillPolygon(
            [
                PixelPoint(x: 381, y: 355), PixelPoint(x: 395, y: 355),
                PixelPoint(x: 388, y: 369),
            ],
            colour: coral.rgba8,
            into: &source
        )
        Raster.fillEllipse(
            in: PixelRect(x: 384, y: 347, width: 8, height: 8),
            colour: warmWhite.rgba8,
            into: &source
        )
        fillRoundedRect(
            PixelRect(x: 72, y: 514, width: 196, height: 44),
            radius: 12,
            colour: warmWhite.rgba8,
            into: &source
        )
        TextRenderer.draw(
            "North overlook",
            in: PixelRect(x: 88, y: 526, width: 166, height: 26),
            style: .init(fontName: "Helvetica-Bold", pointSize: 16, colour: navy),
            into: &source
        )

        // The right side is the clean schedule content the user is marking up.
        fillRoundedRect(
            PixelRect(x: 510, y: 132, width: 442, height: 448),
            radius: 22,
            colour: warmWhite.rgba8,
            into: &source
        )
        TextRenderer.draw(
            "Saturday plan",
            in: PixelRect(x: 538, y: 148, width: 300, height: 30),
            style: .init(fontName: "Helvetica-Bold", pointSize: 18, colour: slate),
            into: &source
        )

        fillRoundedRect(
            PixelRect(x: 538, y: 184, width: 386, height: 82),
            radius: 14,
            colour: sand.rgba8,
            into: &source
        )
        Raster.fillEllipse(
            in: PixelRect(x: 560, y: 210, width: 28, height: 28),
            colour: warmWhite.rgba8,
            into: &source
        )
        Raster.strokeLine(
            from: PixelPoint(x: 574, y: 214),
            to: PixelPoint(x: 574, y: 224),
            brush: Brush(shape: .round, size: 2),
            colour: navy.rgba8,
            into: &source
        )
        Raster.strokeLine(
            from: PixelPoint(x: 574, y: 224),
            to: PixelPoint(x: 581, y: 229),
            brush: Brush(shape: .round, size: 2),
            colour: navy.rgba8,
            into: &source
        )
        TextRenderer.draw(
            "10:30 AM",
            in: PixelRect(x: 606, y: 211, width: 220, height: 44),
            style: .init(fontName: "Helvetica-Bold", pointSize: 27, colour: navy),
            into: &source
        )

        fillRoundedRect(
            PixelRect(x: 538, y: 286, width: 386, height: 96),
            radius: 14,
            colour: sky.rgba8,
            into: &source
        )
        Raster.fillEllipse(
            in: PixelRect(x: 558, y: 315, width: 28, height: 28),
            colour: ocean.rgba8,
            into: &source
        )
        Raster.fillEllipse(
            in: PixelRect(x: 567, y: 324, width: 10, height: 10),
            colour: warmWhite.rgba8,
            into: &source
        )
        TextRenderer.draw(
            "North overlook",
            in: PixelRect(x: 606, y: 311, width: 280, height: 34),
            style: .init(fontName: "Helvetica-Bold", pointSize: 21, colour: navy),
            into: &source
        )

        fillRoundedRect(
            PixelRect(x: 538, y: 404, width: 386, height: 132),
            radius: 14,
            colour: colour("F6F2EA").rgba8,
            into: &source
        )
        TextRenderer.draw(
            "I’ll meet you by the blue rail.",
            in: PixelRect(x: 566, y: 431, width: 318, height: 66),
            style: .init(fontName: "Helvetica", pointSize: 20, colour: slate),
            into: &source
        )

        return source
    }

    private static func applyAnnotations(
        to engine: PaintEngine,
        navy: PaintColour,
        coral: PaintColour
    ) {
        engine.settings.tool = .highlighter
        engine.settings.brushSize = 20
        engine.settings.highlighterOpacity = 0.45
        engine.colours.foreground = colour("FFD166")
        drag(engine, from: PixelPoint(x: 598, y: 258), to: PixelPoint(x: 751, y: 258))

        engine.settings.tool = .shape
        engine.settings.shapeKind = .ellipse
        engine.settings.shapeStyle = .outline
        engine.settings.brushSize = 5
        engine.settings.strokeDash = .solid
        engine.colours.foreground = coral
        drag(engine, from: PixelPoint(x: 350, y: 324), to: PixelPoint(x: 425, y: 394))

        engine.settings.shapeKind = .arrow
        drag(engine, from: PixelPoint(x: 574, y: 362), to: PixelPoint(x: 424, y: 361))

        engine.settings.tool = .text
        engine.drawText(
            "meet here",
            in: PixelRect(x: 432, y: 326, width: 132, height: 30),
            style: .init(fontName: "Helvetica-Bold", pointSize: 19, colour: coral)
        )

        engine.settings.tool = .badge
        engine.settings.brushSize = 9
        engine.colours.foreground = coral
        engine.beginStroke(at: PixelPoint(x: 72, y: 156))
        engine.beginStroke(at: PixelPoint(x: 906, y: 156))

        engine.settings.tool = .pencil
        engine.settings.brushSize = 3
        engine.colours.foreground = navy
        engine.beginStroke(at: PixelPoint(x: 861, y: 500))
        engine.continueStroke(to: PixelPoint(x: 871, y: 510))
        engine.endStroke(at: PixelPoint(x: 891, y: 484))
    }

    private static func drag(_ engine: PaintEngine, from: PixelPoint, to: PixelPoint) {
        engine.beginStroke(at: from)
        engine.endStroke(at: to)
    }

    private static func fillRoundedRect(
        _ rect: PixelRect,
        radius: Int,
        colour: RGBA8,
        into bitmap: inout Bitmap
    ) {
        let diameter = radius * 2
        Raster.fillRect(
            PixelRect(x: rect.minX + radius, y: rect.minY, width: rect.width - diameter, height: rect.height),
            colour: colour,
            into: &bitmap
        )
        Raster.fillRect(
            PixelRect(x: rect.minX, y: rect.minY + radius, width: rect.width, height: rect.height - diameter),
            colour: colour,
            into: &bitmap
        )
        for corner in [
            PixelRect(x: rect.minX, y: rect.minY, width: diameter, height: diameter),
            PixelRect(x: rect.maxX - diameter, y: rect.minY, width: diameter, height: diameter),
            PixelRect(x: rect.minX, y: rect.maxY - diameter, width: diameter, height: diameter),
            PixelRect(x: rect.maxX - diameter, y: rect.maxY - diameter, width: diameter, height: diameter),
        ] {
            Raster.fillEllipse(in: corner, colour: colour, into: &bitmap)
        }
    }

    private static func colour(_ hex: String) -> PaintColour {
        PaintColour(hex: hex) ?? .black
    }

    private static func mix(
        _ first: PaintColour,
        _ second: PaintColour,
        _ amount: Double
    ) -> PaintColour {
        PaintColour(
            red: first.red + (second.red - first.red) * amount,
            green: first.green + (second.green - first.green) * amount,
            blue: first.blue + (second.blue - first.blue) * amount
        )
    }

    private static func drawTravelPhoto(
        in rect: PixelRect,
        navy: PaintColour,
        warmWhite: PaintColour,
        ocean: PaintColour,
        sky: PaintColour,
        sand: PaintColour,
        slate: PaintColour,
        into bitmap: inout Bitmap
    ) {
        let width = Double(rect.width - 1)
        let height = Double(rect.height - 1)
        for y in rect.minY..<rect.maxY {
            for x in rect.minX..<rect.maxX {
                let u = Double(x - rect.minX) / width
                let v = Double(y - rect.minY) / height
                let hash = (x &* 73_856_093) ^ (y &* 19_349_663)
                let grain = Double(hash & 255) / 255 - 0.5

                let waterVariation = 0.05 * sin(u * 17.0 + v * 5.0)
                    + 0.025 * sin(u * 39.0 - v * 21.0)
                var sample = mix(sky, ocean, 0.30 + v * 0.48 + waterVariation)

                // Sunlit stone enters as a broad, defocused foreground mass.
                let stoneField = v + 0.075 * sin(u * 8.4) + 0.035 * sin(u * 23.0 + v * 4.0)
                let stoneMask = smoothstep(0.62, 0.91, stoneField)
                sample = mix(sample, sand, stoneMask * 0.86)

                // Soft, overlapping colour clusters imply out-of-focus foliage
                // at the crop edges without drawing any leaf or tree symbol.
                let leftFoliage = blob(u, v, centreX: -0.03, centreY: 0.18, radiusX: 0.26, radiusY: 0.34)
                    + blob(u, v, centreX: 0.12, centreY: 0.05, radiusX: 0.20, radiusY: 0.22)
                    + blob(u, v, centreX: 0.05, centreY: 0.40, radiusX: 0.16, radiusY: 0.25)
                let rightFoliage = blob(u, v, centreX: 1.02, centreY: 0.20, radiusX: 0.22, radiusY: 0.31)
                    + blob(u, v, centreX: 0.91, centreY: 0.04, radiusX: 0.18, radiusY: 0.19)
                let foliageDetail = 0.76 + 0.16 * sin(u * 53.0 + v * 29.0)
                let foliage = min(1, (leftFoliage + rightFoliage) * foliageDetail)
                sample = mix(sample, slate, foliage * 0.74)
                sample = mix(sample, navy, foliage * foliage * 0.20)

                // A close blue rail supplies the meeting-point landmark. Both
                // members use Gaussian falloff so they sit in the same soft
                // photographic depth as the surroundings instead of becoming
                // clean diagram lines.
                let railY = 0.51 + 0.018 * sin(u * 5.2)
                let railDistance = (v - railY) / 0.034
                let horizontalRail = exp(-(railDistance * railDistance))
                let postX = 0.79 + (v - 0.50) * 0.045
                let postDistance = (u - postX) / 0.032
                let verticalRail = exp(-(postDistance * postDistance))
                    * smoothstep(0.24, 0.34, v)
                let rail = min(1, horizontalRail + verticalRail)
                sample = mix(sample, navy, min(0.34, rail * 0.28))
                sample = mix(sample, mix(ocean, sky, 0.38), rail * 0.88)

                let railHighlight = exp(-pow((v - railY + 0.012) / 0.010, 2))
                    + exp(-pow((u - postX + 0.010) / 0.010, 2))
                        * smoothstep(0.26, 0.36, v)
                sample = mix(sample, warmWhite, min(0.52, railHighlight * 0.44))

                // Lens-like light and muted shadow vary continuously across the crop.
                let flare = blob(u, v, centreX: 0.27, centreY: 0.16, radiusX: 0.34, radiusY: 0.27)
                let shade = blob(u, v, centreX: 0.58, centreY: 0.88, radiusX: 0.45, radiusY: 0.30)
                sample = mix(sample, warmWhite, flare * 0.22)
                sample = mix(sample, slate, shade * 0.13)

                let vignetteX = (u - 0.5) * 2
                let vignetteY = (v - 0.5) * 2
                let vignette = max(0, vignetteX * vignetteX + vignetteY * vignetteY - 0.48)
                let light = grain * 0.038
                    + 0.014 * sin(u * 71.0 + v * 31.0)
                    - vignette * 0.035
                bitmap.setPixel(
                    PaintColour(
                        red: sample.red + light,
                        green: sample.green + light,
                        blue: sample.blue + light
                    ).rgba8,
                    at: PixelPoint(x: x, y: y)
                )
            }
        }
    }

    private static func blob(
        _ x: Double,
        _ y: Double,
        centreX: Double,
        centreY: Double,
        radiusX: Double,
        radiusY: Double
    ) -> Double {
        let dx = (x - centreX) / radiusX
        let dy = (y - centreY) / radiusY
        return exp(-(dx * dx + dy * dy))
    }

    private static func smoothstep(_ lower: Double, _ upper: Double, _ value: Double) -> Double {
        let amount = min(1, max(0, (value - lower) / (upper - lower)))
        return amount * amount * (3 - 2 * amount)
    }
}
