import AppKit
import PaintKit
import SwiftUI

/// Application entry point.
///
/// AppKit lifecycle with a programmatic main menu — no nib. A nib for a menu
/// this small is a binary blob nobody can review in a diff; building it in code
/// keeps every shortcut and every action greppable.
/// An explicit entry point.
///
/// `@main` on an `NSApplicationDelegate` was tried first and silently did not
/// install the delegate: no launch callback ever fired, so the main menu was
/// never assigned and the app shipped with nothing but its own app menu — no
/// File, no Edit, no View.
///
/// This sets the delegate and the menu before starting the loop, and calls
/// `app.run()` rather than `NSApplicationMain`. That distinction matters:
/// `NSApplicationMain` after touching `NSApplication.shared` initialises the
/// application twice, which survives a normal launch and then crashes the host
/// under `xcodebuild test`.
@main
enum ItsPaintMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        // Held for the process lifetime by NSApplication itself once assigned;
        // the local also keeps it alive across setup. An app whose delegate is
        // deallocated mid-launch fails in ways that look like anything but that.
        let delegate = ItsPaintAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.mainMenu = MainMenuBuilder.build()
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

final class ItsPaintAppDelegate: NSObject, NSApplicationDelegate {

    /// The menu is already installed by `main()`, before the run loop starts —
    /// earlier than any launch callback, and the one assignment that cannot be
    /// too late. Building it a second time here only replaced a live menu bar
    /// with an identical one.
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Instantiate the document controller explicitly. Without a MainMenu
        // nib nothing else touches `NSDocumentController.shared`, and until it
        // exists it is not in the responder chain — so the app launches with a
        // menu bar and no window, and File ▸ New does nothing.
        _ = NSDocumentController.shared
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate()
        // Touching the singleton is what starts the watch, when it is switched
        // on and its bookmark still resolves. Nothing here asks for anything: it
        // is off until someone turns it on, and it stays off if the folder it was
        // given has since moved.
        _ = ScreenshotWatcher.shared
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        do {
            _ = try NSDocumentController.shared.openUntitledDocumentAndDisplay(true)
            return true
        } catch {
            NSApp.presentError(error)
            return false
        }
    }

    /// Opening a new window on reactivation is the expected Mac behaviour for a
    /// document app with no open documents.
    func applicationShouldHandleReopen(
        _ sender: NSApplication, hasVisibleWindows: Bool
    ) -> Bool {
        !hasVisibleWindows
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Settings has to work with no document open.
    ///
    /// The command lives on the document, because that is where every other
    /// command lives — but with no window there is no document in the responder
    /// chain, and `⌘,` would do nothing on a freshly launched app that had not
    /// opened anything yet. The delegate is the tail of the chain, so putting
    /// it here catches exactly that case and nothing else.
    @IBAction func showSettings(_ sender: Any?) {
        SettingsWindowController.show()
    }
}
