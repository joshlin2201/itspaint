import Testing
@testable import PaintKit

@Suite("Retained text")
struct RetainedTextTests {
    private func object(_ text: String = "Edit me") -> TextObject {
        TextObject(
            frame: PixelRect(x: 8, y: 8, width: 120, height: 42),
            runs: [TextRun(text: text, style: .init(pointSize: 24, colour: .black))]
        )
    }

    @Test("Retained text renders without mutating the base bitmap")
    func textRendersSeparately() {
        let engine = PaintEngine(canvas: Bitmap(width: 160, height: 70, fill: .white))
        let text = object()

        _ = engine.upsertTextObject(text)

        #expect(engine.canvas.pixels.allSatisfy { $0 == .white })
        #expect(engine.renderedCanvas().pixels.contains { $0 != .white })
        #expect(engine.textObjects == [text])
    }

    @Test("A live text session is one reversible edit")
    func liveTextUndoRedo() {
        let engine = PaintEngine(canvas: Bitmap(width: 160, height: 70, fill: .white))
        let before = engine.textObjects
        let text = object()

        _ = engine.upsertTextObject(text, registerUndo: false)
        let dirty = engine.recordTextEdit(from: before)
        #expect(engine.undoStack.undoActionName == "Text")
        #expect(dirty == text.frame)

        #expect(engine.undo() == text.frame)
        #expect(engine.textObjects.isEmpty)
        engine.redo()
        #expect(engine.textObjects == [text])
    }

    @Test("A raster edit bakes text and undo restores it")
    func rasterEditRestoresTextOnUndo() {
        let engine = PaintEngine(canvas: Bitmap(width: 160, height: 70, fill: .white))
        let text = object()
        _ = engine.upsertTextObject(text, registerUndo: false)
        let before = engine.canvas

        _ = engine.clearCanvas()
        #expect(engine.textObjects.isEmpty)
        #expect(engine.renderedCanvas().pixels.allSatisfy { $0 == .white })

        engine.undo()
        #expect(engine.canvas == before)
        #expect(engine.textObjects == [text])
    }

    @Test("Text history accounts for run payload and selection lifts visible text")
    func textHistoryAndSelectionUseRenderedContent() {
        let engine = PaintEngine(canvas: Bitmap(width: 200, height: 80, fill: .white))
        let before = engine.textObjects
        let text = object(String(repeating: "x", count: 8_192))
        _ = engine.upsertTextObject(text, registerUndo: false)
        _ = engine.recordTextEdit(from: before)
        #expect(engine.undoStack.byteCount >= 8_192)

        engine.selectAll()
        let content = try! #require(engine.selectedContent())
        #expect(content.pixels.contains { $0 != .white })
        _ = engine.cutSelection()
        #expect(engine.textObjects.isEmpty)
        engine.undo()
        #expect(engine.textObjects == [text])
    }

    @Test("Highlighter and shape preserve baked text through undo")
    func rasterGesturesKeepTextPixelsAndUndoObjects() {
        let engine = PaintEngine(canvas: Bitmap(width: 180, height: 90, fill: .white))
        let text = object()
        _ = engine.upsertTextObject(text, registerUndo: false)

        engine.settings.tool = .highlighter
        _ = engine.beginStroke(at: PixelPoint(x: 12, y: 20))
        _ = engine.endStroke(at: PixelPoint(x: 72, y: 20))
        #expect(engine.textObjects.isEmpty)
        #expect(engine.canvas.pixels.contains { $0 != .white })
        engine.undo()
        #expect(engine.canvas.pixels.allSatisfy { $0 == .white })
        #expect(engine.textObjects == [text])

        engine.settings.tool = .shape
        engine.settings.shapeKind = .rectangle
        _ = engine.beginStroke(at: PixelPoint(x: 4, y: 4))
        _ = engine.continueStroke(to: PixelPoint(x: 120, y: 52))
        _ = engine.endStroke(at: PixelPoint(x: 120, y: 52))
        #expect(engine.textObjects.isEmpty)
        #expect(engine.canvas.pixels.contains { $0 != .white })
        engine.undo()
        #expect(engine.textObjects == [text])
    }

    @Test("Cancelling a raster gesture restores the base and text objects")
    func cancelRestoresRetainedText() {
        let engine = PaintEngine(canvas: Bitmap(width: 160, height: 70, fill: .white))
        let text = object()
        _ = engine.upsertTextObject(text, registerUndo: false)
        engine.settings.tool = .brush
        _ = engine.beginStroke(at: PixelPoint(x: 12, y: 18))

        _ = engine.cancelStroke()
        #expect(engine.canvas.pixels.allSatisfy { $0 == .white })
        #expect(engine.textObjects == [text])
        #expect(!engine.canUndo)
    }

