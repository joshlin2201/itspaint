import PaintKit
import Foundation

enum DemoScene: String, CaseIterable, Sendable {
    case clipboard
    case quickSketch = "quick-sketch"
    case transparency

    var defaultFilename: String {
        switch self {
        case .clipboard: "clipboard-markup.png"
        case .quickSketch: "quick-sketch.png"
        case .transparency: "transparency.png"
        }
    }

    @MainActor
    func render() -> Bitmap {
        switch self {
        case .clipboard:
            ClipboardMarkupScene.render()
        case .quickSketch:
            QuickSketchScene.render()
        case .transparency:
            DemoCanvas().engine.canvas
        }
    }

    @MainActor
    func write(to output: URL) throws {
        try ImageCodec.write(render(), to: output, as: .png)
    }
}
