import PaintKit

@MainActor
enum TransparencyScene {
    static let backgroundSample = PixelPoint(x: 20, y: 20)

    static func render() -> Bitmap {
        let canvas = DemoCanvas(fill: colour("CDEFE2"))
        let engine = canvas.engine
        let navy = colour("17324D")

        // Every part starts as an opaque shape on a single mint canvas. The
        // connected mint region is removed below through Instant Alpha.
        filledShape(
            on: canvas,
            kind: .triangle,
            from: point(262, 182),
            to: point(762, 482),
            colour: colour("B5CDD6")
        )

        engine.settings.brushSize = 5
        engine.settings.shapeStyle = .outlineAndFill
        engine.settings.strokeDash = .solid
        engine.colours.foreground = navy
        engine.colours.background = .white
        canvas.shape(.triangle, from: point(250, 170), to: point(750, 470))

        filledShape(
            on: canvas,
            kind: .rightTriangle,
            from: point(383, 310),
            to: point(500, 470),
            colour: colour("EF6A5B")
        )
        filledShape(
            on: canvas,
            kind: .triangle,
            from: point(383, 310),
            to: point(617, 470),
            colour: colour("2F80ED")
        )

        engine.settings.brushSize = 5
        engine.settings.shapeStyle = .outline
        engine.settings.strokeDash = .solid
        engine.colours.foreground = navy
        line(on: canvas, from: point(500, 170), to: point(250, 470))
        line(on: canvas, from: point(500, 170), to: point(750, 470))
        line(on: canvas, from: point(250, 470), to: point(750, 470))
        line(on: canvas, from: point(500, 170), to: point(500, 470))
        line(on: canvas, from: point(383, 310), to: point(500, 470))
        line(on: canvas, from: point(500, 310), to: point(383, 470))
        line(on: canvas, from: point(500, 310), to: point(617, 470))

        engine.settings.tool = .select
        engine.settings.selectionKind = .instantAlpha
        engine.settings.selectionTolerance = 0
        engine.beginStroke(at: backgroundSample)
        engine.makeSelectionTransparent()

        return engine.canvas
    }

    private static func filledShape(
        on canvas: DemoCanvas,
        kind: ShapeKind,
        from: PixelPoint,
        to: PixelPoint,
        colour: PaintColour
    ) {
        let engine = canvas.engine
        engine.settings.brushSize = 1
        engine.settings.shapeStyle = .filled
        engine.colours.background = colour
        canvas.shape(kind, from: from, to: to)
    }

    private static func line(on canvas: DemoCanvas, from: PixelPoint, to: PixelPoint) {
        canvas.shape(.line, from: from, to: to)
    }

    private static func point(_ x: Int, _ y: Int) -> PixelPoint {
        PixelPoint(x: x, y: y)
    }

    private static func colour(_ hex: String) -> PaintColour {
        PaintColour(hex: hex) ?? .black
    }
}
