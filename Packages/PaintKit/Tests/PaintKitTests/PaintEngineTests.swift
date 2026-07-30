import Foundation
import Testing
@testable import PaintKit

@Suite("Colour model")
struct PaintColourTests {

    @Test("Hex round-trips through the raster format for opaque colours")
    func hexRoundTrip() throws {
        let colour = try #require(PaintColour(hex: "#3A7BD5"))
        #expect(colour.hexString == "3A7BD5")
        #expect(PaintColour(colour.rgba8).hexString == "3A7BD5")
    }

    @Test("Shorthand hex expands correctly")
    func shorthandHex() throws {
        let short = try #require(PaintColour(hex: "F0A"))
        let long = try #require(PaintColour(hex: "FF00AA"))
        #expect(short == long)
    }

    @Test("Invalid hex is rejected rather than silently becoming black")
    func invalidHex() {
        #expect(PaintColour(hex: "nothex") == nil)
        #expect(PaintColour(hex: "12345") == nil)
        #expect(PaintColour(hex: "") == nil)
    }

    @Test("A transparent colour premultiplies to clear")
    func transparentPremultiplies() {
        #expect(PaintColour(red: 1, green: 0, blue: 0, alpha: 0).rgba8 == .clear)
    }

    @Test("Half-alpha red premultiplies its channels")
    func halfAlphaPremultiplies() {
        let raster = PaintColour(red: 1, green: 0, blue: 0, alpha: 0.5).rgba8
        #expect(raster.a == 128)
        #expect(raster.r < 140 && raster.r > 120)
    }

    @Test("HSB round-trips")
    func hsbRoundTrip() throws {
        let original = try #require(PaintColour(hex: "2E9BFF"))
        let (h, s, b) = original.hsb
        let rebuilt = PaintColour(hue: h, saturation: s, brightness: b)
        #expect(abs(rebuilt.red - original.red) < 0.01)
        #expect(abs(rebuilt.green - original.green) < 0.01)
        #expect(abs(rebuilt.blue - original.blue) < 0.01)
    }

    @Test("A negative hue wraps instead of collapsing to red")
    func negativeHueWraps() {
        // -30° is 330°: rose. Left unwrapped it falls through to the last
        // sector and comes back pure red, which is silent and wrong.
        let wrapped = PaintColour(hue: -30, saturation: 1, brightness: 1)
        #expect(wrapped == PaintColour(hue: 330, saturation: 1, brightness: 1))
        #expect(wrapped != PaintColour(hue: 0, saturation: 1, brightness: 1))
    }

    @Test("Luminance drives swatch contrast the right way round")
    func contrastDirection() {
        #expect(PaintColour.white.prefersDarkContrast)
        #expect(!PaintColour.black.prefersDarkContrast)
    }

    @Test("Components are clamped, never wrapped")
    func clamping() {
        let c = PaintColour(red: 5, green: -3, blue: 0.5, alpha: 99)
        #expect(c.red == 1 && c.green == 0 && c.alpha == 1)
    }
}

@Suite("Palette and colour pair")
struct PaletteTests {

    @Test("The standard palette is the full 28-swatch grid")
    func standardShape() {
        #expect(Palette.standard.swatches.count == 28)
        #expect(Palette.standard.rows == 2)
    }

    @Test("Palette construction preserves the fixed two-row ceiling")
    func constructionIsBounded() {
        let palette = Palette(
            swatches: Array(repeating: .black, count: Palette.maximumSwatchCount + 1)
        )
        #expect(palette.swatches.count == Palette.maximumSwatchCount)
        #expect(palette.rows == 2)
    }

    @Test("Palette coding keeps the legacy keyed wire shape")
    func codingWireShape() throws {
        let palette = Palette(swatches: [.black, .white])
        let data = try JSONEncoder().encode(palette)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(Set(object.keys) == ["swatches"])
        #expect(try JSONDecoder().decode(Palette.self, from: data) == palette)
    }

    @Test("Palette decoding accepts 28 swatches and rejects the twenty-ninth")
    func decodingBoundary() throws {
        let colourData = try JSONEncoder().encode(PaintColour.black)
        let colour = String(decoding: colourData, as: UTF8.self)

        func encodedPalette(count: Int) -> Data {
            let swatches = Array(repeating: colour, count: count).joined(separator: ",")
            return Data("{\"swatches\":[\(swatches)]}".utf8)
        }

        let accepted = try JSONDecoder().decode(
            Palette.self,
            from: encodedPalette(count: Palette.maximumSwatchCount)
        )
        #expect(accepted.swatches.count == Palette.maximumSwatchCount)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(
                Palette.self,
                from: encodedPalette(count: Palette.maximumSwatchCount + 1)
            )
        }
    }

    @Test("Swapping exchanges foreground and background")
    func swapColours() {
        var pair = ColourPair(foreground: .black, background: .white)
        pair.swap()
        #expect(pair.foreground == .white && pair.background == .black)
    }

    @Test("The secondary button paints the background colour")
    func buttonMapping() {
        let pair = ColourPair(foreground: .black, background: .white)
        #expect(pair.colour(for: .primary) == .black)
        #expect(pair.colour(for: .secondary) == .white)
    }

    @Test("The eraser mapping is the inverse of the paint mapping")
    func erasureMapping() {
        let pair = ColourPair(foreground: .black, background: .white)
        #expect(pair.erasureColour(for: .primary) == .white)
        #expect(pair.erasureColour(for: .secondary) == .black)
    }
}

@Suite("Tool set")
struct ToolSetTests {

    @Test("Every tool is reachable by a unique keyboard shortcut")
    func shortcutsAreUnique() {
        let shortcuts = ToolKind.allCases.map(\.shortcut)
        #expect(Set(shortcuts).count == ToolKind.allCases.count)
    }

    @Test("No tool claims a key reserved for something else")
    func shortcutsAvoidReservedKeys() {
        // X swaps the colour pair — a binding older than every paint app we are
        // competing with, and the most surprising thing we could override.
        let reserved: Set<Character> = ["x"]
        let claimed = Set(ToolKind.allCases.map(\.shortcut))
        #expect(claimed.isDisjoint(with: reserved))
    }

    @Test("Every tool appears exactly once in the rail groups")
    func railCoversEveryTool() {
        let grouped = ToolKind.groups.flatMap { $0 }
        #expect(Set(grouped) == Set(ToolKind.allCases))
        #expect(grouped.count == ToolKind.allCases.count)
    }