    @Test("A disjoint pencil stroke keeps text editable while overlap bakes it")
    func rasterGestureKeepsOnlyDisjointTextRetained() {
        let engine = PaintEngine(canvas: Bitmap(width: 220, height: 100, fill: .white))
        let text = object()
        _ = engine.upsertTextObject(text, registerUndo: false)
        engine.settings.tool = .pencil

        _ = engine.beginStroke(at: PixelPoint(x: 190, y: 82))
        _ = engine.endStroke(at: PixelPoint(x: 190, y: 82))
        #expect(engine.textObjects == [text])
        #expect(engine.renderedCanvas().pixels.contains { $0 != .white })

        _ = engine.beginStroke(at: PixelPoint(x: 12, y: 20))
        _ = engine.endStroke(at: PixelPoint(x: 12, y: 20))
        #expect(engine.textObjects.isEmpty)
        engine.undo()
        #expect(engine.textObjects == [text])
    }

    @Test("Aiming the clone tool leaves text editable and records nothing")
    func cloneAimKeepsTextEditable() {
        let engine = PaintEngine(canvas: Bitmap(width: 160, height: 70, fill: .white))
        let text = object()
        _ = engine.upsertTextObject(text, registerUndo: false)
        engine.settings.tool = .clone

        // No source yet, so this click only aims. It must not bake the text it
        // flattened for a stroke that never comes.
        _ = engine.beginStroke(at: PixelPoint(x: 150, y: 60))
        _ = engine.endStroke(at: PixelPoint(x: 150, y: 60))
        #expect(engine.textObjects == [text])
        #expect(engine.canvas.pixels.allSatisfy { $0 == .white })
        #expect(!engine.canUndo)
    }

    @Test("A polygon over a text box keeps the letters it does not cover")
    func polygonKeepsBakedLetters() {
        let engine = PaintEngine(canvas: Bitmap(width: 200, height: 80, fill: .white))
        let text = object()
        _ = engine.upsertTextObject(text, registerUndo: false)
        // The same polygon on a canvas whose letters are already plain pixels is
        // the answer: baking the text first must be indistinguishable from it.
        let reference = PaintEngine(canvas: engine.renderedCanvas())
        let corners = [PixelPoint(x: 16, y: 14), PixelPoint(x: 70, y: 14), PixelPoint(x: 43, y: 40)]
        for target in [engine, reference] {
            target.settings.tool = .shape
            target.settings.shapeKind = .polygon
            for corner in corners {
                // The rubber band sweeps across the letters between clicks, the
                // way the pointer does, and each redraw restores what it covered.
                _ = target.previewPolygon(to: PixelPoint(x: 120, y: 70))
                _ = target.beginStroke(at: corner)
                _ = target.endStroke(at: corner)
            }
            _ = target.closePolygon()
        }

        #expect(engine.textObjects.isEmpty)
        #expect(engine.canvas == reference.canvas)
        engine.undo()
        #expect(engine.textObjects == [text])
        #expect(engine.canvas.pixels.allSatisfy { $0 == .white })
    }

    @Test("Loading a document while a curve's chord is pending keeps the loaded text")
    func resetForgetsPendingChordText() {
        let engine = PaintEngine(canvas: Bitmap(width: 200, height: 80, fill: .white))
        _ = engine.upsertTextObject(object("Old"), registerUndo: false)
        engine.settings.tool = .shape
        engine.settings.shapeKind = .curve
        _ = engine.beginStroke(at: PixelPoint(x: 150, y: 10))
        _ = engine.endStroke(at: PixelPoint(x: 190, y: 70))

        let loaded = object("Loaded")
        engine.reset(to: Bitmap(width: 200, height: 80, fill: .white), textObjects: [loaded])
        engine.settings.tool = .pencil
        _ = engine.beginStroke(at: PixelPoint(x: 12, y: 20))
        _ = engine.endStroke(at: PixelPoint(x: 12, y: 20))

        // The stroke overlaps the loaded box, so it bakes; Undo has to bring
        // back the loaded box, not the one from before the reset.
        #expect(engine.textObjects.isEmpty)
        engine.undo()
        #expect(engine.textObjects == [loaded])
    }

    @Test("Adding text while a chord is pending keeps the new box")
    func upsertLandsPendingChord() {
        let engine = PaintEngine(canvas: Bitmap(width: 200, height: 80, fill: .white))
        _ = engine.upsertTextObject(object("A"), registerUndo: false)
        engine.settings.tool = .shape
        engine.settings.shapeKind = .curve
        _ = engine.beginStroke(at: PixelPoint(x: 150, y: 10))
        _ = engine.endStroke(at: PixelPoint(x: 190, y: 70))

        let added = TextObject(
            frame: PixelRect(x: 140, y: 40, width: 50, height: 30),
            runs: [TextRun(text: "B", style: .init(pointSize: 18))]
        )
        _ = engine.upsertTextObject(added, registerUndo: false)
        _ = engine.commitPendingShape()
        #expect(engine.textObjects.contains(added))
    }

