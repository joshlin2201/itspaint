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

    @Test("Clipboard photo source has no poster-like horizon seam")
    @MainActor
    func clipboardMarkupPhotoSource() {
        let source = ClipboardMarkupScene.unmarkedSource()
        let abruptColumns = (48..<478).filter { x in
            let above = source.pixel(at: PixelPoint(x: x, y: 291))!
            let below = source.pixel(at: PixelPoint(x: x, y: 292))!
            let difference = abs(Int(above.r) - Int(below.r))
                + abs(Int(above.g) - Int(below.g))
                + abs(Int(above.b) - Int(below.b))
            return difference > 48
        }.count

        #expect(abruptColumns < 100)
    }

    @Test("Quick sketch stays a simple two-colour explanation")
    @MainActor
    func quickSketch() {
        let first = QuickSketchScene.render()
        let second = QuickSketchScene.render()

        #expect((first.width, first.height) == (1000, 640))
        #expect(first == second)
        #expect(first.pixel(at: PixelPoint(x: 118, y: 122)) != .white)
        #expect(first.pixel(at: PixelPoint(x: 500, y: 328)) != .white)
        #expect(first.pixel(at: PixelPoint(x: 110, y: 95)) ==
                RGBA8(r: 23, g: 50, b: 77))
        #expect(first.pixel(at: PixelPoint(x: 500, y: 543)) ==
                RGBA8(r: 47, g: 128, b: 237))
        #expect(first.pixel(at: PixelPoint(x: 405, y: 188)) ==
                RGBA8(r: 239, g: 106, b: 91))
    }
}
