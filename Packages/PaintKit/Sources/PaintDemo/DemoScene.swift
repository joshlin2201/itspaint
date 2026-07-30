import PaintKit
import Foundation

enum DemoScene: String, CaseIterable, Sendable {
    case clipboard
    case quickSketch = "quick-sketch"
    case transparency
    case chameleon

    var defaultFilename: String {
        switch self {
        case .clipboard: "clipboard-markup.png"
        case .quickSketch: "quick-sketch.png"
        case .transparency: "transparency.png"
        case .chameleon: "chameleon.png"
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
            TransparencyScene.render()
        case .chameleon:
            ChameleonScene.render()
        }
    }

    @MainActor
    func write(to output: URL) throws {
        try ImageCodec.write(render(), to: output, as: .png)
    }
}