    @Test("Shapes are one tool, not one tool per shape")
    func shapesAreConsolidated() {
        // The rail must not regrow a button per shape. Fifteen shapes exist;
        // exactly one tool emits them, and they are chosen inside that tool's
        // own options — which is the whole reason the rail stays scannable.
        #expect(ShapeKind.allCases.count > 8)
        #expect(ToolKind.allCases.filter(\.usesShapeKind) == [.shape])
    }

    @Test("The rail stays small enough to scan")
    func toolSetStaysSmall() {
        // The ceiling is the point, not the exact number: past this the rail
        // stops being a row you read at a glance and becomes a palette you
        // search. New capability belongs inside a tool's options.
        #expect(ToolKind.allCases.count <= 14, "tool set grew to \(ToolKind.allCases.count)")
    }

    @Test("Shapes that only differ by their outline are not tools")
    func shapesAreNotTools() {
        let names = Set(ToolKind.allCases.map(\.rawValue))
        for retired in ["magnifier", "rectangle", "ellipse", "line", "curve", "polygon", "star"] {
            #expect(!names.contains(retired), "\(retired) should be a shape, not a tool")
        }
    }

    @Test("Open shapes report no interior")
    func openShapes() {
        #expect(!ShapeKind.line.isClosed)
        #expect(!ShapeKind.arrow.isClosed)
        #expect(ShapeKind.ellipse.isClosed)
    }
}

@Suite("Undo stack")
struct UndoStackTests {

    @Test("A stroke can be undone and redone exactly")
    func undoRedoRoundTrip() {
        let engine = PaintEngine(width: 32, height: 32)
        let pristine = engine.canvas

        engine.settings.tool = .pencil
        engine.beginStroke(at: PixelPoint(x: 4, y: 4))
        engine.continueStroke(to: PixelPoint(x: 20, y: 20))
        engine.endStroke()

        let painted = engine.canvas
        #expect(painted != pristine)

        engine.undo()
        #expect(engine.canvas == pristine)

        engine.redo()
        #expect(engine.canvas == painted)
    }

    @Test("Undo names the tool so the Edit menu can read 'Undo Pencil'")
    func undoIsNamed() {
        let engine = PaintEngine(width: 16, height: 16)
        engine.settings.tool = .pencil
        engine.beginStroke(at: PixelPoint(x: 2, y: 2))
        engine.endStroke()
        #expect(engine.undoStack.undoActionName == "Pencil")
    }

    @Test("A new edit discards the redo branch")
    func newEditClearsRedo() {
        let engine = PaintEngine(width: 16, height: 16)
        engine.settings.tool = .pencil
        engine.beginStroke(at: PixelPoint(x: 1, y: 1)); engine.endStroke()
        engine.undo()
        #expect(engine.canRedo)
        engine.beginStroke(at: PixelPoint(x: 8, y: 8)); engine.endStroke()
        #expect(!engine.canRedo)
    }

    @Test("Ten strokes undo back to a pristine canvas")
    func deepUndo() {
        let engine = PaintEngine(width: 40, height: 40)
        let pristine = engine.canvas
        engine.settings.tool = .pencil
        for i in 0..<10 {
            engine.beginStroke(at: PixelPoint(x: i, y: i))
            engine.continueStroke(to: PixelPoint(x: i + 5, y: i + 5))
            engine.endStroke()
        }
        #expect(engine.undoStack.undoCount == 10)
        for _ in 0..<10 { engine.undo() }
        #expect(engine.canvas == pristine)
        #expect(!engine.canUndo)
    }

    @Test("Undo history is bounded by bytes, and always keeps one step")
    func budgetIsEnforced() {
        let engine = PaintEngine(canvas: Bitmap(width: 64, height: 64), undoByteBudget: 1_024)
        engine.settings.tool = .fill
        for i in 0..<5 {
            engine.colours.foreground = PaintColour(red: Double(i) / 5, green: 0.2, blue: 0.4)
            engine.beginStroke(at: PixelPoint(x: 10, y: 10))
        }
        #expect(engine.undoStack.undoCount >= 1)
        #expect(engine.undoStack.undoCount < 5)
    }

    @Test("Read-only tools never enter undo history")
    func eyedropperIsNotAnEdit() {
        let engine = PaintEngine(width: 16, height: 16)
        engine.settings.tool = .eyedropper
        engine.beginStroke(at: PixelPoint(x: 2, y: 2))
        engine.endStroke()
        #expect(!engine.canUndo)
    }
}

@Suite("Engine gestures")
struct EngineGestureTests {

    @Test("A freehand stroke paints a connected path")
    func freehandIsConnected() {
        let engine = PaintEngine(width: 32, height: 32)
        engine.settings.tool = .pencil
        engine.colours.foreground = .black
        engine.beginStroke(at: PixelPoint(x: 2, y: 2))
        engine.continueStroke(to: PixelPoint(x: 10, y: 2))
        engine.endStroke()

        for x in 2...10 {
            #expect(engine.canvas.pixel(at: PixelPoint(x: x, y: 2)) == .black)
        }
    }

    @Test("The secondary button paints the background colour")
    func rightDragPaintsBackground() {
        let engine = PaintEngine(width: 16, height: 16)
        engine.settings.tool = .pencil
        engine.colours = ColourPair(foreground: .black, background: PaintColour(hex: "FF0000")!)
        engine.beginStroke(at: PixelPoint(x: 5, y: 5), button: .secondary)
        engine.endStroke()
        #expect(engine.canvas.pixel(at: PixelPoint(x: 5, y: 5)) == PaintColour(hex: "FF0000")!.rgba8)
    }

    @Test("The eraser lays down the background colour")
    func eraserPaintsBackground() {
        let engine = PaintEngine(width: 16, height: 16)
        engine.colours = ColourPair(foreground: .black, background: .white)
        engine.settings.tool = .pencil
        engine.beginStroke(at: PixelPoint(x: 5, y: 5)); engine.endStroke()
        #expect(engine.canvas.pixel(at: PixelPoint(x: 5, y: 5)) == RGBA8.black)

        engine.settings.tool = .eraser
        engine.settings.brushSize = 1
        engine.beginStroke(at: PixelPoint(x: 5, y: 5)); engine.endStroke()
        #expect(engine.canvas.pixel(at: PixelPoint(x: 5, y: 5)) == RGBA8.white)
    }

