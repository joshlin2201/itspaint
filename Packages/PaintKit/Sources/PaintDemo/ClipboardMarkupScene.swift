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

        // A compact, deterministic travel-photo surrogate: uneven depth
        // layers, haze, reflections, shoreline detail, and foreground foliage.
        fillRoundedRect(
            PixelRect(x: 48, y: 132, width: 430, height: 448),
            radius: 22,
            colour: sky.rgba8,
            into: &source
        )
        for y in 132..<306 {
            let progress = Double(y - 132) / 174
            Raster.fillRect(
                PixelRect(x: 48, y: y, width: 430, height: 1),
                colour: mix(sky, warmWhite, progress * 0.32).rgba8,
                into: &source
            )
        }
        Raster.fillPolygon(
            [
                PixelPoint(x: 76, y: 188), PixelPoint(x: 143, y: 172),
                PixelPoint(x: 214, y: 187), PixelPoint(x: 270, y: 176),
                PixelPoint(x: 337, y: 202), PixelPoint(x: 276, y: 211),
                PixelPoint(x: 188, y: 204), PixelPoint(x: 112, y: 215),
            ],
            colour: translucent(warmWhite, alpha: 0.36),
            into: &source
        )
        for y in 292..<496 {
            let progress = Double(y - 292) / 204
            Raster.fillRect(
                PixelRect(x: 48, y: y, width: 430, height: 1),
                colour: mix(ocean, navy, progress * 0.24).rgba8,
                into: &source
            )
        }

        // Distant headlands overlap instead of forming one geometric wedge.
        Raster.fillPolygon(
            [
                PixelPoint(x: 48, y: 222), PixelPoint(x: 91, y: 205),
                PixelPoint(x: 129, y: 213), PixelPoint(x: 163, y: 196),
                PixelPoint(x: 211, y: 218), PixelPoint(x: 244, y: 259),
                PixelPoint(x: 48, y: 302),
            ],
            colour: translucent(slate, alpha: 0.54),
            into: &source
        )
        Raster.fillPolygon(
            [
                PixelPoint(x: 48, y: 190), PixelPoint(x: 78, y: 173),
                PixelPoint(x: 104, y: 183), PixelPoint(x: 131, y: 158),
                PixelPoint(x: 151, y: 186), PixelPoint(x: 180, y: 169),
                PixelPoint(x: 199, y: 207), PixelPoint(x: 177, y: 250),
                PixelPoint(x: 118, y: 270), PixelPoint(x: 48, y: 289),
            ],
            colour: slate.rgba8,
            into: &source
        )

        let reflectionBrush = Brush(shape: .round, size: 2)
        for ripple in [
            (74, 327, 62), (166, 310, 41), (236, 347, 88), (340, 321, 47),
            (91, 379, 92), (217, 401, 57), (301, 373, 116), (356, 433, 73),
            (61, 421, 44), (151, 454, 71),
        ] {
            Raster.strokeLine(
                from: PixelPoint(x: ripple.0, y: ripple.1),
                to: PixelPoint(x: ripple.0 + ripple.2, y: ripple.1 + (ripple.0 % 3) - 1),
                brush: reflectionBrush,
                colour: translucent(warmWhite, alpha: 0.30),
                into: &source
            )
        }

        let wetSand = mix(sand, ocean, 0.24)
        Raster.fillPolygon(
            [
                PixelPoint(x: 48, y: 458), PixelPoint(x: 84, y: 451),
                PixelPoint(x: 126, y: 431), PixelPoint(x: 170, y: 442),
                PixelPoint(x: 221, y: 435), PixelPoint(x: 265, y: 416),
                PixelPoint(x: 311, y: 426), PixelPoint(x: 352, y: 408),
                PixelPoint(x: 405, y: 421), PixelPoint(x: 478, y: 414),
                PixelPoint(x: 478, y: 580), PixelPoint(x: 48, y: 580),
            ],
            colour: wetSand.rgba8,
            into: &source
        )
        Raster.fillPolygon(
            [
                PixelPoint(x: 48, y: 475), PixelPoint(x: 91, y: 460),
                PixelPoint(x: 139, y: 449), PixelPoint(x: 184, y: 458),
                PixelPoint(x: 233, y: 446), PixelPoint(x: 279, y: 431),
                PixelPoint(x: 326, y: 440), PixelPoint(x: 374, y: 424),
                PixelPoint(x: 421, y: 438), PixelPoint(x: 478, y: 431),
                PixelPoint(x: 478, y: 580), PixelPoint(x: 48, y: 580),
            ],
            colour: sand.rgba8,
            into: &source
        )

        // Irregular foreground detail keeps the panel from reading like icon art.
        for rock in [
            PixelRect(x: 297, y: 465, width: 25, height: 10),
            PixelRect(x: 333, y: 446, width: 12, height: 7),
            PixelRect(x: 195, y: 491, width: 18, height: 8),
            PixelRect(x: 436, y: 474, width: 21, height: 9),
        ] {
            Raster.fillEllipse(in: rock, colour: translucent(slate, alpha: 0.48), into: &source)
        }
        let branchBrush = Brush(shape: .round, size: 3)
        Raster.strokeLine(
            from: PixelPoint(x: 431, y: 304), to: PixelPoint(x: 426, y: 232),
            brush: branchBrush, colour: navy.rgba8, into: &source
        )
        for branch in [
            (426, 245, 400, 226), (428, 256, 454, 236),
            (427, 268, 397, 255), (429, 277, 456, 262),
        ] {
            Raster.strokeLine(
                from: PixelPoint(x: branch.0, y: branch.1),
                to: PixelPoint(x: branch.2, y: branch.3),
                brush: branchBrush,
                colour: navy.rgba8,
                into: &source
            )
        }
        Raster.fillPolygon(
            [
                PixelPoint(x: 390, y: 247), PixelPoint(x: 398, y: 224),
                PixelPoint(x: 413, y: 218), PixelPoint(x: 420, y: 203),
                PixelPoint(x: 437, y: 211), PixelPoint(x: 448, y: 226),
                PixelPoint(x: 462, y: 233), PixelPoint(x: 468, y: 253),
                PixelPoint(x: 453, y: 267), PixelPoint(x: 434, y: 264),
                PixelPoint(x: 420, y: 276), PixelPoint(x: 401, y: 268),
            ],
            colour: slate.rgba8,
            into: &source
        )
        let grassBrush = Brush(shape: .round, size: 2)
        for grass in [
            (62, 522, 53, 492), (75, 529, 82, 487), (94, 521, 111, 481),
            (448, 529, 438, 484), (463, 535, 454, 475),
        ] {
            Raster.strokeLine(
                from: PixelPoint(x: grass.0, y: grass.1),
                to: PixelPoint(x: grass.2, y: grass.3),
                brush: grassBrush,
                colour: translucent(navy, alpha: 0.68),
                into: &source
            )
        }

        addPhotoTexture(
            in: PixelRect(x: 48, y: 132, width: 430, height: 448),
            to: &source
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
        engine.beginStroke(at: PixelPoint(x: 534, y: 156))

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

    private static func translucent(_ colour: PaintColour, alpha: Double) -> RGBA8 {
        PaintColour(red: colour.red, green: colour.green, blue: colour.blue, alpha: alpha).rgba8
    }

    private static func addPhotoTexture(in rect: PixelRect, to bitmap: inout Bitmap) {
        let centreX = Double(rect.minX + rect.width / 2)
        let centreY = Double(rect.minY + rect.height / 2)
        for y in rect.minY..<rect.maxY {
            for x in rect.minX..<rect.maxX {
                let point = PixelPoint(x: x, y: y)
                guard let pixel = bitmap.pixel(at: point) else { continue }
                let base = PaintColour(pixel)
                let hash = (x &* 73_856_093) ^ (y &* 19_349_663)
                let grain = Double(hash & 255) / 255 - 0.5
                let wave = sin(Double(x) * 0.071) + sin(Double(y) * 0.053)
                let dx = abs(Double(x) - centreX) / Double(rect.width / 2)
                let dy = abs(Double(y) - centreY) / Double(rect.height / 2)
                let vignette = max(0, dx * dx + dy * dy - 0.42) * 0.055
                let light = grain * 0.055 + wave * 0.012 - vignette
                bitmap.setPixel(
                    PaintColour(
                        red: base.red + light,
                        green: base.green + light,
                        blue: base.blue + light
                    ).rgba8,
                    at: point
                )
            }
        }
    }
}
