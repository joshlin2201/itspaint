import Testing
@testable import PaintKit

/// Lasso, crop and trim — the three that were previously stubbed or partial.
@Suite("Lasso — freeform selection")
struct LassoTests {

    /// A canvas with a red block covering exactly x/y 20...79.
    private func markedEngine() -> PaintEngine {
        let engine = PaintEngine(width: 100, height: 100)
        engine.settings.tool = .shape
        engine.settings.shapeKind = .rectangle
        engine.settings.shapeStyle = .filled
        engine.settings.brushSize = 1
        engine.colours.background = PaintColour(hex: "FF0000")!
        engine.beginStroke(at: PixelPoint(x: 19, y: 19))
        engine.endStroke(at: PixelPoint(x: 80, y: 80))
        engine.colours.background = .white
        return engine
    }

    /// Trace a triangle with the lasso: apex (50,20), base from (80,80) to
    /// (20,80). At y=30 it spans only x 45...55, so (25,30) is comfortably
    /// outside it while sitting well inside its bounding box.
    private func traceTriangle(_ engine: PaintEngine) {
        engine.settings.tool = .select
        engine.settings.selectionKind = .lasso
        engine.beginStroke(at: PixelPoint(x: 50, y: 20))
        for step in 1...30 {
            engine.continueStroke(to: PixelPoint(x: 50 + step, y: 20 + step * 2))
        }
        for step in 1...60 {
            engine.continueStroke(to: PixelPoint(x: 80 - step, y: 80))
        }
        engine.endStroke(at: PixelPoint(x: 50, y: 20))
    }

    @Test("A traced outline produces a mask, not a bounding box")
    func lassoProducesMask() throws {
        let engine = markedEngine()
        traceTriangle(engine)

        let selection = try #require(engine.selection)
        #expect(!selection.isRectangular, "lasso fell back to a rectangle")

        // Inside the triangle is selected; a bounding-box corner outside it is not.
        #expect(selection.coverage(at: PixelPoint(x: 55, y: 70)) > 0)
        #expect(selection.coverage(at: PixelPoint(x: 25, y: 30)) == 0)
    }

    @Test("A click with no drag selects nothing")
    func lassoNeedsAPath() {
        let engine = markedEngine()
        engine.settings.tool = .select
        engine.settings.selectionKind = .lasso
        engine.beginStroke(at: PixelPoint(x: 40, y: 40))
        engine.endStroke()
        #expect(engine.selection == nil)
    }

    @Test("The traced path is exposed so the ants can follow the real shape")
    func lassoPathIsAvailable() {
        let engine = markedEngine()
        traceTriangle(engine)
        #expect(engine.lassoPath.count > 10)
    }

    @Test("Copying a lasso yields the traced shape, not its bounding box")
    func copyRespectsMask() throws {
        // The whole point of a freeform tool. A bounding-box copy would paste a
        // rectangle of background around the shape.
        let engine = markedEngine()
        traceTriangle(engine)

        let content = try #require(engine.selectedContent())
        // A corner of the bounding box that the triangle does not cover must be
        // transparent, not background-coloured.
        // Bitmap (1,1) is canvas (21,21) — inside the bounding box, outside
        // the triangle.
        let corner = try #require(content.pixel(at: PixelPoint(x: 1, y: 1)))
        #expect(corner.a == 0, "outside the traced shape should be transparent")
        // And somewhere inside it is opaque.
        #expect(content.pixels.contains { $0.a == 255 })
    }

    @Test("Cutting a lasso clears only the traced shape")
    func cutRespectsMask() {
        let red = PaintColour(hex: "FF0000")!.rgba8
        let engine = markedEngine()
        traceTriangle(engine)
        engine.cutSelection()

        // Inside the triangle is vacated…
        #expect(engine.canvas.pixel(at: PixelPoint(x: 55, y: 70)) != red)
        // …but a bounding-box corner outside it still holds the original block.
        #expect(engine.canvas.pixel(at: PixelPoint(x: 25, y: 30)) == red)
    }