    @Test("A dragged shape previews without accumulating ghosts")
    func shapePreviewDoesNotAccumulate() {
        let engine = PaintEngine(width: 40, height: 40)
        engine.settings.tool = .shape
        engine.settings.shapeKind = .rectangle
        engine.settings.shapeStyle = .outline
        engine.settings.brushSize = 1
        engine.colours.foreground = .black

        engine.beginStroke(at: PixelPoint(x: 5, y: 5))
        engine.continueStroke(to: PixelPoint(x: 35, y: 35))
        engine.continueStroke(to: PixelPoint(x: 15, y: 15))
        engine.endStroke()

        #expect(engine.canvas.pixel(at: PixelPoint(x: 15, y: 15)) == .black)
        #expect(engine.canvas.pixel(at: PixelPoint(x: 35, y: 35)) == .white)
        #expect(engine.canvas.pixel(at: PixelPoint(x: 35, y: 20)) == .white)
    }

    @Test("Cancelling a shape restores the canvas exactly")
    func cancelRestores() {
        let engine = PaintEngine(width: 32, height: 32)
        let pristine = engine.canvas
        engine.settings.tool = .shape
        engine.settings.shapeKind = .ellipse
        engine.beginStroke(at: PixelPoint(x: 4, y: 4))
        engine.continueStroke(to: PixelPoint(x: 28, y: 28))
        #expect(engine.canvas != pristine)

        engine.cancelStroke()
        #expect(engine.canvas == pristine)
        #expect(!engine.canUndo)
    }

    @Test("Shift constrains a rectangle to a square")
    func constrainedSquare() {
        let engine = PaintEngine(width: 60, height: 60)
        engine.settings.tool = .shape
        engine.settings.shapeKind = .rectangle
        engine.settings.shapeStyle = .outline
        engine.settings.brushSize = 1
        engine.beginStroke(at: PixelPoint(x: 5, y: 5))
        engine.endStroke(at: PixelPoint(x: 45, y: 20), constrained: true)

        #expect(engine.canvas.pixel(at: PixelPoint(x: 45, y: 45)) == .black)
        #expect(engine.canvas.pixel(at: PixelPoint(x: 5, y: 45)) == .black)
    }

    @Test("Shift snaps a line to the horizontal")
    func constrainedLine() {
        let engine = PaintEngine(width: 60, height: 60)
        engine.settings.tool = .shape
        engine.settings.shapeKind = .line
        engine.settings.brushSize = 1
        engine.beginStroke(at: PixelPoint(x: 5, y: 30))
        engine.endStroke(at: PixelPoint(x: 50, y: 33), constrained: true)

        for x in 5...50 {
            #expect(engine.canvas.pixel(at: PixelPoint(x: x, y: 30)) == .black)
        }
        #expect(engine.canvas.pixel(at: PixelPoint(x: 50, y: 33)) == .white)
    }

    @Test("A rounded rectangle rounds its corners and leaves no stray arcs")
    func roundedRectangleCorners() {
        let engine = PaintEngine(width: 80, height: 80)
        engine.settings.tool = .shape
        engine.settings.shapeKind = .roundedRectangle
        engine.settings.shapeStyle = .outline
        engine.settings.brushSize = 1
        engine.settings.cornerRadius = 12
        engine.beginStroke(at: PixelPoint(x: 10, y: 10))
        engine.endStroke(at: PixelPoint(x: 69, y: 69))

        #expect(engine.canvas.pixel(at: PixelPoint(x: 10, y: 10)) == .white)
        #expect(engine.canvas.pixel(at: PixelPoint(x: 69, y: 69)) == .white)
        #expect(engine.canvas.pixel(at: PixelPoint(x: 40, y: 10)) == .black)
        #expect(engine.canvas.pixel(at: PixelPoint(x: 10, y: 40)) == .black)
        for y in 26...53 {
            for x in 26...53 {
                #expect(engine.canvas.pixel(at: PixelPoint(x: x, y: y)) == .white)
            }
        }
    }

    @Test("Outline and fill uses both colours")
    func outlineAndFill() {
        let engine = PaintEngine(width: 40, height: 40)
        engine.settings.tool = .shape
        engine.settings.shapeKind = .rectangle
        engine.settings.shapeStyle = .outlineAndFill
        engine.settings.brushSize = 1
        engine.colours = ColourPair(
            foreground: PaintColour(hex: "000000")!, background: PaintColour(hex: "FF0000")!
        )
        engine.beginStroke(at: PixelPoint(x: 5, y: 5))
        engine.endStroke(at: PixelPoint(x: 34, y: 34))

        #expect(engine.canvas.pixel(at: PixelPoint(x: 5, y: 5)) == RGBA8.black)
        #expect(engine.canvas.pixel(at: PixelPoint(x: 20, y: 20)) == PaintColour(hex: "FF0000")!.rgba8)
    }

    @Test("The eyedropper loads the sampled colour as foreground")
    func eyedropperSamples() {
        let engine = PaintEngine(width: 16, height: 16)
        let red = PaintColour(hex: "FF0000")!
        engine.settings.tool = .pencil
        engine.colours.foreground = red
        engine.beginStroke(at: PixelPoint(x: 8, y: 8)); engine.endStroke()

        engine.colours.foreground = .black
        engine.settings.tool = .eyedropper
        engine.beginStroke(at: PixelPoint(x: 8, y: 8))

        #expect(engine.colours.foreground == red)
        #expect(engine.lastSampledColour == red)
    }

    @Test("Fill commits in one gesture and is undoable as one step")
    func fillIsOneStep() {
        let engine = PaintEngine(width: 32, height: 32)
        let pristine = engine.canvas
        engine.settings.tool = .fill
        engine.colours.foreground = PaintColour(hex: "00FF00")!
        engine.beginStroke(at: PixelPoint(x: 16, y: 16))
        engine.endStroke()

        #expect(engine.undoStack.undoCount == 1)
        engine.undo()
        #expect(engine.canvas == pristine)
    }

    @Test("A dropped mouse-up commits rather than losing the stroke")
    func interruptedGestureCommits() {
        let engine = PaintEngine(width: 32, height: 32)
        engine.settings.tool = .pencil
        engine.beginStroke(at: PixelPoint(x: 2, y: 2))
        engine.continueStroke(to: PixelPoint(x: 10, y: 2))
        engine.beginStroke(at: PixelPoint(x: 20, y: 20))
        engine.endStroke()

        #expect(engine.undoStack.undoCount == 2)
        #expect(engine.canvas.pixel(at: PixelPoint(x: 5, y: 2)) == .black)
    }