    @Test("Placing a paste off the top-left moves text boxes with the artwork")
    func growingCanvasMovesText() {
        let engine = PaintEngine(canvas: Bitmap(width: 160, height: 70, fill: .white))
        let text = object()
        _ = engine.upsertTextObject(text, registerUndo: false)

        engine.paste(Bitmap(width: 20, height: 20, fill: PaintColour(hex: "FF0000")!.rgba8))
        engine.moveFloating(to: PixelPoint(x: -30, y: -10))
        engine.commitFloating()

        #expect(engine.canvas.width == 190)
        #expect(engine.canvas.height == 80)
        #expect(engine.textObjects.map(\.frame) == [PixelRect(x: 38, y: 18, width: 120, height: 42)])
        engine.undo()
        #expect(engine.canvas.width == 160)
        #expect(engine.textObjects == [text])
        engine.redo()
        #expect(engine.textObjects.map(\.frame) == [PixelRect(x: 38, y: 18, width: 120, height: 42)])
    }

    @Test("Remove Background treats text over the page as subject")
    func removeBackgroundKeepsText() {
        var canvas = Bitmap(width: 200, height: 80, fill: .white)
        Raster.fillRect(
            PixelRect(x: 150, y: 20, width: 30, height: 30),
            colour: RGBA8(r: 200, g: 30, b: 30), into: &canvas
        )
        let engine = PaintEngine(canvas: canvas)
        _ = engine.upsertTextObject(object(), registerUndo: false)

        #expect(engine.removeBackground())
        let letters = engine.canvas.extract(PixelRect(x: 8, y: 8, width: 120, height: 42)).pixels
        #expect(letters.contains { $0.a == 255 && $0.r < 80 }, "the letters were keyed out with the page")
    }

    @Test("The eyedropper picks up the colour of text it is over")
    func eyedropperSeesText() {
        let engine = PaintEngine(canvas: Bitmap(width: 160, height: 70, fill: .white))
        let red = PaintColour(red: 1, green: 0, blue: 0)
        let block = TextObject(
            frame: PixelRect(x: 8, y: 8, width: 120, height: 60),
            runs: [TextRun(text: "█", style: .init(pointSize: 48, colour: red, haloColour: nil))]
        )
        _ = engine.upsertTextObject(block, registerUndo: false)
        let inside = engine.renderedCanvas().pixels.indices.first {
            engine.renderedCanvas().pixels[$0] == red.rgba8
        }
        let index = try! #require(inside)
        engine.settings.tool = .eyedropper
        _ = engine.beginStroke(at: PixelPoint(x: index % 160, y: index / 160))
        #expect(engine.colours.foreground.rgba8 == red.rgba8)
    }
}

@Suite("Styled runs")
struct StyledRunTests {
    private func width(of text: String, _ style: TextRenderer.Style) -> Int {
        TextRenderer.measure([TextRun(text: text, style: style)], maxWidth: 1_000).width
    }

    @Test("A transparent run cuts out while its neighbour paints")
    func mixedEraseAndPaint() {
        var bitmap = Bitmap(width: 300, height: 60, fill: RGBA8(r: 200, g: 200, b: 255))
        let ink = TextRenderer.Style(pointSize: 36, colour: .black, haloColour: nil)
        var hole = ink
        hole.colour = .clear
        let split = width(of: "WWW", ink)

        TextRenderer.draw(
            [TextRun(text: "WWW", style: ink), TextRun(text: "WWW", style: hole)],
            in: PixelRect(x: 0, y: 0, width: 300, height: 60), into: &bitmap
        )

        let left = (0..<60).flatMap { y in (0..<split - 2).map { bitmap.pixels[y * 300 + $0] } }
        let right = (0..<60).flatMap { y in (split + 2..<300).map { bitmap.pixels[y * 300 + $0] } }
        #expect(left.contains { $0.a == 255 && $0.b < 60 }, "the painted run drew nothing")
        #expect(!left.contains { $0.a == 0 }, "the painted run cut a hole")
        #expect(right.contains { $0.a == 0 }, "the transparent run did not cut out")
        #expect(!right.contains { $0.a == 255 && $0.b < 60 }, "the transparent run painted ink")
    }

    @Test("Each run keeps or drops its own rim")
    func haloIsPerRun() {
        var bitmap = Bitmap(width: 300, height: 60, fill: RGBA8(r: 0, g: 0, b: 0))
        let rimmed = TextRenderer.Style(pointSize: 36, colour: .black, haloColour: .white)
        var plain = rimmed
        plain.haloColour = nil
        let split = width(of: "Rim", rimmed)

        TextRenderer.draw(
            [TextRun(text: "Rim", style: rimmed), TextRun(text: "Rim", style: plain)],
            in: PixelRect(x: 0, y: 0, width: 300, height: 60), into: &bitmap
        )

        let light: (RGBA8) -> Bool = { $0.r > 128 }
        let left = (0..<60).flatMap { y in (0..<split - 2).map { bitmap.pixels[y * 300 + $0] } }
        let right = (0..<60).flatMap { y in (split + 4..<300).map { bitmap.pixels[y * 300 + $0] } }
        #expect(left.contains(where: light), "the rimmed run has no rim")
        #expect(!right.contains(where: light), "the plain run borrowed its neighbour's rim")
    }
}
