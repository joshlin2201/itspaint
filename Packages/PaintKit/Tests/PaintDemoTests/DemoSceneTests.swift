import Foundation
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
}