    @Test("Invert twice returns the original image")
    func invertIsInvolutive() {
        let engine = PaintEngine(width: 24, height: 24)
        engine.settings.tool = .pencil
        engine.beginStroke(at: PixelPoint(x: 4, y: 4))
        engine.continueStroke(to: PixelPoint(x: 18, y: 18))
        engine.endStroke()
        let original = engine.canvas

        engine.invertColours()
        #expect(engine.canvas != original)
        engine.invertColours()
        #expect(engine.canvas == original)
    }

    @Test("Invert honours the marquee instead of hitting the whole canvas")
    func invertRespectsSelection() {
        let engine = PaintEngine(width: 40, height: 40)
        engine.settings.tool = .select
        engine.beginStroke(at: PixelPoint(x: 5, y: 5))
        engine.endStroke(at: PixelPoint(x: 20, y: 20))
        engine.invertColours()

        #expect(engine.canvas.pixel(at: PixelPoint(x: 10, y: 10)) == .black)   // inverted white
        #expect(engine.canvas.pixel(at: PixelPoint(x: 30, y: 30)) == .white)   // untouched
    }

    @Test("Clear fills with the background colour and is undoable")
    func clearUsesBackground() {
        let engine = PaintEngine(width: 20, height: 20)
        engine.settings.tool = .pencil
        engine.beginStroke(at: PixelPoint(x: 5, y: 5)); engine.endStroke()
        let drawn = engine.canvas

        engine.colours.background = PaintColour(hex: "0000FF")!
        engine.clearCanvas()
        #expect(engine.canvas.pixels.allSatisfy { $0 == PaintColour(hex: "0000FF")!.rgba8 })

        engine.undo()
        #expect(engine.canvas == drawn)
    }

    @Test("Resizing the canvas is undoable, and the work before it survives")
    func resizeIsUndoable() {
        // This used to clear the history: a rect patch is addressed in canvas
        // coordinates, so replaying one into a differently-sized canvas put
        // pixels in the wrong places, and wiping the stack was the safe way out.
        // A size change now records both canvases whole, so the resize *and*
        // everything before it stay reversible.
        let engine = PaintEngine(width: 20, height: 20)
        engine.settings.tool = .pencil
        engine.beginStroke(at: PixelPoint(x: 5, y: 5)); engine.endStroke()
        #expect(engine.canUndo)
        let drawn = engine.canvas

        engine.replaceCanvas(with: Bitmap(width: 40, height: 40), actionName: "Resize")
        #expect(engine.canvas.width == 40)
        #expect(engine.canUndo)

        engine.undo()
        #expect(engine.canvas.width == 20, "undo did not restore the original size")
        #expect(engine.canvas == drawn, "undo did not restore the pixels drawn before the resize")

        // And the stroke underneath is still reachable.
        #expect(engine.canUndo)
        engine.undo()
        #expect(engine.canvas != drawn)
    }
}

@Suite("Highlighter")
struct HighlighterTests {

    private func highlighterEngine() -> PaintEngine {
        let engine = PaintEngine(width: 120, height: 60)
        engine.settings.tool = .highlighter
        engine.settings.brushSize = 12
        engine.settings.highlighterOpacity = 0.4
        engine.colours.foreground = PaintColour(hex: "FFD400")!
        return engine
    }

    @Test("Overlapping passes within one stroke do not darken")
    func noOverlapDarkening() {
        // THE defining property of a highlighter. Compositing each stamp
        // directly would muddy every place a slow drag overlaps itself.
        let engine = highlighterEngine()
        engine.beginStroke(at: PixelPoint(x: 20, y: 30))
        engine.continueStroke(to: PixelPoint(x: 100, y: 30))
        engine.continueStroke(to: PixelPoint(x: 20, y: 30))   // back over the same run
        engine.continueStroke(to: PixelPoint(x: 100, y: 30))  // and again
        engine.endStroke()

        let single = engine.canvas.pixel(at: PixelPoint(x: 25, y: 30))
        let quadruple = engine.canvas.pixel(at: PixelPoint(x: 60, y: 30))
        #expect(single == quadruple)
    }

    @Test("Highlighter is translucent — the content underneath survives")
    func staysTranslucent() {
        let engine = highlighterEngine()
        engine.settings.tool = .pencil
        engine.colours.foreground = .black
        engine.beginStroke(at: PixelPoint(x: 20, y: 30))
        engine.endStroke(at: PixelPoint(x: 100, y: 30))

        engine.settings.tool = .highlighter
        engine.colours.foreground = PaintColour(hex: "FFD400")!
        engine.beginStroke(at: PixelPoint(x: 20, y: 30))
        engine.endStroke(at: PixelPoint(x: 100, y: 30))

        // The black line is tinted, not erased.
        let overLine = engine.canvas.pixel(at: PixelPoint(x: 60, y: 30))!
        let overPaper = engine.canvas.pixel(at: PixelPoint(x: 60, y: 26))!
        #expect(overLine != overPaper)
        #expect(overLine.r < overPaper.r)
    }

    @Test("A separate stroke does layer on top of the first")
    func separateStrokesAccumulate() {
        // Within a stroke: no darkening. Across strokes: darkening, because the
        // user asked for a second pass.
        let engine = highlighterEngine()
        engine.beginStroke(at: PixelPoint(x: 20, y: 30))
        engine.endStroke(at: PixelPoint(x: 100, y: 30))
        let afterFirst = engine.canvas.pixel(at: PixelPoint(x: 60, y: 30))

        engine.beginStroke(at: PixelPoint(x: 20, y: 30))
        engine.endStroke(at: PixelPoint(x: 100, y: 30))
        let afterSecond = engine.canvas.pixel(at: PixelPoint(x: 60, y: 30))

        #expect(afterFirst != afterSecond)
    }

    @Test("A highlighter stroke undoes as one step")
    func undoesAsOneStep() {
        let engine = highlighterEngine()
        let pristine = engine.canvas
        engine.beginStroke(at: PixelPoint(x: 20, y: 30))
        engine.continueStroke(to: PixelPoint(x: 100, y: 30))
        engine.endStroke()

        #expect(engine.undoStack.undoCount == 1)
        engine.undo()
        #expect(engine.canvas == pristine)
    }
}

@Suite("Selection, clipboard and crop")
struct SelectionTests {

