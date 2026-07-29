import PaintKit

@MainActor
enum QuickSketchScene {
    static func render() -> Bitmap {
        let canvas = DemoCanvas(fill: colour("FBF8F2"))
        let navy = colour("17324D")
        let blue = colour("2F80ED")
        let coral = colour("EF6A5B")

        drawRoom(on: canvas, colour: navy)
        drawDimensions(on: canvas, colour: navy)
        drawRoute(on: canvas, colour: blue)
        drawPlacementNote(on: canvas, colour: coral)

        return canvas.engine.canvas
    }

    private static func drawRoom(on canvas: DemoCanvas, colour: PaintColour) {
        let engine = canvas.engine
        engine.settings.brushSize = 4
        engine.settings.shapeStyle = .outline
        engine.settings.strokeDash = .solid
        engine.colours.foreground = colour

        // Room outline, with a centred 90 px doorway gap in the bottom wall.
        line(on: canvas, from: point(110, 95), to: point(890, 95))
        line(on: canvas, from: point(110, 95), to: point(110, 545))
        line(on: canvas, from: point(890, 95), to: point(890, 545))
        line(on: canvas, from: point(110, 545), to: point(455, 545))
        line(on: canvas, from: point(545, 545), to: point(890, 545))

        // A simple door leaf makes the gap read as an entrance, not a mistake.
        engine.settings.brushSize = 3
        line(on: canvas, from: point(455, 545), to: point(518, 482))

        // The only two furniture blocks.
        engine.settings.brushSize = 3
        canvas.shape(.rectangle, from: point(160, 150), to: point(400, 245))
        canvas.shape(.rectangle, from: point(590, 245), to: point(775, 395))
    }

    private static func drawDimensions(on canvas: DemoCanvas, colour: PaintColour) {
        let engine = canvas.engine
        engine.settings.brushSize = 2
        engine.settings.strokeDash = .solid
        engine.colours.foreground = colour

        // Twelve-foot horizontal dimension above the room.
        line(on: canvas, from: point(110, 62), to: point(448, 62))
        line(on: canvas, from: point(552, 62), to: point(890, 62))
        line(on: canvas, from: point(110, 52), to: point(110, 72))
        line(on: canvas, from: point(890, 52), to: point(890, 72))

        // Nine-foot vertical dimension to the left of the room.
        line(on: canvas, from: point(76, 95), to: point(76, 290))
        line(on: canvas, from: point(76, 340), to: point(76, 545))
        line(on: canvas, from: point(66, 95), to: point(86, 95))
        line(on: canvas, from: point(66, 545), to: point(86, 545))

        engine.settings.tool = .text
        canvas.text(
            "12 ft",
            in: PixelRect(x: 456, y: 44, width: 88, height: 28),
            size: 19,
            colour: colour,
            bold: true
        )
        canvas.text(
            "9 ft",
            in: PixelRect(x: 25, y: 302, width: 70, height: 28),
            size: 19,
            colour: colour,
            bold: true
        )
    }

    private static func drawRoute(on canvas: DemoCanvas, colour: PaintColour) {
        let engine = canvas.engine
        engine.settings.tool = .pencil
        engine.colours.foreground = colour

        let route = [
            point(500, 543),
            point(500, 500),
            point(530, 465),
            point(565, 430),
            point(590, 365),
            point(558, 348),
            point(520, 320),
            point(478, 286),
            point(438, 254),
            point(400, 225),
        ]

        // Pencil is intentionally a one-pixel tool. Adjacent gesture passes
        // preserve that behaviour while keeping the route readable when the
        // demo is scaled to half size.
        for offset in -2...2 {
            pencilStroke(
                on: engine,
                through: route.map { point($0.x, $0.y + offset) }
            )
        }
        for offset in -1...1 {
            pencilStroke(
                on: engine,
                through: [point(415, 215 + offset), point(400, 225 + offset)]
            )
            pencilStroke(
                on: engine,
                through: [point(416, 237 + offset), point(400, 225 + offset)]
            )
        }
    }

    private static func drawPlacementNote(on canvas: DemoCanvas, colour: PaintColour) {
        let engine = canvas.engine
        engine.settings.brushSize = 5
        engine.settings.strokeDash = .solid
        engine.colours.foreground = colour
        canvas.shape(.arrow, from: point(555, 188), to: point(405, 188))

        engine.settings.tool = .text
        canvas.text(
            "set it here",
            in: PixelRect(x: 444, y: 142, width: 150, height: 32),
            size: 21,
            colour: colour,
            bold: true
        )
    }

    private static func line(on canvas: DemoCanvas, from: PixelPoint, to: PixelPoint) {
        canvas.shape(.line, from: from, to: to)
    }

    private static func pencilStroke(on engine: PaintEngine, through points: [PixelPoint]) {
        guard let first = points.first, let last = points.last else { return }
        engine.beginStroke(at: first)
        for point in points.dropFirst().dropLast() {
            engine.continueStroke(to: point)
        }
        engine.endStroke(at: last)
    }

    private static func point(_ x: Int, _ y: Int) -> PixelPoint {
        PixelPoint(x: x, y: y)
    }

    private static func colour(_ hex: String) -> PaintColour {
        PaintColour(hex: hex) ?? .black
    }
}
