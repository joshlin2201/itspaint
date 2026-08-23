import AppKit
import Carbon.HIToolbox
import PaintKit

/// A system-wide shortcut that turns whatever is on the clipboard into a document.
///
/// `⌃⇧⌘4` already puts a screenshot on the clipboard instead of on the Desktop,
/// and that half of the workflow has nowhere to go: you have to find an app,
/// make a document, and paste. This closes it from the keyboard, from any app,
/// without ItsPaint being frontmost or even having a window open.
///
/// **Carbon, deliberately.** `RegisterEventHotKey` is the one global-shortcut API
/// that works from inside the App Sandbox with no extra entitlement and no
/// Accessibility prompt. `NSEvent.addGlobalMonitorForEvents` needs the
/// Accessibility grant — a scary System Settings trip for a paint app — and
/// `MASShortcut` and friends are third-party, which this project does not take.
/// Carbon is old, not deprecated, and it is the cheap correct answer here.
///
/// Off until switched on: an app that claims a system-wide key combination on
/// first launch is taking something that belongs to the whole machine.
@MainActor
@Observable
final class ClipboardHotKey {
    static let shared = ClipboardHotKey()

    private enum Key {
        static let enabled = "clipboardHotKeyEnabled"
    }

    /// `⌃⌥⌘V`. Three modifiers because this is registered against every app on
    /// the machine, and a two-modifier combination is something another app or
    /// the user probably already wants. `⇧⌘V` in particular is paste-and-match-
    /// style almost everywhere, so taking it globally would break typing.
    static let keyCode = UInt32(kVK_ANSI_V)
    static let modifiers = UInt32(controlKey | optionKey | cmdKey)
    static let displayName = "⌃⌥⌘V"

    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Key.enabled)
            isEnabled ? register() : unregister()
        }
    }

    /// Set when the combination could not be claimed, which in practice means
    /// another running app already owns it. Worth surfacing: the alternative is
    /// a switch that is on and does nothing.
    private(set) var problem: String?

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: Key.enabled)
        if isEnabled { register() }
    }

    // MARK: - Registration

    private func register() {
        unregister()

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // The callback is a C function pointer, so it cannot capture `self`.
        // It hops to the main actor and goes through the singleton instead —
        // which is also the only reason this type is a singleton.
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                var id = EventHotKeyID()
                let read = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &id
                )
                // Named explicitly, not `Self`: a C function pointer cannot be
                // formed from a closure that captures the dynamic Self type.
                guard read == noErr, id.signature == ClipboardHotKey.signature else {
                    return OSStatus(eventNotHandledErr)
                }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { ClipboardHotKey.shared.fire() }
                }
                return noErr
            },
            1, &spec, nil, &handler
        )
        guard status == noErr else {
            problem = "The shortcut could not be installed."
            return
        }

        var ref: EventHotKeyRef?
        let registered = RegisterEventHotKey(
            Self.keyCode, Self.modifiers,
            EventHotKeyID(signature: Self.signature, id: 1),
            GetApplicationEventTarget(), 0, &ref
        )
        guard registered == noErr, let ref else {
            problem = "\(Self.displayName) is already taken by another app."
            unregister()
            return
        }
        hotKey = ref
        problem = nil
    }

    private func unregister() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
    }

    /// `'ItsP'`, so the handler can tell our hot key from any other one installed
    /// on the same application target.
    private static let signature: OSType = 0x4974_7350

    // MARK: - Firing

    /// Open the clipboard as a new document.
    ///
    /// Nothing is pasted into the document you are working in. A global shortcut
    /// fires while you are somewhere else entirely, so the only safe target is a
    /// new window — landing a paste on top of whatever happens to be frontmost is
    /// an edit nobody asked for, in a document they were not looking at.
    private func fire() {
        NSApp.activate(ignoringOtherApps: true)

        let board = NSPasteboard.general
        guard Bitmap.canDecode(pasteboard: board) else {
            present("There is no image on the clipboard.",
                    "Copy an image — or take a screenshot with ⌃⇧⌘4 — and try again.")
            return
        }

        do {
            // Shared with the Services entry, which arrives the same way: an
            // image from another app, no document to put it in.
            try NewDocument.open(with: Bitmap(pasteboard: board))
        } catch {
            present("That image could not be opened.", error.localizedDescription)
        }
    }

    private func present(_ message: String, _ detail: String?) {
        let alert = NSAlert()
        alert.messageText = message
        if let detail { alert.informativeText = detail }
        alert.alertStyle = .informational
        alert.runModal()
    }
}