    @Test("Deleting a lasso clears only the traced shape")
    func deleteRespectsMask() {
        let red = PaintColour(hex: "FF0000")!.rgba8
        let engine = markedEngine()
        traceTriangle(engine)
        engine.colours.background = PaintColour(hex: "0000FF")!
        engine.deleteSelection()

        #expect(engine.canvas.pixel(at: PixelPoint(x: 55, y: 70)) == PaintColour(hex: "0000FF")!.rgba8)
        #expect(engine.canvas.pixel(at: PixelPoint(x: 25, y: 30)) == red)
    }

    @Test("Inverting colours inside a lasso leaves the rest alone")
    func invertRespectsMask() {
        let engine = markedEngine()
        let before = engine.canvas
        traceTriangle(engine)
        engine.invertColours()

        #expect(engine.canvas.pixel(at: PixelPoint(x: 55, y: 70)) != before.pixel(at: PixelPoint(x: 55, y: 70)))
        #expect(engine.canvas.pixel(at: PixelPoint(x: 25, y: 30)) == before.pixel(at: PixelPoint(x: 25, y: 30)))
    }

    @Test("Dragging inside a lasso lifts the traced shape")
    func autoLiftRespectsMask() throws {
        let engine = markedEngine()
        traceTriangle(engine)

        engine.beginStroke(at: PixelPoint(x: 55, y: 70))
        engine.continueStroke(to: PixelPoint(x: 60, y: 72))
        engine.endStroke()

        let floating = try #require(engine.floating)
        // The lifted content is the shape, so its corners are transparent.
        let corner = try #require(floating.bitmap.pixel(at: PixelPoint(x: 1, y: 1)))
        #expect(corner.a == 0)
    }

    @Test("A lasso cut is undoable")
    func lassoCutUndoes() {
        let engine = markedEngine()
        let before = engine.canvas
        traceTriangle(engine)
        engine.cutSelection()
        engine.undo()
        #expect(engine.canvas == before)
    }
}

@Suite("Crop")
struct CropTests {

    private func engineWithBlock() -> PaintEngine {
        let engine = PaintEngine(width: 100, height: 100)
        engine.settings.tool = .shape
        engine.settings.shapeKind = .rectangle
        engine.settings.shapeStyle = .filled
        engine.settings.brushSize = 1
        engine.colours.background = PaintColour(hex: "FF0000")!
        engine.beginStroke(at: PixelPoint(x: 19, y: 19))
        engine.endStroke(at: PixelPoint(x: 60, y: 60))
        engine.colours.background = .white
        return engine
    }

    @Test("Crop trims the canvas to a rectangular marquee")
    func cropToRectangle() {
        let engine = engineWithBlock()
        engine.settings.tool = .select
        engine.beginStroke(at: PixelPoint(x: 20, y: 20))
        engine.endStroke(at: PixelPoint(x: 49, y: 39))

        #expect(engine.cropToSelection())
        #expect(engine.canvas.width == 30 && engine.canvas.height == 20)
        #expect(engine.canvas.pixels.allSatisfy { $0 == PaintColour(hex: "FF0000")!.rgba8 })
        #expect(engine.selection == nil)
    }

    @Test("Cropping a lasso clears everything outside the traced shape")
    func cropToLasso() throws {
        // Cropping to a freeform shape has to mean the shape, not the box
        // around it, or the tool is a rectangle wearing a costume.
        let engine = engineWithBlock()
        engine.settings.tool = .select
        engine.settings.selectionKind = .lasso
        engine.beginStroke(at: PixelPoint(x: 25, y: 25))
        engine.continueStroke(to: PixelPoint(x: 55, y: 25))
        engine.continueStroke(to: PixelPoint(x: 55, y: 55))
        engine.endStroke(at: PixelPoint(x: 25, y: 25))

        #expect(engine.cropToSelection())
        // The lower-left of the new canvas is outside the triangle → transparent.
        let outside = try #require(engine.canvas.pixel(at: PixelPoint(x: 2, y: engine.canvas.height - 3)))
        #expect(outside.a == 0)
        // And inside it survives.
        #expect(engine.canvas.pixels.contains { $0.a == 255 })
    }

