import Foundation
import PaintKit
import Testing
@testable import PaintDemo

@Suite("PaintDemo scene contract")
struct DemoSceneTests {
    @Test("The public demo suite has stable CLI names and filenames")
    func stableNames() {
        #expect(DemoScene.allCases.map(\.rawValue) == [
            "clipboard", "quick-sketch", "transparency",
        ])
        #expect(DemoScene.clipboard.defaultFilename == "clipboard-markup.png")
        #expect(DemoScene.quickSketch.defaultFilename == "quick-sketch.png")
        #expect(DemoScene.transparency.defaultFilename == "transparency.png")
    }

    @Test("Clipboard markup is fixed, deterministic, and visibly annotated")
    @MainActor
    func clipboardMarkup() {
        let unmarked = ClipboardMarkupScene.unmarkedSource()
        let first = ClipboardMarkupScene.render()
        let second = ClipboardMarkupScene.render()

        #expect((first.width, first.height) == (1000, 640))
        #expect(first == second)
        #expect(first.pixel(at: PixelPoint(x: 618, y: 267)) !=
                first.pixel(at: PixelPoint(x: 618, y: 232)))
        #expect(first.pixel(at: PixelPoint(x: 350, y: 360)) !=
                unmarked.pixel(at: PixelPoint(x: 350, y: 360)))
        #expect(first.pixel(at: PixelPoint(x: 500, y: 361)) !=
                unmarked.pixel(at: PixelPoint(x: 500, y: 361)))
    }
}
