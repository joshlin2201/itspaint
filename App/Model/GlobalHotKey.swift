import AppKit
import Carbon.HIToolbox
import PaintKit

/// A system-wide shortcut that starts a new image from outside the app.
///
/// Two of them, both reached from any app, without ItsPaint being frontmost or
/// even having a window open:
///
/// - `⌃⌥⌘V` opens whatever is on the clipboard. `⌃⇧⌘4` already puts a
///   screenshot there, and that half of the workflow had nowhere to go.
/// - `⌃⌥⌘4` takes the screenshot itself, with the system's crosshair, and opens
///   the result.
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
///
/// Three modifiers because these are registered against every app on the
/// machine, and a two-modifier combination is something another app or the user
/// probably already wants. `⇧⌘V` in particular is paste-and-match-style almost
/// everywhere, so taking it globally would break typing.
@MainActor
@Observable
final class GlobalHotKey {
    static let clipboard = GlobalHotKey(
        id: 1, defaultsKey: "clipboardHotKeyEnabled",
        keyCode: kVK_ANSI_V, displayName: "⌃⌥⌘V",
        action: { NewDocument.openClipboard() }
    )

    static let capture = GlobalHotKey(
        id: 2, defaultsKey: "captureHotKeyEnabled",
        keyCode: kVK_ANSI_4, displayName: "⌃⌥⌘4",
        action: { ScreenCapture.begin() }
    )

    static let modifiers = UInt32(controlKey | optionKey | cmdKey)

    let id: UInt32
    let keyCode: UInt32
    let displayName: String
    private let defaultsKey: String
    private let action: @MainActor () -> Void

    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: defaultsKey)
            isEnabled ? register() : unregister()
        }
    }

    /// Set when the combination could not be claimed, which in practice means
    /// another running app already owns it. Worth surfacing: the alternative is
    /// a switch that is on and does nothing.
    private(set) var problem: String?

    @ObservationIgnored private var hotKey: EventHotKeyRef?

    private init(
        id: UInt32, defaultsKey: String, keyCode: Int, displayName: String,
        action: @escaping @MainActor () -> Void
    ) {
        self.id = id
        self.defaultsKey = defaultsKey
        self.keyCode = UInt32(keyCode)
        self.displayName = displayName
        self.action = action
        isEnabled = UserDefaults.standard.bool(forKey: defaultsKey)
        if isEnabled { register() }
    }

    // MARK: - Registration

    private func register() {
        unregister()
        guard Self.installHandler() else {
            problem = "The shortcut could not be installed."
            return
        }

        var ref: EventHotKeyRef?
        let registered = RegisterEventHotKey(
            keyCode, Self.modifiers,
            EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(), 0, &ref
        )
        guard registered == noErr, let ref else {
            problem = "\(displayName) is already taken by another app."
            return
        }
        hotKey = ref
        Self.registered[id] = self
        problem = nil
    }

    private func unregister() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        Self.registered[id] = nil
    }

    /// The shortcuts currently claimed, by id, for the handler to dispatch to.
    private static var registered: [UInt32: GlobalHotKey] = [:]
    private static var handler: EventHandlerRef?

    /// One handler for every shortcut, installed the first time one is claimed.
    ///
    /// The callback is a C function pointer, so it cannot capture anything. It
    /// reads which shortcut fired and hops to the main actor to find it.
    private static func installHandler() -> Bool {
        guard handler == nil else { return true }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
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
                guard read == noErr, id.signature == GlobalHotKey.signature else {
                    return OSStatus(eventNotHandledErr)
                }
                let which = id.id
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { GlobalHotKey.registered[which]?.action() }
                }
                return noErr
            },
            1, &spec, nil, &handler
        )
        return status == noErr
    }

    /// `'ItsP'`, so the handler can tell our hot keys from any other one
    /// installed on the same application target.
    nonisolated private static let signature: OSType = 0x4974_7350
}