    @Test("Crop with no selection is refused rather than clearing the canvas")
    func cropNeedsSelection() {
        let engine = engineWithBlock()
        let before = engine.canvas
        #expect(!engine.cropToSelection())
        #expect(engine.canvas == before)
    }

    @Test("Cropping to the whole canvas is a no-op")
    func cropToEverything() {
        let engine = engineWithBlock()
        engine.selectAll()
        #expect(!engine.cropToSelection())
        #expect(engine.canvas.width == 100)
    }
}

@Suite("Trim borders")
struct TrimTests {

    /// Content inset inside a solid border, the screenshot case.
    private func borderedEngine(border: PaintColour, jitter: Bool = false) -> PaintEngine {
        let engine = PaintEngine(canvas: Bitmap(width: 100, height: 80, fill: border.rgba8))
        engine.settings.tool = .shape
        engine.settings.shapeKind = .rectangle
        engine.settings.shapeStyle = .filled
        engine.settings.brushSize = 1
        engine.colours.background = PaintColour(hex: "3366CC")!
        engine.beginStroke(at: PixelPoint(x: 19, y: 14))
        engine.endStroke(at: PixelPoint(x: 80, y: 65))
        return engine
    }

    @Test("Trim removes a solid border and keeps the content")
    func trimsSolidBorder() {
        let engine = borderedEngine(border: .white)
        #expect(engine.trimBorders())
        #expect(engine.canvas.width < 100 && engine.canvas.height < 80)
        // Every remaining pixel is content, not border.
        #expect(engine.canvas.pixels.allSatisfy { $0 == PaintColour(hex: "3366CC")!.rgba8 })
    }

    @Test("Trim tolerates a near-uniform border")
    func trimsNearUniformBorder() {
        // A screenshot's "solid" border is rarely one exact colour after a lossy
        // round trip. Zero tolerance silently does nothing on exactly the images
        // people most want to trim.
        var canvas = Bitmap(width: 80, height: 60, fill: RGBA8(r: 250, g: 250, b: 250))
        canvas.setPixel(RGBA8(r: 247, g: 251, b: 249), at: PixelPoint(x: 3, y: 2))
        canvas.setPixel(RGBA8(r: 253, g: 248, b: 250), at: PixelPoint(x: 70, y: 5))
        let engine = PaintEngine(canvas: canvas)
        engine.settings.tool = .shape
        engine.settings.shapeKind = .rectangle
        engine.settings.shapeStyle = .filled
        engine.settings.brushSize = 1
        engine.colours.background = .black
        engine.beginStroke(at: PixelPoint(x: 19, y: 14))
        engine.endStroke(at: PixelPoint(x: 60, y: 45))

        #expect(engine.trimBorders(tolerance: 8))
        #expect(engine.canvas.width < 80)
    }

    @Test("Trim is refused on an image with no border")
    func refusesWhenNothingToTrim() {
        var canvas = Bitmap(width: 40, height: 40, fill: .white)
        canvas.setPixel(.black, at: PixelPoint(x: 0, y: 0))
        canvas.setPixel(.black, at: PixelPoint(x: 39, y: 39))
        let engine = PaintEngine(canvas: canvas)
        let before = engine.canvas
        #expect(!engine.trimBorders())
        #expect(engine.canvas == before)
    }

    @Test("Trim is refused on a blank canvas rather than erasing it")
    func refusesOnBlankCanvas() {
        // Trimming everything away would leave nothing, which is never what the
        // user meant.
        let engine = PaintEngine(canvas: Bitmap(width: 50, height: 50, fill: .white))
        #expect(!engine.trimBorders())
        #expect(engine.canvas.width == 50)
    }

