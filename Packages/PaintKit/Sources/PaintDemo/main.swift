import PaintKit
import Foundation

// Draws a sample image by driving the real `PaintEngine` through the same
// gesture API the canvas view uses. If this produces the expected picture, the
// tool → raster → codec chain works end to end, not just in unit tests.

if CommandLine.arguments.contains("--bench") {
    Benchmark.run()
    exit(0)
}

if let index = CommandLine.arguments.firstIndex(of: "--icon") {
    let target = CommandLine.arguments.count > index + 1
        ? URL(fileURLWithPath: CommandLine.arguments[index + 1])
        : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    do {
        try IconGenerator.run(into: target)
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("Icon failed: \(error)\n".utf8))
        exit(1)
    }
}

if let index = CommandLine.arguments.firstIndex(of: "--social") {
    guard CommandLine.arguments.count > index + 2 else {
        FileHandle.standardError.write(
            Data("Usage: paint-demo --social <window-capture> <output.png>\n".utf8)
        )
        exit(2)
    }
    do {
        try SocialPreview.run(
            windowCapture: URL(fileURLWithPath: CommandLine.arguments[index + 1]),
            output: URL(fileURLWithPath: CommandLine.arguments[index + 2])
        )
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("Social preview failed: \(error)\n".utf8))
        exit(1)
    }
}

let output = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/itspaint-sample.png")

let engine = PaintEngine(canvas: Bitmap(width: 1000, height: 640, fill: .white))

func colour(_ hex: String) -> PaintColour { PaintColour(hex: hex) ?? .black }

// Top-level code is main-actor isolated in Swift 6, so these helpers must be
// too — otherwise they cannot touch `engine`.

@MainActor
func drag(from: PixelPoint, to: PixelPoint, via: [PixelPoint] = []) {
    engine.beginStroke(at: from)
    for point in via { engine.continueStroke(to: point) }
    engine.endStroke(at: to)
}

@MainActor
func shape(_ kind: ShapeKind, from: PixelPoint, to: PixelPoint) {
    engine.settings.tool = .shape
    engine.settings.shapeKind = kind
    drag(from: from, to: to)
}

@MainActor
func text(
    _ value: String,
    x: Int,
    y: Int,
    width: Int,
    height: Int,
    size: Double,
    colour: PaintColour,
    bold: Bool = false
) {
    engine.drawText(
        value,
        in: PixelRect(x: x, y: y, width: width, height: height),
        style: TextRenderer.Style(
            fontName: bold ? "Helvetica-Bold" : "Helvetica",
            pointSize: size,
            colour: colour
        )
    )
}

@MainActor
func card(
    from: PixelPoint,
    to: PixelPoint,
    fill: PaintColour,
    border: PaintColour,
    radius: Int = 18
) {
    engine.settings.brushSize = 2
    engine.settings.shapeStyle = .outlineAndFill
    engine.settings.strokeDash = .solid
    engine.settings.cornerRadius = radius
    engine.colours.foreground = border
    engine.colours.background = fill
    shape(.roundedRectangle, from: from, to: to)
}

let navy = colour("17324D")
let slate = colour("617184")
let blue = colour("2F80ED")
let red = colour("EF476F")
let yellow = colour("FFD166")
let purple = colour("7B61FF")
let mint = colour("DDF4EE")
let coral = colour("FDE5DF")
let paper = colour("F4F6F8")
let white = colour("FFFFFF")

// A small, deliberate proof board rather than a renderer test chart. Every
// mark is still made through the same PaintEngine API the app uses.
engine.settings.tool = .fill
engine.colours.foreground = paper
drag(from: PixelPoint(x: 5, y: 5), to: PixelPoint(x: 5, y: 5))

text("Mark it up.", x: 60, y: 38, width: 520, height: 60, size: 42, colour: navy, bold: true)
text(
    "Twelve tools. One quick window.",
    x: 62,
    y: 98,
    width: 520,
    height: 34,
    size: 20,
    colour: slate
)

card(
    from: PixelPoint(x: 60, y: 150),
    to: PixelPoint(x: 490, y: 330),
    fill: mint,
    border: navy
)
card(
    from: PixelPoint(x: 530, y: 150),
    to: PixelPoint(x: 940, y: 330),
    fill: coral,
    border: navy
)

text("Focus the reader", x: 102, y: 174, width: 310, height: 36, size: 24, colour: navy, bold: true)
text("Keep one clear idea in view.", x: 102, y: 216, width: 310, height: 30, size: 17, colour: slate)

// Highlighter: overlapping passes must not muddy the stroke.
engine.settings.tool = .highlighter
engine.settings.brushSize = 18
engine.settings.highlighterOpacity = 0.45
engine.colours.foreground = yellow
engine.beginStroke(at: PixelPoint(x: 102, y: 259))
for x in stride(from: 102, through: 335, by: 5) {
    engine.continueStroke(to: PixelPoint(x: x, y: 259))
}
for x in stride(from: 335, through: 250, by: -5) {
    engine.continueStroke(to: PixelPoint(x: x, y: 259))
}
engine.endStroke()
text("The important bit", x: 104, y: 242, width: 250, height: 32, size: 18, colour: navy, bold: true)

