import AppKit
import Foundation
import PaintKit
import Testing
@testable import ItsPaint

/// Renders a real editor window to a PNG, for the README and social card.
///
/// The screenshots in docs/images are generated, not hand-assembled: the
/// artwork comes from `paint-demo`, and the window around it comes from here.
/// Because unit tests run inside the app process, the window can draw itself
/// into a bitmap — no screen-recording permission, no compositor, no pixels
/// that depend on whichever desktop happened to be behind the window.
///
/// Inert without the environment variables, so it costs CI nothing:
///
///     ITSPAINT_CAPTURE_IMAGE=/path/to/artwork.png \
///     ITSPAINT_CAPTURE_OUT=/path/to/window.png \
///     xcodebuild -project ItsPaint.xcodeproj -scheme ItsPaint \
///       -destination 'platform=macOS' \
///       test -only-testing:ItsPaintTests/WindowCaptureTests
///
/// The Remove Background reel is ITSPAINT_ALPHA_REEL_DIR=<dir> plus
/// ITSPAINT_ALPHA_REEL_SUBJECT=<subject.png with alpha>. The app is
/// sandboxed, so <dir> has to be inside its container — the tmp directory
/// under ~/Library/Containers/com.joshlin.itspaint/Data works.
///
/// The README reel works the same way with ITSPAINT_REEL_DIR=<dir>, and the
/// frames assemble into docs/images/markup-reel.gif with ffmpeg:
///
///     ffmpeg -f concat -i durations.txt -vf "scale=1012:-1:flags=lanczos, \
///       split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse= \
///       dither=bayer:bayer_scale=4:diff_mode=rectangle" -loop 0 markup-reel.gif
@Suite("Window capture", .serialized)
@MainActor
struct WindowCaptureTests {
    @Test("Captures the front window when the capture environment is set")
    func captureWindow() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let imagePath = environment["ITSPAINT_CAPTURE_IMAGE"],
              let outputPath = environment["ITSPAINT_CAPTURE_OUT"] else {
            return
        }

        let imageURL = URL(fileURLWithPath: imagePath)
        let document = DrawingDocument()
        try document.read(from: imageURL, ofType: "public.png")
        // The title chip shows the document name; without a file URL the
        // capture would read "Untitled".
        document.fileURL = imageURL
        document.makeWindowControllers()
        document.showWindows()

        let window = try #require(document.windowControllers.first?.window)
        window.makeKeyAndOrderFront(nil)

        // Optional: open a specific tool's options panel, so a capture can show
        // a control that only exists while that tool is selected.
        if let toolName = environment["ITSPAINT_CAPTURE_TOOL"],
           let tool = ToolKind(rawValue: toolName) {
            document.model.selectTool(tool)
        }
        if let grid = environment["ITSPAINT_CAPTURE_SNAP"], let spacing = Int(grid) {
            document.model.snapGrid = spacing
        }
        if environment["ITSPAINT_CAPTURE_SELECTION"] != nil {
            // Make the marquee with the select tool, then restore whichever tool
            // the capture asked for — otherwise this quietly overwrites it and
            // the panel shows the wrong options.
            let wanted = document.model.engine.settings.tool
            document.model.engine.settings.tool = .select
            document.model.engine.beginStroke(at: PixelPoint(x: 40, y: 40))
            _ = document.model.engine.endStroke(at: PixelPoint(x: 354, y: 267))
            document.model.engine.settings.tool = wanted
            document.model.noteChange(.empty)
        }

        // The traffic lights only take their colours once the app is active,
        // and activation is asynchronous.
        var patience = 100
        while !NSApp.isActive && patience > 0 {
            NSApp.activate(ignoringOtherApps: true)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            patience -= 1
        }

        // Let SwiftUI finish its first layout: the tool rail, options panel
        // and title chip all place themselves over the canvas asynchronously.
        for _ in 0..<20 {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }

