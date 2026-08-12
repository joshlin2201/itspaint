import Testing
import PaintKit
@testable import ItsPaint

/// The highlighter's 4px floor has to keep the size control honest without taking
/// the small sizes away from every other tool for the rest of the session.
@Suite("A tool's size floor is not permanent")
@MainActor
struct ToolSizeFloorTests {

    private func model() -> EditorModel {
        EditorModel(engine: PaintEngine(width: 64, height: 64))
    }

    @Test func armingTheHighlighterRaisesTheSizeToItsFloor() {
        let m = model()
        m.brushSize = 2
        m.tool = .highlighter
        #expect(m.brushSize == 4, "the panel would show 2 and the stroke would be 4")
    }

    /// The regression a one-way `max` shipped: after one highlighter stroke you
    /// could never get back to a 2px brush.
    @Test func leavingTheHighlighterHandsTheChosenSizeBack() {
        let m = model()
        m.brushSize = 2
        m.tool = .highlighter
        m.tool = .brush
        #expect(m.brushSize == 2, "one visit to the highlighter took 1-3px away for good")
    }

    @Test func aSizeChosenUnderTheFloorIsKept() {
        let m = model()
        m.brushSize = 2
        m.tool = .highlighter
        m.brushSize = 28
        m.tool = .brush
        #expect(m.brushSize == 28, "a size picked on purpose was overwritten on the way out")
    }

    @Test func aSizeAboveTheFloorIsUntouched() {
        let m = model()
        m.brushSize = 14
        m.tool = .highlighter
        #expect(m.brushSize == 14)
        m.tool = .brush
        #expect(m.brushSize == 14)
    }

    @Test func everyToolCanStillReachEverySizeItOffers() {
        let m = model()
        for tool in ToolKind.allCases where tool.usesBrushSize {
            m.tool = tool
            for size in ToolSettings.sizeRange(for: tool) {
                m.brushSize = size
                #expect(m.engine.settings.nib.size == size, "\(tool) at \(size)px paints \(m.engine.settings.nib.size)px")
            }
        }
    }
}