    /// A canvas carrying a solid red block covering exactly x/y 5...20.
    ///
    /// The drag runs 4→21 because `.filled` insets by the brush width so the
    /// interior does not bleed under its own outline.
    private func markedEngine() -> PaintEngine {
        let engine = PaintEngine(width: 60, height: 60)
        engine.settings.tool = .shape
        engine.settings.shapeKind = .rectangle
        engine.settings.shapeStyle = .filled
        engine.settings.brushSize = 1
        engine.colours.background = PaintColour(hex: "FF0000")!
        engine.beginStroke(at: PixelPoint(x: 4, y: 4))
        engine.endStroke(at: PixelPoint(x: 21, y: 21))
        engine.colours.background = .white
        return engine
    }

    private func select(_ engine: PaintEngine, _ a: PixelPoint, _ b: PixelPoint) {
        engine.settings.tool = .select
        engine.beginStroke(at: a)
        engine.endStroke(at: b)
    }

    @Test("Dragging the select tool produces a marquee")
    func marqueeIsCreated() {
        let engine = markedEngine()
        select(engine, PixelPoint(x: 4, y: 4), PixelPoint(x: 21, y: 21))
        #expect(engine.selectionBounds == PixelRect(x: 4, y: 4, width: 18, height: 18))
        #expect(engine.hasSelection)
    }

    @Test("A click without a drag clears the marquee")
    func clickClearsMarquee() {
        let engine = markedEngine()
        select(engine, PixelPoint(x: 4, y: 4), PixelPoint(x: 21, y: 21))
        select(engine, PixelPoint(x: 40, y: 40), PixelPoint(x: 40, y: 40))
        #expect(engine.selection == nil)
    }

    @Test("Instant Alpha selects a connected colour without editing")
    func instantAlphaIsNonDestructive() throws {
        let engine = markedEngine()
        let before = engine.canvas
        let undoCount = engine.undoStack.undoCount
        engine.settings.tool = .select
        engine.settings.selectionKind = .instantAlpha

        engine.beginStroke(at: PixelPoint(x: 0, y: 0))

        let selection = try #require(engine.selection)
        #expect(selection.contains(PixelPoint(x: 0, y: 0)))
        #expect(!selection.contains(PixelPoint(x: 10, y: 10)))
        #expect(engine.canvas == before)
        #expect(engine.undoStack.undoCount == undoCount)
    }

    @Test("Instant Alpha adds and subtracts disconnected colour regions")
    func instantAlphaCombinesRegions() throws {
        var canvas = Bitmap(width: 30, height: 10, fill: .white)
        let red = RGBA8(r: 255, g: 0, b: 0)
        let blue = RGBA8(r: 0, g: 0, b: 255)
        Raster.fillRect(PixelRect(x: 0, y: 0, width: 10, height: 10), colour: red, into: &canvas)
        Raster.fillRect(PixelRect(x: 20, y: 0, width: 10, height: 10), colour: blue, into: &canvas)
        let engine = PaintEngine(canvas: canvas)

        engine.selectInstantAlpha(at: PixelPoint(x: 2, y: 2))
        engine.selectInstantAlpha(at: PixelPoint(x: 22, y: 2), operation: .add)
        #expect(engine.selection?.contains(PixelPoint(x: 2, y: 2)) == true)
        #expect(engine.selection?.contains(PixelPoint(x: 22, y: 2)) == true)
        #expect(engine.selection?.contains(PixelPoint(x: 15, y: 2)) == false)

        engine.selectInstantAlpha(at: PixelPoint(x: 2, y: 2), operation: .subtract)
        let remaining = try #require(engine.selection)
        #expect(!remaining.contains(PixelPoint(x: 2, y: 2)))
        #expect(remaining.contains(PixelPoint(x: 22, y: 2)))
    }

    @Test("Instant Alpha tolerance includes connected near colours")
    func instantAlphaUsesItsOwnTolerance() {
        var canvas = Bitmap(width: 8, height: 8, fill: .white)
        canvas.setPixel(RGBA8(r: 248, g: 248, b: 248), at: PixelPoint(x: 4, y: 4))
        let engine = PaintEngine(canvas: canvas)
        engine.settings.selectionTolerance = 0
        engine.selectInstantAlpha(at: PixelPoint(x: 0, y: 0))
        #expect(engine.selection?.contains(PixelPoint(x: 4, y: 4)) == false)

        engine.settings.selectionTolerance = 8
        engine.selectInstantAlpha(at: PixelPoint(x: 0, y: 0))
        #expect(engine.selection?.contains(PixelPoint(x: 4, y: 4)) == true)
    }

    @Test("Make transparent clears only Instant Alpha's mask and undoes")
    func instantAlphaRemovalIsUndoable() {
        let engine = markedEngine()
        let before = engine.canvas
        engine.settings.selectionTolerance = 0
        engine.selectInstantAlpha(at: PixelPoint(x: 0, y: 0))

        engine.makeSelectionTransparent()

        #expect(engine.canvas.pixel(at: PixelPoint(x: 0, y: 0)) == .clear)
        #expect(engine.canvas.pixel(at: PixelPoint(x: 10, y: 10))?.a == 255)
        #expect(engine.undoStack.undoActionName == "Make transparent")
        engine.undo()
        #expect(engine.canvas == before)
    }

    @Test("Selecting does not modify a single pixel")
    func selectingIsNonDestructive() {
        let engine = markedEngine()
        let before = engine.canvas
        let stepsBefore = engine.undoStack.undoCount

        select(engine, PixelPoint(x: 4, y: 4), PixelPoint(x: 21, y: 21))

        #expect(engine.canvas == before)
        // Selecting is not an edit, so it must not add an undo step either.
        #expect(engine.undoStack.undoCount == stepsBefore)
    }

    @Test("Copy returns the selected pixels without changing the canvas")
    func copyIsNonDestructive() throws {
        let engine = markedEngine()
        let before = engine.canvas
        select(engine, PixelPoint(x: 5, y: 5), PixelPoint(x: 14, y: 14))

        let content = try #require(engine.selectedContent())
        #expect(content.width == 10 && content.height == 10)
        #expect(content.pixels.allSatisfy { $0 == PaintColour(hex: "FF0000")!.rgba8 })
        #expect(engine.canvas == before)
    }

    @Test("Cut lifts the pixels and backfills with the background colour")
    func cutLiftsAndBackfills() throws {
        let engine = markedEngine()
        select(engine, PixelPoint(x: 5, y: 5), PixelPoint(x: 14, y: 14))
        engine.cutSelection()

        let floating = try #require(engine.floating)
        #expect(floating.bitmap.pixels.allSatisfy { $0 == PaintColour(hex: "FF0000")!.rgba8 })
        // The hole left behind is background, and the canvas itself does not
        // contain the floating content.
        #expect(engine.canvas.pixel(at: PixelPoint(x: 8, y: 8)) == .white)
    }

