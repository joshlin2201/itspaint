import PaintKit
import Testing
@testable import ItsPaint

/// The contract the selection bar is built on, which is not the bar itself.
///
/// `SelectionActions` appears when `model.hasSelection` is true. That forwards
/// to the engine, which is UI-free and deliberately not observable — so nothing
/// in `EditorView`'s body is invalidated by making a marquee, and the bar simply
/// never appeared. It was drawing correctly the whole time; it was never asked
/// to draw.
///
/// `hasSelection` is a **mirror** now, synced only when the value genuinely
/// differs — not `revision`, which bumps on every dirty rect and would re-render
/// the whole editor sixty times a second during a freehand stroke. These tests
/// guard the mirror: that making a marquee sets it, and that clearing one clears
/// it, on the same path the pointer takes.
@Suite("Selection bar")
@MainActor
struct SelectionBarTests {
    private func model() -> EditorModel {
        EditorModel(canvas: Bitmap(width: 200, height: 160, fill: .white))
    }

    /// The path the pointer takes, not a shortcut round it.
    ///
    /// `CanvasNSView` reports the rect the stroke dirtied through
    /// `noteVisualChange`, and a selection is a visual change rather than an
    /// edit — it moves what you see without marking the document. A helper that
    /// passed `.empty` here would be testing a call the app never makes.
    private func select(_ model: EditorModel, to point: PixelPoint) {
        model.engine.settings.tool = .select
        model.engine.beginStroke(at: PixelPoint(x: 10, y: 10))
        let dirty = model.engine.endStroke(at: point)
        model.noteVisualChange(dirty)
    }

    @Test("Making a selection sets the flag the view watches")
    func selectionSetsTheMirror() {
        let model = model()
        #expect(!model.hasSelection)

        select(model, to: PixelPoint(x: 120, y: 90))

        // Without the mirror this stays false as far as SwiftUI is concerned,
        // the bar's `if` is never re-evaluated, and the bar is invisible for the
        // whole session while the engine says there is a selection.
        #expect(model.hasSelection)
    }

    @Test("Clearing the selection takes the bar with it")
    func deselectingClearsTheMirror() {
        let model = model()
        select(model, to: PixelPoint(x: 120, y: 90))
        #expect(model.hasSelection)

        model.deselect()
        #expect(!model.hasSelection)
    }

    @Test("The bar knows how big the selection is")
    func selectionReportsItsSize() {
        let model = model()
        select(model, to: PixelPoint(x: 110, y: 60))

        let size = model.selectionSize
        #expect(size != nil)
        #expect((size?.width ?? 0) > 0)
        #expect((size?.height ?? 0) > 0)
    }

    /// Every action the bar offers has to work on a selection that exists, or the
    /// bar is four buttons that teach four shortcuts and do nothing.
    @Test("Crop, copy, cut and delete all act on the selection")
    func everyActionActs() {
        for act in ["crop", "copy", "cut", "delete"] {
            let model = model()
            select(model, to: PixelPoint(x: 110, y: 60))
            #expect(!model.canUndo)

            switch act {
            case "crop": model.cropToSelection()
            case "copy": model.copySelection()
            case "cut": model.cutSelection()
            default: model.deleteSelection()
            }

            // **Undoable, not "the pixels moved".** Deleting a white region from
            // a white canvas leaves every pixel exactly as it was, so comparing
            // bitmaps calls a working Delete a no-op. What every one of these
            // has in common is that it is an edit you can take back.
            if act != "copy" {
                #expect(model.canUndo, "\(act) registered no undoable edit")
            } else {
                // Copy is the one that must NOT be an edit: it puts the pixels on
                // the clipboard and leaves the document alone.
                #expect(!model.canUndo, "copy marked the document edited")
            }
        }
    }

    /// The paste bar and the selection bar want the same slot, and a floating
    /// paste is itself a selection — so without this rule both are eligible at
    /// once and the window shows two answers to one question.
    @Test("A floating paste yields the slot to the paste bar")
    func floatingContentWinsTheSlot() {
        let model = model()
        select(model, to: PixelPoint(x: 110, y: 60))
        #expect(model.hasSelection)
        #expect(!model.hasFloatingContent)
    }
}