        // The theme frame is the content view's superview: the whole window,
        // titlebar, traffic lights and rounded corners included.
        try Self.writeWindowPNG(window, to: URL(fileURLWithPath: outputPath))

        document.close()
    }

    @Test("Captures the README reel frames when the reel environment is set")
    func captureReel() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let reelDir = environment["ITSPAINT_REEL_DIR"] else { return }
        let directory = URL(fileURLWithPath: reelDir, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let document = DrawingDocument()
        let model = document.model
        // The reel is a fixture: pin the canvas to the documented demo size
        // rather than inheriting the local new-document preference.
        model.engine.reset(to: Bitmap(width: 1000, height: 640, fill: .white))
        // The pencil's options chip is the compact one; the brush panel would
        // sit over the pasted sheet's title, and an asset that hides the thing
        // it demonstrates is the wrong asset.
        model.selectTool(.pencil)
        document.fileURL = directory.appendingPathComponent("deploy-settings.png")
        document.makeWindowControllers()
        document.showWindows()
        let window = try #require(document.windowControllers.first?.window)
        window.makeKeyAndOrderFront(nil)

        var patience = 100
        while !NSApp.isActive && patience > 0 {
            NSApp.activate(ignoringOtherApps: true)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            patience -= 1
        }

        var frame = 0
        func snap() throws {
            for _ in 0..<6 {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            }
            frame += 1
            let name = String(format: "frame-%02d.png", frame)
            try Self.writeWindowPNG(window, to: directory.appendingPathComponent(name))
        }

        // The story the GIF tells, in the order GROWTH.md names it:
        // paste a screenshot, drop three step badges, pixelate a token.
        try snap()

        model.noteChange(model.engine.paste(Self.deploySettingsScreenshot()))
        model.noteChange(model.engine.commitFloating())
        try snap()

        model.selectTool(.badge)
        model.brushSize = 14
        model.foreground = PaintColour(hex: "EF6A5B") ?? .black
        for badge in [PixelPoint(x: 98, y: 236), PixelPoint(x: 98, y: 316), PixelPoint(x: 98, y: 396)] {
            model.noteChange(model.engine.beginStroke(at: badge))
            try snap()
        }

        model.selectTool(.pixelate)
        let sweep = [PixelPoint(x: 540, y: 506), PixelPoint(x: 670, y: 506), PixelPoint(x: 806, y: 506)]
        for reach in sweep {
            model.noteChange(model.engine.beginStroke(at: PixelPoint(x: 372, y: 458)))
            model.noteChange(model.engine.continueStroke(to: reach))
            model.noteChange(model.engine.endStroke(at: reach))
            try snap()
        }

        try snap()
        document.close()
    }

    /// Renders the Remove Background reel: a subject sitting on a flat page,
    /// then the same window one command later with the page gone.
    ///
    /// The fixture is any PNG with alpha — `paint-demo --scene chameleon`
    /// output — flattened onto a page
    /// colour, so the "before" is manufactured from the "after" and the frames
    /// cannot disagree with each other. Set `ITSPAINT_ALPHA_REEL_DIR` and
    /// `ITSPAINT_ALPHA_REEL_SUBJECT`.
    @Test("Captures the Remove Background reel when its environment is set")
    func captureAlphaReel() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let reelDir = environment["ITSPAINT_ALPHA_REEL_DIR"],
              let subjectPath = environment["ITSPAINT_ALPHA_REEL_SUBJECT"] else { return }
        let directory = URL(fileURLWithPath: reelDir, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let subject = try ImageCodec.decode(contentsOf: URL(fileURLWithPath: subjectPath))
        let page = PaintColour(hex: "EEF1F5") ?? .white
        let document = DrawingDocument()
        let model = document.model
        model.engine.reset(to: ImageCodec.flattened(subject, onto: page))
        // The eraser's chip is the compact one, and it is the tool a person
        // would otherwise be reaching for — which is the point of the reel.
        model.selectTool(.eraser)
        document.fileURL = directory.appendingPathComponent("product-shot.png")
        document.makeWindowControllers()
        document.showWindows()
        let window = try #require(document.windowControllers.first?.window)
        window.makeKeyAndOrderFront(nil)

        var patience = 100
        while !NSApp.isActive && patience > 0 {
            NSApp.activate(ignoringOtherApps: true)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            patience -= 1
        }

        var frame = 0
        func snap() throws {
            for _ in 0..<6 {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            }
            frame += 1
            try Self.writeWindowPNG(
                window, to: directory.appendingPathComponent(String(format: "frame-%02d.png", frame))
            )
        }

        // Hold on the flat page, take it away, hold on the result. Two holds a
        // side, because a two-frame GIF reads as a glitch rather than a change.
        try snap()
        try snap()
        let before = model.engine.canvas
        model.removeBackground()
        // Remove Background declines when the flood would take essentially the
        // whole canvas, which is the correct answer for a small subject on a
        // big page — and a silent no-op would ship a reel of five identical
        // frames. Fail here instead.
        #expect(
            model.engine.canvas != before,
            "Remove Background declined on this subject, so the reel has nothing to show"
        )
        try snap()
        try snap()
        try snap()

        document.close()
    }

    /// A plausible settings sheet to mark up, drawn by the engine itself so
    /// the reel needs no external fixture.
    private static func deploySettingsScreenshot() -> Bitmap {
        let engine = PaintEngine(
            canvas: Bitmap(width: 840, height: 460, fill: (PaintColour(hex: "F6F7F9") ?? .white).rgba8)
        )
        func colour(_ hex: String) -> PaintColour { PaintColour(hex: hex) ?? .black }
        func chip(_ rect: PixelRect) {
            engine.settings.tool = .shape
            engine.settings.shapeKind = .roundedRectangle
            engine.settings.shapeStyle = .outlineAndFill
            engine.settings.cornerRadius = 10
            engine.settings.brushSize = 2
            engine.colours.foreground = colour("D8DEE6")
            engine.colours.background = .white
            engine.beginStroke(at: PixelPoint(x: rect.minX, y: rect.minY))
            engine.endStroke(at: PixelPoint(x: rect.maxX, y: rect.maxY))
        }
        func text(_ string: String, x: Int, y: Int, size: Double, colour ink: PaintColour, font: String = "Helvetica") {
            engine.drawText(
                string,
                in: PixelRect(x: x, y: y, width: 700, height: Int(size * 1.6)),
                style: TextRenderer.Style(fontName: font, pointSize: size, colour: ink)
            )
        }

        text("Deploy settings", x: 48, y: 36, size: 30, colour: colour("1F2A37"), font: "Helvetica-Bold")

        let rows: [(label: String, value: String, y: Int)] = [
            ("Region", "us-west-2", 118),
            ("Instance", "m7g.large", 198),
            ("Auto scale", "On", 278),
        ]
        for row in rows {
            chip(PixelRect(x: 48, y: row.y, width: 744, height: 56))
            text(row.label, x: 72, y: row.y + 14, size: 21, colour: colour("33404F"))
            text(row.value, x: 560, y: row.y + 14, size: 21, colour: colour("5A6B7E"))
        }

        chip(PixelRect(x: 48, y: 366, width: 744, height: 60))
        text("API token", x: 72, y: 382, size: 21, colour: colour("33404F"))
        text("demo_EXAMPLE_NOT_A_REAL_KEY", x: 300, y: 384, size: 19, colour: colour("B3261E"), font: "Menlo")

        return engine.canvas
    }

    private static func writeWindowPNG(_ window: NSWindow, to url: URL) throws {
        // The theme frame is the content view's superview: the whole window,
        // titlebar, traffic lights and rounded corners included.
        let themeFrame = try #require(window.contentView?.superview)
        let rep = try #require(
            themeFrame.bitmapImageRepForCachingDisplay(in: themeFrame.bounds)
        )
        themeFrame.cacheDisplay(in: themeFrame.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: url)
    }
}
