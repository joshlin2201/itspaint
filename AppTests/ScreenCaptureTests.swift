import AppKit
import Foundation
import Testing
@testable import ItsPaint

/// The capture itself runs `screencapture` and needs Screen Recording, which a
/// test host does not have, so these pin everything around it: what is asked of
/// the system, what the result is called, and how it is reached.
@Suite("Screen capture")
@MainActor
struct ScreenCaptureTests {

    @Test("The capture is interactive and writes to the file it will open")
    func argumentsAreInteractive() {
        let url = URL(fileURLWithPath: "/private/var/folders/x/shot.png")
        #expect(ScreenCapture.arguments(writingTo: url) == ["-i", "/private/var/folders/x/shot.png"])
    }

    @Test("A capture is named the way macOS names its own screenshots, on either clock")
    func captureName() throws {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 9; parts.day = 5
        parts.hour = 21; parts.minute = 4; parts.second = 7
        let date = try #require(Calendar(identifier: .gregorian).date(from: parts))
        #expect(ScreenCapture.name(for: date, twelveHour: false) == "Screenshot 2026-09-05 at 21.04.07")
        #expect(ScreenCapture.name(for: date, twelveHour: true) == "Screenshot 2026-09-05 at 9.04.07 PM")
    }

    @Test("The two global shortcuts are distinct and use three modifiers")
    func globalShortcutsAreDistinct() {
        let clipboard = GlobalHotKey.clipboard
        let capture = GlobalHotKey.capture
        #expect(clipboard.id != capture.id)
        #expect(clipboard.keyCode != capture.keyCode)
        #expect(clipboard.displayName == "⌃⌥⌘V")
        #expect(capture.displayName == "⌃⌥⌘4")
    }

    /// Both work with no window open, so the app delegate answers them rather
    /// than a document, and the File menu shows the same chords the global
    /// shortcuts use.
    @Test("New from Screenshot and New from Clipboard are in File and answered by the app")
    func fileMenuReachesTheApp() throws {
        let file = try #require(
            MainMenuBuilder.build().items.first { $0.submenu?.title == "File" }?.submenu
        )
        let delegate = try #require(NSApp.delegate as? NSObject)
        for (title, key) in [("New from Screenshot", "4"), ("New from Clipboard", "v")] {
            let item = try #require(file.items.first { $0.title == title }, "File is missing \(title)")
            #expect(item.keyEquivalent == key)
            #expect(item.keyEquivalentModifierMask == [.command, .option, .control])
            #expect(delegate.responds(to: try #require(item.action)), "\(title) reaches nothing")
        }
        let dock = try #require((NSApp.delegate as? ItsPaintAppDelegate)?.applicationDockMenu(NSApp))
        #expect(dock.items.map(\.title) == ["New from Screenshot", "New from Clipboard"])
    }
}
