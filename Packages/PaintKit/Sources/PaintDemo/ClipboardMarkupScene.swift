import PaintKit

@MainActor
enum ClipboardMarkupScene {
    static let canvasSize = (width: 1000, height: 640)

    static func render() -> Bitmap {
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

        // The left panel deliberately resembles a pasted travel screenshot:
        // broad colour bands, an irregular coast, distant trees, and one pin.
        fillRoundedRect(
            PixelRect(x: 48, y: 132, width: 430, height: 448),
            radius: 22,
            colour: sky.rgba8,
            into: &source
        )
        Raster.fillRect(
            PixelRect(x: 48, y: 292, width: 430, height: 205),
            colour: ocean.rgba8,
            into: &source
        )
        Raster.fillPolygon(
            [
                PixelPoint(x: 48, y: 461), PixelPoint(x: 142, y: 434),
                PixelPoint(x: 236, y: 451), PixelPoint(x: 338, y: 421),
                PixelPoint(x: 478, y: 449), PixelPoint(x: 478, y: 580),
                PixelPoint(x: 48, y: 580),
            ],
            colour: sand.rgba8,
            into: &source
        )
        Raster.fillPolygon(
            [
                PixelPoint(x: 48, y: 132), PixelPoint(x: 226, y: 132),
                PixelPoint(x: 168, y: 249), PixelPoint(x: 48, y: 286),
            ],
            colour: slate.rgba8,
            into: &source
        )
        for tree in [
            PixelPoint(x: 100, y: 224), PixelPoint(x: 137, y: 210),
            PixelPoint(x: 177, y: 238), PixelPoint(x: 431, y: 250),
        ] {
            Raster.fillRect(
                PixelRect(x: tree.x - 3, y: tree.y + 18, width: 6, height: 38),
                colour: navy.rgba8,
                into: &source
            )
            Raster.fillEllipse(
                in: PixelRect(x: tree.x - 20, y: tree.y - 10, width: 40, height: 50),
                colour: slate.rgba8,
                into: &source
            )
        }
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

        let engine = PaintEngine(canvas: source)
        applyAnnotations(to: engine, navy: navy, coral: colour("E5534B"))
        return engine.canvas
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
}
