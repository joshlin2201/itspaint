import AppKit
import Foundation
import PaintKit
import Testing
@testable import ItsPaint

/// The paste path, end to end through the model and the pasteboard.
///
/// The engine's growth is covered in PaintKit. What is covered *here* is
/// everything the app layer adds on top and that nothing exercised before: that
/// a real pasteboard image grows the canvas, that the size change is announced
/// so the window can follow, and that the announcement fires once per change
/// rather than on every stroke.
@Suite("Paste grows the canvas", .serialized)
@MainActor
struct PasteGrowthTests {

    private func writeToPasteboard(_ bitmap: Bitmap) throws {
        let data = try ImageCodec.encode(bitmap, as: .png)
        let board = NSPasteboard.general
        board.clearContents()
        board.setData(data, forType: .png)
    }

    private func red(_ w: Int, _ h: Int) -> Bitmap {
        Bitmap(width: w, height: h, fill: PaintColour(hex: "FF0000")!.rgba8)
    }

    @Test("Pasting an oversized image from the pasteboard grows the canvas")
    func pasteGrowsFromPasteboard() throws {
        let model = EditorModel(canvas: Bitmap(width: 100, height: 100, fill: .white))
        try writeToPasteboard(red(400, 300))

        model.paste()

        #expect(model.canvasSize.width == 400)
        #expect(model.canvasSize.height == 300)
        // Entirely on-canvas, which is what makes every resize handle reachable.
        let frame = try #require(model.floating).frame
        #expect(model.canvas.bounds.union(frame) == model.canvas.bounds)
    }

    @Test("A size change is announced exactly once")
    func announcesResizeOnce() throws {
        let model = EditorModel(canvas: Bitmap(width: 100, height: 100, fill: .white))
        var announced: [(Int, Int)] = []
        model.onCanvasResized = { width, height in announced.append((width, height)) }

        try writeToPasteboard(red(400, 300))
        model.paste()

        #expect(announced.count == 1, "expected one announcement, got \(announced)")
        #expect(announced.first?.0 == 400)
        #expect(announced.first?.1 == 300)
    }

    @Test("Drawing does not announce a resize")
    func drawingIsSilent() {
        // The hook is consulted from the same place every pixel change funnels
        // through, so the guard against firing on ordinary edits matters.
        let model = EditorModel(canvas: Bitmap(width: 120, height: 120, fill: .white))
        var announced = 0
        model.onCanvasResized = { _, _ in announced += 1 }

        model.selectTool(.brush)
        _ = model.engine.beginStroke(at: PixelPoint(x: 10, y: 10))
        model.noteChange(model.engine.endStroke(at: PixelPoint(x: 80, y: 80)))

        #expect(announced == 0)
    }

    @Test("Committing content dragged off the edge keeps it and announces the growth")
    func commitOverhangAnnounces() throws {
        let model = EditorModel(canvas: Bitmap(width: 200, height: 200, fill: .white))
        var announced: [(Int, Int)] = []
        model.onCanvasResized = { w, h in announced.append((w, h)) }

        try writeToPasteboard(red(40, 40))
        model.paste()
        #expect(announced.isEmpty, "a fitting paste should not resize anything")

        model.noteChange(model.engine.moveFloating(to: PixelPoint(x: 180, y: 180)))
        model.noteChange(model.engine.commitFloating())

        #expect(model.canvasSize.width == 220)
        #expect(announced.count == 1)
        // The overhanging corner survived rather than being cropped away.
        let corner = model.canvas.pixel(at: PixelPoint(x: 219, y: 219))
        #expect(corner == PaintColour(hex: "FF0000")!.rgba8)
    }

    @Test("Growth is undoable, and undoing announces the size going back")
    func undoAnnouncesShrink() throws {
        let model = EditorModel(canvas: Bitmap(width: 100, height: 100, fill: .white))
        try writeToPasteboard(red(400, 300))
        model.paste()
        model.noteChange(model.engine.commitFloating())

        var announced: [(Int, Int)] = []
        model.onCanvasResized = { w, h in announced.append((w, h)) }

        while model.canUndo { model.undo() }

        #expect(model.canvasSize.width == 100, "undo did not restore the original canvas size")
        #expect(announced.contains { $0 == (100, 100) }, "the shrink was never announced")
    }

    @Test("Turning growth off restores the cropping behaviour")
    func growthRespectsTheSetting() throws {
        let model = EditorModel(canvas: Bitmap(width: 100, height: 100, fill: .white))
        model.engine.growsToFitFloating = false
        try writeToPasteboard(red(400, 300))

        model.paste()
        #expect(model.canvasSize.width == 100)
    }
}

/// The window that has to follow the canvas.
///
/// Pure arithmetic, deliberately: the fit is computed before any layout pass so
/// the open path and the grow path can share it, which is the only reason a
/// window opened at a size and a window grown to that size agree.
@Suite("Window fit")
@MainActor
struct WindowFitTests {

    @Test("A canvas that fits the screen gets a window its own size")
    func smallCanvasIsExact() {
        let fit = DrawingDocument.windowFit(forCanvas: (800, 600), on: nil)
        #expect(fit.zoom == 1, "a canvas smaller than the screen must not be scaled")
        #expect(fit.contentSize.width == 800 + Tokens.Chrome.frameGap * 2)
        #expect(fit.contentSize.height == 600 + Tokens.Chrome.frameGap * 2)
    }

    @Test("A canvas larger than the screen scales down rather than overflowing")
    func hugeCanvasScalesDown() {
        // The fallback screen is 1440x900 when no NSScreen is supplied.
        let fit = DrawingDocument.windowFit(forCanvas: (6000, 4000), on: nil)
        #expect(fit.zoom < 1)
        #expect(fit.contentSize.width <= 1440 * 0.94 + 1)
        #expect(fit.contentSize.height <= 900 * 0.94 + 1)
    }

    @Test("Never smaller than the window's own minimum")
    func tinyCanvasStillUsable() {
        let fit = DrawingDocument.windowFit(forCanvas: (16, 16), on: nil)
        #expect(fit.contentSize.width >= 560)
        #expect(fit.contentSize.height >= 420)
    }

    @Test("Growth is monotonic: a bigger canvas never wants a smaller window")
    func biggerCanvasNeverShrinks() {
        var previous = CGSize.zero
        for side in stride(from: 200, through: 2_000, by: 200) {
            let fit = DrawingDocument.windowFit(forCanvas: (side, side), on: nil)
            #expect(fit.contentSize.width >= previous.width - 1)
            previous = fit.contentSize
        }
    }

    @Test("A degenerate canvas does not divide by zero")
    func zeroCanvasIsSafe() {
        let fit = DrawingDocument.windowFit(forCanvas: (0, 0), on: nil)
        #expect(fit.zoom.isFinite)
        #expect(fit.contentSize.width.isFinite)
        #expect(fit.contentSize.width >= 560)
    }
}
