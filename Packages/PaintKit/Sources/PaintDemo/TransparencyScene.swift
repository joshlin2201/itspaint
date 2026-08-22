import PaintKit

@MainActor
enum TransparencyScene {
    static let backgroundSample = PixelPoint(x: 20, y: 20)

    static func render() -> Bitmap {
        let canvas = DemoCanvas(fill: colour("CDEFE2"))
        let engine = canvas.engine
        let navy = colour("17324D")
        let plane = [
            point(741, 298), // Nose: the plane is travelling right.
            point(388, 170), // Long swept main wing.
            point(460, 290),
            point(252, 315), // Asymmetric tail.
            point(406, 461), // Shorter folded underside.
            point(505, 341),
        ]

        // Every part starts as an opaque shape on a single mint canvas. The
        // connected mint region is removed below through Instant Alpha.
        filledPolygon(
            on: canvas,
            points: plane.map { point($0.x + 10, $0.y + 9) },
            colour: colour("B5CDD6")
        )
        filledPolygon(on: canvas, points: plane, colour: .white)
        filledPolygon(
            on: canvas,
            points: [point(388, 170), point(460, 290), point(586, 262)],
            colour: colour("EF6A5B")
        )
        filledPolygon(
            on: canvas,
            points: [point(342, 328), point(505, 341), point(406, 461)],
            colour: colour("2F80ED")
        )

        engine.settings.brushSize = 5
        engine.settings.shapeStyle = .outline
        engine.settings.strokeDash = .solid
        engine.colours.foreground = navy
        polygon(on: canvas, points: plane)
        line(on: canvas, from: point(460, 290), to: point(741, 298))
        line(on: canvas, from: point(460, 290), to: point(586, 262))
        line(on: canvas, from: point(252, 315), to: point(505, 341))
        line(on: canvas, from: point(342, 328), to: point(406, 461))

        engine.settings.tool = .select
        engine.settings.selectionKind = .instantAlpha
        engine.settings.selectionTolerance = 0
        engine.beginStroke(at: backgroundSample)
        engine.makeSelectionTransparent()

        return engine.canvas
    }

    private static func filledPolygon(
        on canvas: DemoCanvas,
        points: [PixelPoint],
        colour: PaintColour
    ) {
        let engine = canvas.engine
        engine.settings.brushSize = 1
        engine.settings.shapeStyle = .filled
        engine.colours.foreground = colour
        polygon(on: canvas, points: points)
    }

    private static func polygon(on canvas: DemoCanvas, points: [PixelPoint]) {
        guard let first = points.first else { return }
        let engine = canvas.engine
        engine.settings.tool = .shape
        engine.settings.shapeKind = .polygon
        for point in points {
            engine.beginStroke(at: point)
        }
        engine.beginStroke(at: first)
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
