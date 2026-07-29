import Testing
@testable import PaintKit

@Suite("Floating selection — move, resize, handles")
struct FloatingSelectionTests {

    private func floating(width: Int = 40, height: Int = 30) -> FloatingSelection {
        FloatingSelection(
            bitmap: Bitmap(width: width, height: height, fill: .black),
            origin: PixelPoint(x: 100, y: 100)
        )
    }

    @Test("Moving does not resample the content")
    func moveDoesNotResample() {
        var selection = floating()
        let before = selection.rendered
        selection.move(to: PixelPoint(x: 5, y: 7))
        #expect(selection.frame.minX == 5 && selection.frame.minY == 7)
        #expect(selection.rendered == before)
        #expect(selection.frame.width == 40 && selection.frame.height == 30)
    }

    @Test("Resizing re-renders at the new size")
    func resizeRenders() {
        var selection = floating()
        selection.resize(to: PixelRect(x: 100, y: 100, width: 80, height: 60))
        #expect(selection.rendered.width == 80)
        #expect(selection.rendered.height == 60)
        // The original is retained so later resizes resample from it.
        #expect(selection.original.width == 40)
    }

    @Test("Scaling down and back up resamples from the original, not the copy")
    func resizeIsNotCumulative() {
        // Re-rendering from `rendered` each time would compound blur; a few
        // round trips would visibly destroy the content.
        var selection = floating(width: 64, height: 64)
        let originalPixels = selection.original.pixels

        for size in [8, 64, 6, 64, 12, 64] {
            selection.resize(to: PixelRect(x: 0, y: 0, width: size, height: size))
        }
        #expect(selection.original.pixels == originalPixels)
        #expect(selection.rendered.width == 64)
        #expect(selection.rendered.pixels.allSatisfy { $0 == .black })
    }

    @Test("Resizing never collapses to zero")
    func resizeClamps() {
        var selection = floating()
        selection.resize(to: PixelRect(x: 10, y: 10, width: 0, height: 0))
        #expect(selection.frame.width >= 1 && selection.frame.height >= 1)
    }

    @Test("Every handle is hit at its own corner or edge")
    func handlesAreReachable() {
        let selection = floating(width: 60, height: 60)
        for (handle, centre) in selection.handleCentres() {
            #expect(selection.handle(at: centre, tolerance: 5) == handle,
                    "\(handle) not hit at its own centre")
        }
    }

    @Test("Handles never swallow a small selection")
    func handlesDoNotSwallowSmallContent() {
        // Regression guard: with an uncapped tolerance the handles of a 10×10
        // selection overlap in the middle, every click grabs a handle, and the
        // content can be resized but never moved.
        let selection = FloatingSelection(
            bitmap: Bitmap(width: 10, height: 10, fill: .black),
            origin: PixelPoint(x: 5, y: 5)
        )
        #expect(selection.handle(at: PixelPoint(x: 10, y: 10), tolerance: 5) == nil)
        #expect(selection.contains(PixelPoint(x: 10, y: 10)))
    }

    @Test("A point well inside a large selection is not a handle")
    func interiorIsNotAHandle() {
        let selection = floating(width: 200, height: 200)
        #expect(selection.handle(at: PixelPoint(x: 200, y: 200), tolerance: 6) == nil)
    }

    @Test("Dragging a corner handle moves only its own edges")
    func cornerDragMovesTwoEdges() {
        let selection = floating(width: 40, height: 30)  // at (100,100)
        let result = selection.frame(
            draggingHandle: .bottomRight, to: PixelPoint(x: 200, y: 180), uniform: false
        )
        #expect(result.minX == 100 && result.minY == 100)   // anchored corner
        #expect(result.maxX == 201 && result.maxY == 181)
    }

    @Test("Dragging an edge handle moves only that edge")
    func edgeDragMovesOneEdge() {
        let selection = floating(width: 40, height: 30)
        let result = selection.frame(
            draggingHandle: .right, to: PixelPoint(x: 200, y: 999), uniform: false
        )
        #expect(result.minY == 100 && result.height == 30)  // vertical untouched
        #expect(result.maxX == 201)
    }

    @Test("Edges cannot cross — dragging past the opposite side keeps a sliver")
    func edgesCannotInvert() {
        let selection = floating(width: 40, height: 30)     // x 100..140
        let result = selection.frame(
            draggingHandle: .left, to: PixelPoint(x: 999, y: 110), uniform: false
        )
        #expect(result.width >= 1)
        #expect(result.minX < result.maxX)
    }

    @Test("Uniform resize preserves the aspect ratio")
    func uniformResizeKeepsAspect() {
        let selection = floating(width: 40, height: 20)     // 2:1
        let result = selection.frame(
            draggingHandle: .bottomRight, to: PixelPoint(x: 220, y: 105), uniform: true
        )
        let aspect = Double(result.width) / Double(result.height)
        #expect(abs(aspect - 2.0) < 0.1, "aspect drifted to \(aspect)")
    }

    @Test("Dragging a top-left handle anchors the opposite corner")
    func topLeftAnchorsBottomRight() {
        let selection = floating(width: 40, height: 30)     // (100,100)-(140,130)
        let result = selection.frame(
            draggingHandle: .topLeft, to: PixelPoint(x: 80, y: 90), uniform: false
        )
        #expect(result.maxX == 140 && result.maxY == 130)
        #expect(result.minX == 80 && result.minY == 90)
    }
}

