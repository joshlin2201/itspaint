import AppKit
import PaintKit
import SwiftUI

/// What the app remembers between launches.
///
/// Deliberately small. Every setting here is one someone would otherwise have
/// to redo on every launch or every new document — a preference, not a
/// substitute for a decision the app should be making correctly on its own. A
/// checkbox that exists because two people disagreed about a default is a
/// defect with a UI attached.
///
/// Stored in `UserDefaults` because it is genuinely per-user, per-machine
/// state. Nothing here travels in a document.
@MainActor
@Observable
final class Settings {
    static let shared = Settings()

    private enum Key {
        static let newCanvasWidth = "newCanvasWidth"
        static let newCanvasHeight = "newCanvasHeight"
        static let defaultTool = "defaultTool"
        static let defaultBrushSize = "defaultBrushSize"
        static let growCanvasOnPaste = "growCanvasOnPaste"
        static let resizeWindowWithCanvas = "resizeWindowWithCanvas"
        static let confirmLargeCanvas = "confirmLargeCanvas"
    }

    /// The size File ▸ New starts at.
    var newCanvasWidth: Int { didSet { store(newCanvasWidth, Key.newCanvasWidth) } }
    var newCanvasHeight: Int { didSet { store(newCanvasHeight, Key.newCanvasHeight) } }

    /// The tool a new document opens holding.
    var defaultTool: ToolKind { didSet { store(defaultTool.rawValue, Key.defaultTool) } }
    var defaultBrushSize: Int { didSet { store(defaultBrushSize, Key.defaultBrushSize) } }

    /// Whether placing content larger than the canvas enlarges the canvas.
    ///
    /// On by default: a paint app that silently crops what you paste is the
    /// single most-reported thing about this app. Off is for people who treat
    /// the canvas as a fixed frame.
    var growCanvasOnPaste: Bool { didSet { store(growCanvasOnPaste, Key.growCanvasOnPaste) } }

    /// Whether the window grows with the canvas.
    var resizeWindowWithCanvas: Bool {
        didSet { store(resizeWindowWithCanvas, Key.resizeWindowWithCanvas) }
    }

    /// Warn before a paste that would produce a very large canvas.
    var confirmLargeCanvas: Bool { didSet { store(confirmLargeCanvas, Key.confirmLargeCanvas) } }

    private init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Key.newCanvasWidth: 1_280,
            Key.newCanvasHeight: 800,
            Key.defaultBrushSize: 2,
            Key.growCanvasOnPaste: true,
            Key.resizeWindowWithCanvas: true,
            Key.confirmLargeCanvas: true,
        ])
        newCanvasWidth = defaults.integer(forKey: Key.newCanvasWidth)
        newCanvasHeight = defaults.integer(forKey: Key.newCanvasHeight)
        defaultBrushSize = defaults.integer(forKey: Key.defaultBrushSize)
        defaultTool = defaults.string(forKey: Key.defaultTool)
            .flatMap(ToolKind.init(rawValue:)) ?? .brush
        growCanvasOnPaste = defaults.bool(forKey: Key.growCanvasOnPaste)
        resizeWindowWithCanvas = defaults.bool(forKey: Key.resizeWindowWithCanvas)
        confirmLargeCanvas = defaults.bool(forKey: Key.confirmLargeCanvas)
    }

    private func store(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    /// Apply the launch preferences to a freshly created document.
    func apply(to model: EditorModel) {
        model.tool = defaultTool
        model.brushSize = defaultBrushSize
        model.engine.growsToFitFloating = growCanvasOnPaste
    }

    /// The canvas size File ▸ New should use, clamped to what the engine
    /// supports so a hand-edited defaults plist cannot produce a document that
    /// refuses to open.
    var newCanvasSize: (width: Int, height: Int) {
        let width = min(max(1, newCanvasWidth), Bitmap.maximumDimension)
        let height = min(max(1, newCanvasHeight), Bitmap.maximumDimension)
        return (width, height)
    }

    func resetToDefaults() {
        newCanvasWidth = 1_280
        newCanvasHeight = 800
        defaultTool = .brush
        defaultBrushSize = 2
        growCanvasOnPaste = true
        resizeWindowWithCanvas = true
        confirmLargeCanvas = true
    }
}

// MARK: - The window

/// A plain `NSWindow` rather than SwiftUI's `Settings` scene.
///
/// `Settings {}` is only available to a SwiftUI `App`, and this app's lifecycle
/// is `NSApplicationDelegate` + `NSDocumentController` so the document model
/// stays AppKit's. One small window controller is a smaller price than
/// restructuring the lifecycle for a preferences pane.
@MainActor
enum SettingsWindowController {
    private static var window: NSWindow?

    static func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: SettingsView())
        let created = NSWindow(contentViewController: hosting)
        created.title = "Settings"
        created.styleMask = [.titled, .closable]
        created.isReleasedWhenClosed = false
        created.center()
        created.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = created
    }
}

struct SettingsView: View {
    @Bindable private var settings = Settings.shared

    var body: some View {
        Form {
            Section("New documents") {
                LabeledContent("Canvas size") {
                    HStack(spacing: Tokens.Space.tight) {
                        TextField("", value: $settings.newCanvasWidth, format: .number)
                            .frame(width: 72)
                        Text("×").foregroundStyle(.secondary)
                        TextField("", value: $settings.newCanvasHeight, format: .number)
                            .frame(width: 72)
                        Text("px").foregroundStyle(.secondary)
                    }
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                }

                Picker("Start with", selection: $settings.defaultTool) {
                    ForEach(ToolKind.allCases, id: \.self) { tool in
                        Text(tool.displayName).tag(tool)
                    }
                }

                LabeledContent("Brush size") {
                    HStack(spacing: Tokens.Space.tight) {
                        Slider(
                            value: Binding(
                                get: { Double(settings.defaultBrushSize) },
                                set: { settings.defaultBrushSize = Int($0.rounded()) }
                            ),
                            in: 1...48
                        )
                        Text("\(settings.defaultBrushSize)")
                            .monospacedDigit()
                            .frame(width: 24, alignment: .trailing)
                    }
                }
            }

            Section("Pasting") {
                Toggle("Grow the canvas to fit pasted images", isOn: $settings.growCanvasOnPaste)
                Text("When off, anything outside the canvas is cropped when you place it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Resize the window with the canvas", isOn: $settings.resizeWindowWithCanvas)
                Toggle("Warn before very large canvases", isOn: $settings.confirmLargeCanvas)
            }

            Section {
                HStack {
                    Spacer()
                    Button("Reset to Defaults") { settings.resetToDefaults() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