    @Test("Trim clears history because coordinates no longer line up")
    func trimClearsHistory() {
        let engine = borderedEngine(border: .white)
        #expect(engine.canUndo)
        _ = engine.trimBorders()
        // Undo patches are addressed in canvas coordinates; keeping them across
        // a resize would restore pixels into the wrong places.
        #expect(!engine.canUndo)
    }
}

@Suite("Text tool")
struct TextToolTests {

    private func engine() -> PaintEngine {
        let engine = PaintEngine(canvas: Bitmap(width: 200, height: 80, fill: .white))
        engine.settings.tool = .text
        return engine
    }

    @Test("Text marks pixels inside its box and nothing outside it")
    func textLands() {
        let engine = engine()
        let box = PixelRect(x: 10, y: 10, width: 160, height: 50)
        let dirty = engine.drawText("Hello", in: box, style: .init(pointSize: 36, colour: .black))

        #expect(!dirty.isEmpty)
        #expect(engine.canvas.pixels.contains { $0 != RGBA8.white })
        // Outside the box the canvas is untouched.
        for point in [PixelPoint(x: 2, y: 2), PixelPoint(x: 195, y: 75)] {
            #expect(engine.canvas.pixel(at: point) == .white)
        }
    }

    @Test("Text is one undoable edit, named for the Edit menu")
    func textUndoes() {
        let engine = engine()
        let before = engine.canvas
        engine.drawText("Hello", in: PixelRect(x: 4, y: 4, width: 180, height: 60), style: .init())

        #expect(engine.undoStack.undoActionName == "Text")
        engine.undo()
        #expect(engine.canvas == before)
    }

    @Test("An empty string draws nothing rather than an empty undo step")
    func emptyTextIsNotAnEdit() {
        let engine = engine()
        let dirty = engine.drawText("", in: PixelRect(x: 4, y: 4, width: 40, height: 20), style: .init())
        #expect(dirty.isEmpty)
        #expect(!engine.canUndo)
    }

    @Test("The text tool never draws the current shape")
    func textDoesNotDrawShapes() {
        // It used to fall through to the shape gesture, so selecting T and
        // dragging quietly drew a rectangle.
        let engine = engine()
        let before = engine.canvas
        engine.settings.shapeKind = .rectangle
        engine.settings.shapeStyle = .filled
        engine.beginStroke(at: PixelPoint(x: 10, y: 10))
        engine.continueStroke(to: PixelPoint(x: 90, y: 60))
        engine.endStroke(at: PixelPoint(x: 90, y: 60))

        #expect(engine.canvas == before)
        #expect(!engine.canUndo)
    }
}

@Suite("Masked extraction")
struct MaskedExtractionTests {

    @Test("A masked selection hanging off the canvas extracts the right rows")
    func maskedExtractHonoursClipping() throws {
        // The extract is clipped to the canvas while the mask is addressed in
        // the selection's own space; without the offset every row after the
        // first reads from the wrong place.
        var canvas = Bitmap(width: 20, height: 20, fill: .white)
        canvas.fill(PixelRect(x: 0, y: 0, width: 20, height: 10), with: RGBA8(r: 255, g: 0, b: 0))

        // A 10×10 selection whose left half is off-canvas, masked to its own
        // right half — the pixels that actually exist.
        let bounds = PixelRect(x: -5, y: 0, width: 10, height: 10)
        var mask = [UInt8](repeating: 0, count: bounds.width * bounds.height)
        for row in 0..<bounds.height {
            for column in 5..<bounds.width {
                mask[row * bounds.width + column] = 255
            }
        }
        let selection = Selection(bounds: bounds, mask: mask)
        let extracted = try #require(canvas.extract(selection))

        // Every pixel that survived must be the red the canvas actually holds.
        #expect(extracted.pixels.contains { $0.a > 0 })
        #expect(extracted.pixels.allSatisfy { $0.a == 0 || $0 == RGBA8(r: 255, g: 0, b: 0) })
    }
}