// A tiny thumbnail supplies real texture for the mosaic tool.
card(
    from: PixelPoint(x: 360, y: 230),
    to: PixelPoint(x: 454, y: 302),
    fill: white,
    border: colour("B8C7D1"),
    radius: 10
)
engine.settings.shapeStyle = .filled
engine.colours.background = blue
shape(.ellipse, from: PixelPoint(x: 375, y: 244), to: PixelPoint(x: 404, y: 273))
engine.colours.background = red
shape(.star5, from: PixelPoint(x: 412, y: 243), to: PixelPoint(x: 439, y: 271))
engine.colours.background = colour("7CC4A8")
shape(.rectangle, from: PixelPoint(x: 374, y: 279), to: PixelPoint(x: 441, y: 289))

engine.settings.tool = .pixelate
engine.settings.pixelateBlockSize = 6
drag(from: PixelPoint(x: 405, y: 238), to: PixelPoint(x: 448, y: 296))

text("Call out the change", x: 572, y: 174, width: 320, height: 36, size: 24, colour: navy, bold: true)
text("Arrows, steps, and shapes.", x: 572, y: 216, width: 300, height: 30, size: 17, colour: slate)

engine.settings.brushSize = 3
engine.settings.shapeStyle = .outline
engine.settings.strokeDash = .dashed
engine.colours.foreground = navy
engine.settings.cornerRadius = 12
shape(.roundedRectangle, from: PixelPoint(x: 568, y: 252), to: PixelPoint(x: 746, y: 302))
text("Ready to ship", x: 591, y: 264, width: 150, height: 26, size: 16, colour: navy, bold: true)

engine.settings.strokeDash = .solid
engine.settings.shapeStyle = .outline
engine.settings.brushSize = 4
engine.colours.foreground = red
shape(.arrow, from: PixelPoint(x: 872, y: 264), to: PixelPoint(x: 758, y: 278))

engine.settings.shapeStyle = .filled
engine.colours.background = yellow
shape(.star5, from: PixelPoint(x: 842, y: 174), to: PixelPoint(x: 905, y: 237))

engine.settings.tool = .badge
engine.settings.brushSize = 9
engine.colours.foreground = red
for point in [PixelPoint(x: 84, y: 178), PixelPoint(x: 553, y: 178)] {
    engine.beginStroke(at: point)
}

engine.settings.brushSize = 2
engine.settings.shapeStyle = .outline
engine.settings.strokeDash = .solid
engine.colours.foreground = colour("CBD4DC")
shape(.line, from: PixelPoint(x: 60, y: 370), to: PixelPoint(x: 940, y: 370))

// Brush ribbon.
engine.settings.tool = .brush
engine.settings.brushShape = .soft
engine.settings.brushSize = 13
engine.colours.foreground = blue
engine.beginStroke(at: PixelPoint(x: 70, y: 500))
for x in stride(from: 70, through: 930, by: 5) {
    engine.continueStroke(to: PixelPoint(x: x, y: 500 + Int(28 * sin(Double(x) / 72))))
}
engine.endStroke()

// Airbrush: coverage builds where the pointer lingers.
engine.settings.tool = .airbrush
engine.settings.brushSize = 40
engine.settings.sprayDensity = 0.09
engine.colours.foreground = purple
engine.beginStroke(at: PixelPoint(x: 760, y: 414))
for step in 0..<28 {
    engine.continueStroke(to: PixelPoint(x: 760 + step * 5, y: 414 + Int(13 * sin(Double(step) / 3))))
}
for _ in 0..<8 { engine.continueStroke(to: PixelPoint(x: 895, y: 420)) }
engine.endStroke()

// A speech bubble and a curve bent through a third point.
engine.settings.tool = .shape
engine.settings.brushSize = 3
engine.settings.strokeDash = .solid
engine.settings.shapeStyle = .outlineAndFill
engine.colours.foreground = navy
engine.colours.background = white
engine.settings.cornerRadius = 14
shape(.callout, from: PixelPoint(x: 350, y: 390), to: PixelPoint(x: 650, y: 545))

engine.settings.shapeStyle = .outline
engine.settings.shapeKind = .curve
engine.settings.brushSize = 3
engine.colours.foreground = red
drag(from: PixelPoint(x: 118, y: 565), to: PixelPoint(x: 310, y: 566))
drag(from: PixelPoint(x: 213, y: 535), to: PixelPoint(x: 213, y: 535))

engine.settings.shapeKind = .star5
engine.settings.shapeStyle = .filled
engine.colours.background = yellow
shape(.star5, from: PixelPoint(x: 735, y: 493), to: PixelPoint(x: 815, y: 573))

text("Done.", x: 430, y: 415, width: 170, height: 54, size: 36, colour: navy, bold: true)
text("Export and move on.", x: 410, y: 463, width: 230, height: 30, size: 17, colour: slate)

engine.settings.tool = .badge
engine.settings.brushSize = 9
engine.colours.foreground = red
engine.beginStroke(at: PixelPoint(x: 914, y: 506))

do {
    try ImageCodec.write(engine.canvas, to: output, as: .png)
    print("Wrote \(engine.canvas.width)×\(engine.canvas.height) to \(output.path)")
    print("Undo steps recorded: \(engine.undoStack.undoCount)")
} catch {
    FileHandle.standardError.write(Data("Failed: \(error)\n".utf8))
    exit(1)
}