@Suite("Selection interaction")
struct SelectionInteractionTests {

    private func markedEngine() -> PaintEngine {
        let engine = PaintEngine(width: 120, height: 120)
        engine.settings.tool = .shape
        engine.settings.shapeKind = .rectangle
        engine.settings.shapeStyle = .filled
        engine.settings.brushSize = 1
        engine.colours.background = PaintColour(hex: "FF0000")!
        engine.beginStroke(at: PixelPoint(x: 19, y: 19))
        engine.endStroke(at: PixelPoint(x: 71, y: 71))
        engine.colours.background = .white
        return engine
    }

    @Test("Dragging inside a marquee lifts and moves it with no separate Cut")
    func dragInsideMarqueeAutoLifts() {
        // Requiring an explicit Cut first is the classic reason people conclude
        // a selection "doesn't do anything".
        let engine = markedEngine()
        let red = PaintColour(hex: "FF0000")!.rgba8

        engine.settings.tool = .select
        engine.beginStroke(at: PixelPoint(x: 20, y: 20))
        engine.endStroke(at: PixelPoint(x: 60, y: 60))
        #expect(engine.selection != nil)

        // Now drag from inside it — no cutSelection() call anywhere.
        engine.beginStroke(at: PixelPoint(x: 40, y: 40))
        engine.continueStroke(to: PixelPoint(x: 90, y: 90))
        engine.endStroke()
        #expect(engine.floating != nil)

        engine.commitFloating()
        #expect(engine.canvas.pixel(at: PixelPoint(x: 30, y: 30)) == .white)  // vacated
        #expect(engine.canvas.pixel(at: PixelPoint(x: 80, y: 80)) == red)     // arrived
    }

    @Test("The live region size is reported while dragging and cleared after")
    func regionSizeReadout() {
        let engine = markedEngine()
        engine.settings.tool = .select
        #expect(engine.activeRegionSize == nil)

        engine.beginStroke(at: PixelPoint(x: 10, y: 10))
        engine.continueStroke(to: PixelPoint(x: 39, y: 29))
        let size = engine.activeRegionSize
        #expect(size?.width == 30 && size?.height == 20)

        engine.endStroke()
        #expect(engine.activeRegionSize == nil)
    }

    @Test("Resizing floating content scales what gets committed")
    func resizeThenCommit() {
        let engine = PaintEngine(width: 200, height: 200)
        engine.paste(Bitmap(width: 20, height: 20, fill: .black))
        #expect(engine.floating?.frame.width == 20)

        // Grab the bottom-right handle and pull it out.
        let corner = PixelPoint(
            x: engine.floating!.frame.maxX - 1, y: engine.floating!.frame.maxY - 1
        )
        engine.beginStroke(at: corner)
        engine.endStroke(at: PixelPoint(x: corner.x + 40, y: corner.y + 40))

        #expect(engine.floating!.frame.width > 20)
        engine.commitFloating()

        let painted = engine.canvas.pixels.filter { $0 == .black }.count
        #expect(painted > 400, "expected the scaled-up content, got \(painted) pixels")
    }

    @Test("Invert selection selects everything the marquee did not")
    func invertSelection() throws {
        let engine = markedEngine()
        engine.settings.tool = .select
        engine.beginStroke(at: PixelPoint(x: 10, y: 10))
        engine.endStroke(at: PixelPoint(x: 50, y: 50))

        engine.invertSelection()
        let inverted = try #require(engine.selection)
        // Inside the old marquee is now excluded; outside it is included.
        #expect(inverted.coverage(at: PixelPoint(x: 30, y: 30)) == 0)
        #expect(inverted.coverage(at: PixelPoint(x: 100, y: 100)) > 0)
    }

    @Test("Invert twice returns the original region")
    func invertIsInvolutive() throws {
        let engine = markedEngine()
        engine.settings.tool = .select
        engine.beginStroke(at: PixelPoint(x: 10, y: 10))
        engine.endStroke(at: PixelPoint(x: 50, y: 50))

        engine.invertSelection()
        engine.invertSelection()
        let restored = try #require(engine.selection)

        #expect(restored.coverage(at: PixelPoint(x: 30, y: 30)) > 0)
        #expect(restored.coverage(at: PixelPoint(x: 100, y: 100)) == 0)
        // And the bounds are tightened back, so the status bar reports the real
        // size rather than the whole canvas.
        #expect(restored.bounds.width < 60 && restored.bounds.height < 60)
    }

    @Test("Selecting everything then inverting clears the selection")
    func invertOfSelectAll() {
        let engine = markedEngine()
        engine.selectAll()
        engine.invertSelection()
        #expect(engine.selection == nil)
    }

    @Test("Escape-style cancel during a resize leaves the canvas untouched")
    func cancelDuringResize() {
        let engine = PaintEngine(width: 200, height: 200)
        let pristine = engine.canvas
        engine.paste(Bitmap(width: 30, height: 30, fill: .black))

        let corner = PixelPoint(
            x: engine.floating!.frame.maxX - 1, y: engine.floating!.frame.maxY - 1
        )
        engine.beginStroke(at: corner)
        engine.continueStroke(to: PixelPoint(x: corner.x + 50, y: corner.y + 50))
        engine.cancelStroke()
        engine.discardFloating()

        #expect(engine.canvas == pristine)
    }
}
