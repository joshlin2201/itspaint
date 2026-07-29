import PaintKit

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

    /// Scene artwork is added by the dedicated asset tasks. Keeping this
    /// fixture-sized canvas here makes the public command contract testable.
    @MainActor
    func render() -> DemoCanvas {
        DemoCanvas()
    }
}
