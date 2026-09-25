import AppKit
import PaintKit

/// Take a screenshot with the system's own crosshair and open it as a new image.
///
/// `screencapture -i` is the interface everyone already knows from `⇧⌘4`: drag a
/// region, press Space to pick a window, Escape to back out. Running it rather
/// than drawing a selection overlay of our own gets every one of those behaviours,
/// on every display, exactly as the system does them.
///
/// **It needs Screen Recording.** Capturing other apps' windows is gated by macOS
/// for every app that does it, and `screencapture` run from here is attributed to
/// ItsPaint. The prompt comes the first time someone asks for a screenshot and not
/// before; the folder watcher and the clipboard shortcut still need no permission.
@MainActor
enum ScreenCapture {
    /// While the crosshair is up, so a second press does not start another.
    private static var isCapturing = false

    /// Start a capture. ItsPaint steps aside while the crosshair is up when it
    /// was the app in front, because a screenshot is nearly always of something
    /// else, and comes back with the result or when the capture is cancelled.
    static func begin() {
        guard !isCapturing else { return }
        guard CGPreflightScreenCaptureAccess() else { return askForAccess() }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ItsPaint capture \(UUID().uuidString).png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = arguments(writingTo: url)
        process.terminationHandler = { _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { finish(url) }
            }
        }

        let hid = NSApp.isActive
        if hid { NSApp.hide(nil) }
        do {
            try process.run()
            isCapturing = true
            steppedAside = hid
        } catch {
            if hid { NSApp.unhide(nil) }
            present("The screenshot could not be started.", error.localizedDescription)
        }
    }

    /// Interactive, to a file. Escape leaves no file, which is how a cancel is told
    /// apart from a failure.
    static func arguments(writingTo url: URL) -> [String] {
        ["-i", url.path]
    }

    /// "Screenshot 2026-09-25 at 10.42.13", or "at 10.42.13 AM" where the clock
    /// is 12-hour, which is the shape macOS gives its own screenshots, so the
    /// window title and anything dragged out of it read the way people expect.
    static func name(for date: Date, twelveHour: Bool = usesTwelveHourClock) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = twelveHour ? "yyyy-MM-dd 'at' h.mm.ss a" : "yyyy-MM-dd 'at' HH.mm.ss"
        return "Screenshot \(formatter.string(from: date))"
    }

    /// Whether the user's clock shows AM and PM.
    static var usesTwelveHourClock: Bool {
        DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") ?? false
    }

    private static var steppedAside = false

    private static func finish(_ url: URL) {
        isCapturing = false
        defer { try? FileManager.default.removeItem(at: url) }
        // Named for when the shot was taken, which is now: picking a window can
        // take a while after the crosshair came up.
        let taken = Date()
        if steppedAside { NSApp.unhide(nil) }
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        NSApp.activate()
        do {
            try NewDocument.open(with: ImageCodec.decode(contentsOf: url), named: name(for: taken))
        } catch {
            present("The screenshot could not be opened.", error.localizedDescription)
        }
    }

    /// macOS shows its own request while it has no answer recorded, and after
    /// that answers no without asking. Asking every time costs nothing and puts
    /// ItsPaint back in the Screen Recording list after the permissions have
    /// been reset. From the second time on, this also says where the switch is
    /// and opens the pane.
    private static func askForAccess() {
        let askedKey = "askedForScreenCapture"
        let askedBefore = UserDefaults.standard.bool(forKey: askedKey)
        UserDefaults.standard.set(true, forKey: askedKey)
        _ = CGRequestScreenCaptureAccess()
        guard askedBefore else { return }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "ItsPaint needs permission to take screenshots."
        alert.informativeText = "Turn on ItsPaint in System Settings, under Privacy & Security, "
            + "Screen & System Audio Recording, then try again. macOS may ask you to reopen ItsPaint first."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn,
              let pane = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        else { return }
        NSWorkspace.shared.open(pane)
    }

    private static func present(_ message: String, _ detail: String?) {
        let alert = NSAlert()
        alert.messageText = message
        if let detail { alert.informativeText = detail }
        alert.alertStyle = .informational
        alert.runModal()
    }
}