    @Test("Moving floating content and committing lands it in the new place")
    func moveAndCommit() {
        let engine = markedEngine()
        let red = PaintColour(hex: "FF0000")!.rgba8
        select(engine, PixelPoint(x: 5, y: 5), PixelPoint(x: 14, y: 14))
        engine.cutSelection()

        // Grab inside the floating content and drag it.
        engine.beginStroke(at: PixelPoint(x: 10, y: 10))
        engine.continueStroke(to: PixelPoint(x: 40, y: 40))
        engine.endStroke()
        engine.commitFloating()

        #expect(engine.canvas.pixel(at: PixelPoint(x: 8, y: 8)) == .white)   // vacated
        #expect(engine.canvas.pixel(at: PixelPoint(x: 38, y: 38)) == red)    // arrived
    }

    @Test("Floating content is not written until it is committed")
    func floatingIsNotOnCanvas() {
        let engine = PaintEngine(width: 40, height: 40)
        var stamp = Bitmap(width: 8, height: 8, fill: PaintColour(hex: "00FF00")!.rgba8)
        stamp.setPixel(.black, at: PixelPoint(x: 0, y: 0))

        engine.paste(stamp)
        #expect(engine.floating != nil)
        // Nothing on the canvas yet — that is what makes moving it free.
        #expect(engine.canvas.pixels.allSatisfy { $0 == .white })

        engine.commitFloating()
        #expect(engine.canvas.pixels.contains(PaintColour(hex: "00FF00")!.rgba8))
    }

    @Test("Paste centres the content on the canvas")
    func pasteIsCentred() throws {
        let engine = PaintEngine(width: 100, height: 100)
        engine.paste(Bitmap(width: 20, height: 20, fill: .black))
        let floating = try #require(engine.floating)
        #expect(floating.origin == PixelPoint(x: 40, y: 40))
    }

    @Test("Paste switches to the select tool so the content can be moved")
    func pasteSelectsMoveTool() {
        // Pasting and then being unable to move it because you are still on the
        // pencil is the single most annoying paste bug there is.
        let engine = PaintEngine(width: 40, height: 40)
        engine.settings.tool = .pencil
        engine.paste(Bitmap(width: 8, height: 8, fill: .black))
        #expect(engine.settings.tool == .select)
    }

    @Test("Committing a paste is one undoable step that fully reverts")
    func pasteUndoes() {
        let engine = PaintEngine(width: 40, height: 40)
        let pristine = engine.canvas
        engine.paste(Bitmap(width: 10, height: 10, fill: .black))
        engine.commitFloating()
        #expect(engine.canvas != pristine)

        engine.undo()
        #expect(engine.canvas == pristine)
    }

    @Test("Discarding floating content leaves no trace")
    func discardFloating() {
        let engine = PaintEngine(width: 40, height: 40)
        let pristine = engine.canvas
        engine.paste(Bitmap(width: 10, height: 10, fill: .black))
        engine.discardFloating()
        #expect(engine.floating == nil)
        #expect(engine.canvas == pristine)
    }

    @Test("Content pasted partly off-canvas clips instead of crashing")
    func pasteClips() {
        let engine = PaintEngine(width: 20, height: 20)
        engine.paste(Bitmap(width: 40, height: 40, fill: .black))
        engine.commitFloating()
        #expect(engine.canvas.pixels.allSatisfy { $0 == .black })
    }

    @Test("Starting to draw commits floating content rather than dropping it")
    func drawingCommitsFloating() {
        let engine = PaintEngine(width: 40, height: 40)
        engine.paste(Bitmap(width: 10, height: 10, fill: PaintColour(hex: "00FF00")!.rgba8))
        engine.settings.tool = .pencil
        engine.beginStroke(at: PixelPoint(x: 35, y: 35))
        engine.endStroke()

        #expect(engine.floating == nil)
        #expect(engine.canvas.pixels.contains(PaintColour(hex: "00FF00")!.rgba8))
    }

    @Test("Delete clears the selected region to the background colour")
    func deleteSelection() {
        let engine = markedEngine()
        select(engine, PixelPoint(x: 5, y: 5), PixelPoint(x: 14, y: 14))
        engine.colours.background = PaintColour(hex: "0000FF")!
        engine.deleteSelection()

        #expect(engine.canvas.pixel(at: PixelPoint(x: 8, y: 8)) == PaintColour(hex: "0000FF")!.rgba8)
        #expect(engine.selection == nil)
    }
}

@Suite("Pixelate redaction")
struct PixelateTests {

    /// Fine detail that must not survive redaction.
    private func detailedEngine() -> PaintEngine {
        let engine = PaintEngine(width: 60, height: 60)
        engine.settings.tool = .pencil
        engine.colours.foreground = .black
        for y in stride(from: 0, to: 60, by: 2) {
            engine.beginStroke(at: PixelPoint(x: 0, y: y))
            engine.endStroke(at: PixelPoint(x: 59, y: y))
        }
        return engine
    }

    @Test("Pixelating destroys the detail in its region")
    func detailIsDestroyed() {
        let engine = detailedEngine()
        engine.settings.tool = .pixelate
        engine.settings.pixelateBlockSize = 10
        engine.beginStroke(at: PixelPoint(x: 10, y: 10))
        engine.endStroke(at: PixelPoint(x: 39, y: 39))

        // Inside a block every pixel is now identical — the stripes are gone.
        let sample = engine.canvas.pixel(at: PixelPoint(x: 12, y: 12))
        let block = (10..<20).flatMap { y in
            (10..<20).map { x in engine.canvas.pixel(at: PixelPoint(x: x, y: y)) }
        }
        #expect(block.allSatisfy { $0 == sample }, "the block still carries detail")
    }

    @Test("Pixelating leaves everything outside the region untouched")
    func outsideIsUntouched() {
        let engine = detailedEngine()
        let before = engine.canvas
        engine.settings.tool = .pixelate
        engine.beginStroke(at: PixelPoint(x: 10, y: 10))
        engine.endStroke(at: PixelPoint(x: 39, y: 39))

        #expect(engine.canvas.pixel(at: PixelPoint(x: 50, y: 50)) == before.pixel(at: PixelPoint(x: 50, y: 50)))
        #expect(engine.canvas.pixel(at: PixelPoint(x: 5, y: 5)) == before.pixel(at: PixelPoint(x: 5, y: 5)))
    }

