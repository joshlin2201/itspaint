import AppKit
import Foundation
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
        let themeFrame = try #require(window.contentView?.superview)
        let rep = try #require(
            themeFrame.bitmapImageRepForCachingDisplay(in: themeFrame.bounds)
        )
        themeFrame.cacheDisplay(in: themeFrame.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: outputPath))

        document.close()
    }
}