@Suite("Selection kinds")
struct SelectionKindTests {

    private func engine() -> PaintEngine {
        let engine = PaintEngine(canvas: Bitmap(width: 100, height: 100, fill: .white))
        engine.settings.tool = .select
        return engine
    }

    @Test("An elliptical marquee selects an ellipse, not its box")
    func ellipseSelectsAnEllipse() throws {
        let engine = engine()
        engine.settings.selectionKind = .ellipse
        engine.beginStroke(at: PixelPoint(x: 20, y: 20))
        engine.endStroke(at: PixelPoint(x: 79, y: 79))

        let selection = try #require(engine.selection)
        #expect(!selection.isRectangular, "an ellipse came back as a plain rectangle")
        // Centre in, corners out — the difference between an ellipse and its box.
        #expect(selection.contains(PixelPoint(x: 50, y: 50)))
        #expect(!selection.contains(PixelPoint(x: 21, y: 21)))
        #expect(!selection.contains(PixelPoint(x: 78, y: 78)))
    }

    @Test("The rectangular marquee stays a plain rectangle")
    func rectangleHasNoMask() throws {
        let engine = engine()
        engine.settings.selectionKind = .rectangle
        engine.beginStroke(at: PixelPoint(x: 10, y: 10))
        engine.endStroke(at: PixelPoint(x: 60, y: 40))

        let selection = try #require(engine.selection)
        #expect(selection.isRectangular)
        #expect(selection.bounds.width == 51 && selection.bounds.height == 31)
    }

    @Test("The lasso is a kind of selection, not a tool of its own")
    func lassoIsASelectionKind() throws {
        let engine = engine()
        engine.settings.selectionKind = .lasso
        engine.beginStroke(at: PixelPoint(x: 20, y: 20))
        engine.continueStroke(to: PixelPoint(x: 70, y: 20))
        engine.continueStroke(to: PixelPoint(x: 70, y: 70))
        engine.endStroke(at: PixelPoint(x: 20, y: 20))

        let selection = try #require(engine.selection)
        #expect(!selection.isRectangular)
        #expect(engine.lassoPath.count > 2)
        // And the tool set no longer carries a separate lasso button.
        #expect(!ToolKind.allCases.map(\.rawValue).contains("lasso"))
    }
}

@Suite("Stroke styles")
struct StrokeDashTests {

    @Test("A dashed line leaves gaps a solid one does not")
    func dashedLeavesGaps() {
        func drawn(_ dash: Raster.Dash) -> Int {
            var canvas = Bitmap(width: 120, height: 20, fill: .white)
            Raster.strokeLine(
                from: PixelPoint(x: 2, y: 10), to: PixelPoint(x: 117, y: 10),
                brush: Brush(shape: .square, size: 2), colour: .black,
                into: &canvas, dash: dash
            )
            return canvas.pixels.filter { $0 == RGBA8.black }.count
        }

        let solid = drawn(.solid)
        #expect(drawn(.dashed) < solid, "dashed marked as many pixels as solid")
        #expect(drawn(.dotted) < drawn(.dashed), "dotted is not sparser than dashed")
        #expect(drawn(.dotted) > 0, "dotted drew nothing at all")
    }

    @Test("A dashed line lands on the same pixels a solid one uses")
    func dashedIsASubsetOfSolid() {
        var solid = Bitmap(width: 80, height: 40, fill: .white)
        var dashed = solid
        let brush = Brush(shape: .square, size: 1)
        let a = PixelPoint(x: 4, y: 4), b = PixelPoint(x: 74, y: 34)
        Raster.strokeLine(from: a, to: b, brush: brush, colour: .black, into: &solid)
        Raster.strokeLine(from: a, to: b, brush: brush, colour: .black, into: &dashed, dash: .dashed)

        for index in 0..<solid.pixels.count where dashed.pixels[index] == RGBA8.black {
            #expect(solid.pixels[index] == RGBA8.black, "a dash landed off the line at \(index)")
        }
    }
}