    @Test("Pixelate previews live without accumulating")
    func previewDoesNotAccumulate() {
        let engine = detailedEngine()
        engine.settings.tool = .pixelate
        engine.beginStroke(at: PixelPoint(x: 5, y: 5))
        engine.continueStroke(to: PixelPoint(x: 55, y: 55))
        engine.continueStroke(to: PixelPoint(x: 20, y: 20))
        engine.endStroke()

        // The abandoned large preview must leave nothing behind.
        let reference = detailedEngine().canvas
        #expect(engine.canvas.pixel(at: PixelPoint(x: 40, y: 40)) == reference.pixel(at: PixelPoint(x: 40, y: 40)))
    }

    @Test("Pixelate undoes as one step")
    func undoesAsOneStep() {
        let engine = detailedEngine()
        let before = engine.canvas
        engine.settings.tool = .pixelate
        engine.beginStroke(at: PixelPoint(x: 10, y: 10))
        engine.endStroke(at: PixelPoint(x: 39, y: 39))

        engine.undo()
        #expect(engine.canvas == before)
    }
}

/// The airbrush, which is now the brush's spray tip rather than its own tool.
@Suite("Spray tip")
struct AirbrushTests {

    private func sprayed(density: Double = 0.5, size: Int = 20) -> PaintEngine {
        let engine = PaintEngine(canvas: Bitmap(width: 80, height: 80, fill: .white))
        engine.settings.tool = .brush
        engine.settings.brushShape = .spray
        engine.settings.brushSize = size
        engine.settings.sprayDensity = density
        engine.colours.foreground = .black
        return engine
    }

    @Test("Spray lands inside the nib and nowhere else")
    func sprayStaysInsideItsFootprint() {
        let engine = sprayed()
        engine.beginStroke(at: PixelPoint(x: 40, y: 40))
        engine.endStroke()

        var marked = 0
        for y in 0..<80 {
            for x in 0..<80 where engine.canvas.pixel(at: PixelPoint(x: x, y: y)) != .white {
                marked += 1
                // 20px nib centred at (40,40): nothing may land beyond its radius.
                #expect(abs(x - 40) <= 11 && abs(y - 40) <= 11, "stray dot at \(x), \(y)")
            }
        }
        #expect(marked > 0, "the spray tip laid down nothing at all")
    }

    @Test("Holding still keeps building coverage")
    func lingeringBuildsDensity() {
        // This is the whole feel of the tool: a stamp that lands the same every
        // time is a brush, not an airbrush.
        let engine = sprayed(density: 0.15)
        engine.beginStroke(at: PixelPoint(x: 40, y: 40))
        let afterFirst = engine.canvas.pixels.filter { $0 != RGBA8.white }.count

        for _ in 0..<12 { engine.continueStroke(to: PixelPoint(x: 40, y: 40)) }
        let afterLingering = engine.canvas.pixels.filter { $0 != RGBA8.white }.count
        engine.endStroke()

        #expect(afterLingering > afterFirst)
    }

    @Test("A spray is one undoable stroke")
    func sprayUndoesAsOneStroke() {
        let engine = sprayed()
        let before = engine.canvas
        engine.beginStroke(at: PixelPoint(x: 30, y: 30))
        engine.continueStroke(to: PixelPoint(x: 50, y: 50))
        engine.endStroke()

        // Named for the tip, not the tool, the way a rectangle undoes as
        // "Rectangle" rather than "Shape".
        #expect(engine.undoStack.undoActionName == "Spray")
        engine.undo()
        #expect(engine.canvas == before)
    }

    @Test("The rail no longer carries a separate airbrush button")
    func airbrushIsNotATool() {
        #expect(!ToolKind.allCases.map(\.rawValue).contains("airbrush"))
        // Still reachable, as a tip.
        #expect(Brush.Shape.allCases.contains(.spray))
    }

    @Test("Only the brush sprays, however the tip is set")
    func onlyTheBrushSprays() {
        // The eraser, highlighter and shape tools all borrow `brushShape` for
        // their diameter. None of them may inherit its spray behaviour, and none
        // may end up with a spray-masked nib either.
        for tool in ToolKind.allCases {
            var settings = ToolSettings(tool: tool, brushShape: .spray)
            settings.brushSize = 12
            #expect(settings.isSpraying == (tool == .brush), "\(tool) disagreed")
            if tool != .brush {
                #expect(settings.nib.shape != .spray, "\(tool) kept a spray nib")
            }
        }
    }

    @Test("The same seed sprays the same dots")
    func sprayIsReproducible() {
        // Randomness that cannot be reproduced cannot be tested, and a tool
        // nobody can test is a tool that silently rots.
        func run() -> Bitmap {
            let engine = sprayed()
            engine.beginStroke(at: PixelPoint(x: 40, y: 40))
            engine.endStroke()
            return engine.canvas
        }
        #expect(run() == run())
    }
}

@Suite("Curve, polygon and badges")
struct MultiStepShapeTests {

    private func shapeEngine(_ kind: ShapeKind) -> PaintEngine {
        let engine = PaintEngine(canvas: Bitmap(width: 100, height: 100, fill: .white))
        engine.settings.tool = .shape
        engine.settings.shapeKind = kind
        engine.settings.brushSize = 2
        engine.colours.foreground = .black
        return engine
    }

    @Test("A curve is a chord first, then a bend, then one undo step")
    func curveIsTwoSteps() {
        let engine = shapeEngine(.curve)
        let pristine = engine.canvas

        engine.beginStroke(at: PixelPoint(x: 10, y: 50))
        engine.endStroke(at: PixelPoint(x: 90, y: 50))
        // The chord is drawn but not yet committed — it is still a preview.
        #expect(engine.hasPendingShape)
        #expect(!engine.canUndo)
        let chord = engine.canvas

        engine.beginStroke(at: PixelPoint(x: 50, y: 20))
        engine.continueStroke(to: PixelPoint(x: 50, y: 20))
        engine.endStroke(at: PixelPoint(x: 50, y: 20))

        #expect(!engine.hasPendingShape)
        #expect(engine.undoStack.undoActionName == "Curve")
        #expect(engine.canvas != chord, "the bend changed nothing")
        // The curve now passes near the point it was dragged to.
        #expect(engine.canvas.pixel(at: PixelPoint(x: 50, y: 20))?.a == 255)

        engine.undo()
        #expect(engine.canvas == pristine, "undo left part of the curve behind")
    }

