import PaintKit

@MainActor
struct DemoCanvas {
    let engine: PaintEngine

    init(width: Int = 1000, height: Int = 640, fill: PaintColour = .white) {
        engine = PaintEngine(canvas: Bitmap(width: width, height: height, fill: fill.rgba8))
    }

    func colour(_ hex: String) -> PaintColour {
        PaintColour(hex: hex) ?? .black
    }

    func drag(from: PixelPoint, to: PixelPoint, via: [PixelPoint] = []) {
        engine.beginStroke(at: from)
        for point in via { engine.continueStroke(to: point) }
        engine.endStroke(at: to)
    }

    func shape(_ kind: ShapeKind, from: PixelPoint, to: PixelPoint) {
        engine.settings.tool = .shape
        engine.settings.shapeKind = kind
        drag(from: from, to: to)
    }

    func text(
        _ value: String,
        in rect: PixelRect,
        size: Double,
        colour: PaintColour,
        bold: Bool
    ) {
        engine.drawText(
            value,
            in: rect,
            style: TextRenderer.Style(
                fontName: bold ? "Helvetica-Bold" : "Helvetica",
                pointSize: size,
                colour: colour
            )
        )
    }

    func card(
        from: PixelPoint,
        to: PixelPoint,
        fill: PaintColour,
        border: PaintColour,
        radius: Int
    ) {
        engine.settings.brushSize = 2
        engine.settings.shapeStyle = .outlineAndFill
        engine.settings.strokeDash = .solid
        engine.settings.cornerRadius = radius
        engine.colours.foreground = border
        engine.colours.background = fill
        shape(.roundedRectangle, from: from, to: to)
    }
}
