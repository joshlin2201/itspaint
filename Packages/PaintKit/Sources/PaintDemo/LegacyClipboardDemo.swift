import Foundation
import PaintKit

/// The pre-scene command's sample artwork. It stays behind the positional
/// compatibility route while the named scene assets are built separately.
@MainActor
enum LegacyClipboardDemo {
    static func render() -> DemoCanvas {
        let canvas = DemoCanvas()
        let engine = canvas.engine
        let navy = canvas.colour("17324D")
        let slate = canvas.colour("617184")
        let blue = canvas.colour("2F80ED")
        let red = canvas.colour("EF476F")
        let yellow = canvas.colour("FFD166")
        let purple = canvas.colour("7B61FF")
        let mint = canvas.colour("DDF4EE")
        let coral = canvas.colour("FDE5DF")
        let paper = canvas.colour("F4F6F8")
        let white = canvas.colour("FFFFFF")

        engine.settings.tool = .fill
        engine.colours.foreground = paper
        canvas.drag(from: PixelPoint(x: 5, y: 5), to: PixelPoint(x: 5, y: 5))

        canvas.text("Mark it up.", in: PixelRect(x: 60, y: 38, width: 520, height: 60), size: 42, colour: navy, bold: true)
        canvas.text("Twelve tools. One quick window.", in: PixelRect(x: 62, y: 98, width: 520, height: 34), size: 20, colour: slate, bold: false)

        canvas.card(from: PixelPoint(x: 60, y: 150), to: PixelPoint(x: 490, y: 330), fill: mint, border: navy, radius: 18)
        canvas.card(from: PixelPoint(x: 530, y: 150), to: PixelPoint(x: 940, y: 330), fill: coral, border: navy, radius: 18)

        canvas.text("Focus the reader", in: PixelRect(x: 102, y: 174, width: 310, height: 36), size: 24, colour: navy, bold: true)
        canvas.text("Keep one clear idea in view.", in: PixelRect(x: 102, y: 216, width: 310, height: 30), size: 17, colour: slate, bold: false)

        engine.settings.tool = .highlighter
        engine.settings.brushSize = 18
        engine.settings.highlighterOpacity = 0.45
        engine.colours.foreground = yellow
        engine.beginStroke(at: PixelPoint(x: 102, y: 259))
        for x in stride(from: 102, through: 335, by: 5) { engine.continueStroke(to: PixelPoint(x: x, y: 259)) }
        for x in stride(from: 335, through: 250, by: -5) { engine.continueStroke(to: PixelPoint(x: x, y: 259)) }
        engine.endStroke()
        canvas.text("The important bit", in: PixelRect(x: 104, y: 242, width: 250, height: 32), size: 18, colour: navy, bold: true)

        canvas.card(from: PixelPoint(x: 360, y: 230), to: PixelPoint(x: 454, y: 302), fill: white, border: canvas.colour("B8C7D1"), radius: 10)
        engine.settings.shapeStyle = .filled
        engine.colours.background = blue
        canvas.shape(.ellipse, from: PixelPoint(x: 375, y: 244), to: PixelPoint(x: 404, y: 273))
        engine.colours.background = red
        canvas.shape(.star5, from: PixelPoint(x: 412, y: 243), to: PixelPoint(x: 439, y: 271))
        engine.colours.background = canvas.colour("7CC4A8")
        canvas.shape(.rectangle, from: PixelPoint(x: 374, y: 279), to: PixelPoint(x: 441, y: 289))

        engine.settings.tool = .pixelate
        engine.settings.pixelateBlockSize = 6
        canvas.drag(from: PixelPoint(x: 405, y: 238), to: PixelPoint(x: 448, y: 296))

        canvas.text("Call out the change", in: PixelRect(x: 572, y: 174, width: 320, height: 36), size: 24, colour: navy, bold: true)
        canvas.text("Arrows, steps, and shapes.", in: PixelRect(x: 572, y: 216, width: 300, height: 30), size: 17, colour: slate, bold: false)

        engine.settings.brushSize = 3
        engine.settings.shapeStyle = .outline
        engine.settings.strokeDash = .dashed
        engine.colours.foreground = navy
        engine.settings.cornerRadius = 12
        canvas.shape(.roundedRectangle, from: PixelPoint(x: 568, y: 252), to: PixelPoint(x: 746, y: 302))
        canvas.text("Ready to ship", in: PixelRect(x: 591, y: 264, width: 150, height: 26), size: 16, colour: navy, bold: true)

        engine.settings.strokeDash = .solid
        engine.settings.shapeStyle = .outline
        engine.settings.brushSize = 4
        engine.colours.foreground = red
        canvas.shape(.arrow, from: PixelPoint(x: 872, y: 264), to: PixelPoint(x: 758, y: 278))

        engine.settings.shapeStyle = .filled
        engine.colours.background = yellow
        canvas.shape(.star5, from: PixelPoint(x: 842, y: 174), to: PixelPoint(x: 905, y: 237))

        engine.settings.tool = .badge
        engine.settings.brushSize = 9
        engine.colours.foreground = red
        for point in [PixelPoint(x: 84, y: 178), PixelPoint(x: 553, y: 178)] { engine.beginStroke(at: point) }

        engine.settings.brushSize = 2
        engine.settings.shapeStyle = .outline
        engine.settings.strokeDash = .solid
        engine.colours.foreground = canvas.colour("CBD4DC")
        canvas.shape(.line, from: PixelPoint(x: 60, y: 370), to: PixelPoint(x: 940, y: 370))

        engine.settings.tool = .brush
        engine.settings.brushShape = .soft
        engine.settings.brushSize = 13
        engine.colours.foreground = blue
        engine.beginStroke(at: PixelPoint(x: 70, y: 500))
        for x in stride(from: 70, through: 930, by: 5) { engine.continueStroke(to: PixelPoint(x: x, y: 500 + Int(28 * sin(Double(x) / 72)))) }
        engine.endStroke()

        engine.settings.tool = .airbrush
        engine.settings.brushSize = 40
        engine.settings.sprayDensity = 0.09
        engine.colours.foreground = purple
        engine.beginStroke(at: PixelPoint(x: 760, y: 414))
        for step in 0..<28 { engine.continueStroke(to: PixelPoint(x: 760 + step * 5, y: 414 + Int(13 * sin(Double(step) / 3)))) }
        for _ in 0..<8 { engine.continueStroke(to: PixelPoint(x: 895, y: 420)) }
        engine.endStroke()

        engine.settings.tool = .shape
        engine.settings.brushSize = 3
        engine.settings.strokeDash = .solid
        engine.settings.shapeStyle = .outlineAndFill
        engine.colours.foreground = navy
        engine.colours.background = white
        engine.settings.cornerRadius = 14
        canvas.shape(.callout, from: PixelPoint(x: 350, y: 390), to: PixelPoint(x: 650, y: 545))

        engine.settings.shapeStyle = .outline
        engine.settings.shapeKind = .curve
        engine.settings.brushSize = 3
        engine.colours.foreground = red
        canvas.drag(from: PixelPoint(x: 118, y: 565), to: PixelPoint(x: 310, y: 566))
        canvas.drag(from: PixelPoint(x: 213, y: 535), to: PixelPoint(x: 213, y: 535))

        engine.settings.shapeKind = .star5
        engine.settings.shapeStyle = .filled
        engine.colours.background = yellow
        canvas.shape(.star5, from: PixelPoint(x: 735, y: 493), to: PixelPoint(x: 815, y: 573))

        canvas.text("Done.", in: PixelRect(x: 430, y: 415, width: 170, height: 54), size: 36, colour: navy, bold: true)
        canvas.text("Export and move on.", in: PixelRect(x: 410, y: 463, width: 230, height: 30), size: 17, colour: slate, bold: false)

        engine.settings.tool = .badge
        engine.settings.brushSize = 9
        engine.colours.foreground = red
        engine.beginStroke(at: PixelPoint(x: 914, y: 506))
        return canvas
    }
}