    @Test("Escape throws away a half-built curve")
    func curveCancels() {
        let engine = shapeEngine(.curve)
        let pristine = engine.canvas
        engine.beginStroke(at: PixelPoint(x: 10, y: 50))
        engine.endStroke(at: PixelPoint(x: 90, y: 50))

        engine.cancelStroke()
        #expect(engine.canvas == pristine)
        #expect(!engine.hasPendingShape)
        #expect(!engine.canUndo)
    }

    @Test("A polygon closes when the first corner is clicked again")
    func polygonClosesOnItsFirstCorner() {
        let engine = shapeEngine(.polygon)
        engine.settings.shapeStyle = .filled
        engine.colours.background = PaintColour(hex: "FF0000")!

        for corner in [PixelPoint(x: 20, y: 20), PixelPoint(x: 80, y: 20), PixelPoint(x: 50, y: 80)] {
            engine.beginStroke(at: corner)
            engine.endStroke(at: corner)
        }
        #expect(engine.pendingPolygonCorners == 3)

        engine.beginStroke(at: PixelPoint(x: 21, y: 21))
        engine.endStroke(at: PixelPoint(x: 21, y: 21))

        #expect(!engine.hasPendingShape)
        #expect(engine.undoStack.undoActionName == "Polygon")
        // The interior is filled with the secondary colour, like every other
        // closed shape.
        #expect(engine.canvas.pixel(at: PixelPoint(x: 50, y: 40)) == PaintColour(hex: "FF0000")!.rgba8)
    }

    @Test("A stray click or two leaves no polygon behind")
    func polygonNeedsThreeCorners() {
        let engine = shapeEngine(.polygon)
        let pristine = engine.canvas
        engine.beginStroke(at: PixelPoint(x: 20, y: 20))
        engine.endStroke(at: PixelPoint(x: 20, y: 20))
        engine.closePolygon()

        #expect(engine.canvas == pristine)
        #expect(!engine.canUndo)
    }

    @Test("Badges number themselves, and keep counting")
    func badgesCountUp() {
        let engine = PaintEngine(canvas: Bitmap(width: 200, height: 100, fill: .white))
        engine.settings.tool = .badge
        engine.settings.brushSize = 10
        engine.colours.foreground = PaintColour(hex: "FF3B30")!

        #expect(engine.nextBadgeNumber == 1)
        engine.beginStroke(at: PixelPoint(x: 40, y: 50))
        #expect(engine.nextBadgeNumber == 2)
        engine.beginStroke(at: PixelPoint(x: 120, y: 50))
        #expect(engine.nextBadgeNumber == 3)

        // Each badge is its own undo step, named for what it dropped.
        #expect(engine.undoStack.undoActionName == "Badge 2")

        // A disc in the loaded colour, with a numeral in the contrasting one
        // painted inside it.
        let disc = PaintColour(hex: "FF3B30")!.rgba8
        let inside = (35..<45).flatMap { y in
            (35..<45).map { x in engine.canvas.pixel(at: PixelPoint(x: x, y: y)) }
        }
        #expect(inside.contains(disc), "no badge disc was drawn")
        #expect(inside.contains { $0 != disc && $0 != .white }, "the number never landed")

        engine.resetBadgeNumbering()
        #expect(engine.nextBadgeNumber == 1)
    }

    /// Undoing a badge has to hand its number back.
    ///
    /// The counter used to live outside the undo record, so `⌘Z` put the pixels
    /// back and left the sequence advanced: the badge vanished from the canvas
    /// and the next stamp came out as 4 anyway. What you could see and what the
    /// tool was about to continue no longer matched.
    @Test("Undo and redo carry the badge counter with them")
    func badgeCounterFollowsUndo() {
        let engine = PaintEngine(canvas: Bitmap(width: 300, height: 100, fill: .white))
        engine.settings.tool = .badge
        engine.settings.brushSize = 10
        engine.colours.foreground = PaintColour(hex: "FF3B30")!

        for x in [40, 120, 200] { engine.beginStroke(at: PixelPoint(x: x, y: 50)) }
        #expect(engine.nextBadgeNumber == 4)

        engine.undo()
        #expect(engine.nextBadgeNumber == 3, "undo did not hand back the number it used")
        engine.undo()
        #expect(engine.nextBadgeNumber == 2)

        engine.redo()
        #expect(engine.nextBadgeNumber == 3, "redo did not re-consume the number")

        // And a badge dropped after undoing reuses the freed number rather than
        // skipping to 4.
        engine.undo()
        engine.beginStroke(at: PixelPoint(x: 260, y: 50))
        #expect(engine.undoStack.undoActionName == "Badge 2")
        #expect(engine.nextBadgeNumber == 3)
    }

    @Test("Undoing a non-badge edit leaves the counter alone")
    func unrelatedUndoDoesNotDisturbTheCounter() {
        let engine = PaintEngine(canvas: Bitmap(width: 200, height: 100, fill: .white))
        engine.settings.tool = .badge
        engine.settings.brushSize = 10
        engine.beginStroke(at: PixelPoint(x: 40, y: 50))
        #expect(engine.nextBadgeNumber == 2)

        engine.settings.tool = .brush
        engine.beginStroke(at: PixelPoint(x: 150, y: 20))
        engine.continueStroke(to: PixelPoint(x: 180, y: 40))
        engine.endStroke()
        engine.undo()

        #expect(engine.nextBadgeNumber == 2, "a brush undo moved the badge counter")
    }

    @Test("Every drawn shape marks its own box and no more")
    func shapesStayInsideTheirBox() throws {
        for kind in ShapeKind.allCases where !kind.isMultiStep {
            let engine = shapeEngine(kind)
            engine.settings.shapeStyle = .outlineAndFill
            engine.beginStroke(at: PixelPoint(x: 20, y: 20))
            engine.endStroke(at: PixelPoint(x: 80, y: 80))

            let marked = (0..<100).flatMap { y in
                (0..<100).compactMap { x in
                    engine.canvas.pixel(at: PixelPoint(x: x, y: y)) == .white
                        ? nil : PixelPoint(x: x, y: y)
                }
            }
            #expect(!marked.isEmpty, "\(kind.displayName) drew nothing")
            // A couple of pixels of slack for the stroke's own width.
            for point in marked {
                #expect(
                    point.x >= 16 && point.x <= 84 && point.y >= 16 && point.y <= 84,
                    "\(kind.displayName) painted outside its box at \(point.x), \(point.y)"
                )
            }
        }
    }
}
