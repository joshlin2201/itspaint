import AppKit
import PaintKit
import UniformTypeIdentifiers

/// Open screenshots in ItsPaint the moment they land.
///
/// A paint app gets opened when you remember it exists. A capture tool gets
/// opened without thinking, dozens of times a day, and the gap between those two
/// is most of why this app is not part of anyone's routine. macOS already takes
/// the screenshot and already writes it somewhere; the only missing step is
/// being the thing that catches it.
///
/// **This costs one open panel, once.** `ItsPaint.entitlements` grants
/// `files.user-selected.read-write` and app-scoped bookmarks and deliberately not
/// `assets.pictures` or any blanket read, so a sandboxed process cannot watch
/// `~/Desktop` — where `com.apple.screencapture location` puts shots by default —
/// until the user hands it over. The bookmark then carries that grant across
/// launches on the same machinery recent documents already use. No TCC prompt, no
/// Screen Recording, no Accessibility, and nothing about the existing screenshot
/// workflow changes: the file still lands where it always did.
///
/// Off until switched on. An app that starts opening windows on its own, because
/// of a folder the user does not remember granting, is not a feature.
@MainActor
@Observable
final class ScreenshotWatcher {
    static let shared = ScreenshotWatcher()

    private enum Key {
        static let enabled = "watchScreenshotFolder"
        static let bookmark = "screenshotFolderBookmark"
    }

    /// The folder being watched, when there is one and its bookmark still resolves.
    private(set) var folder: URL?

    /// Off by default, and it stays off if the bookmark no longer resolves —
    /// a moved or deleted folder should surface as "pick one" rather than as a
    /// switch that is on and quietly watching nothing.
    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Key.enabled)
            isEnabled ? start() : stop()
        }
    }

    /// Set when the folder cannot be watched, so the UI can say why instead of
    /// showing an enabled switch over a dead directory.
    private(set) var problem: String?

    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private var accessing: URL?

    /// Names present when watching began. Everything here is pre-existing and is
    /// never opened: switching this on must not throw a window up for every
    /// screenshot already sitting on the Desktop.
    private var known: Set<String> = []

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: Key.enabled)
        folder = resolveBookmark()
        if isEnabled { start() }
    }

    // MARK: - Choosing the folder

    /// Ask for the screenshot folder, defaulting to wherever macOS is currently
    /// putting them so the common case is one click on a pre-selected directory.
    func chooseFolder(completion: @escaping (Bool) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Watch This Folder"
        panel.message = "Choose the folder macOS saves screenshots to. "
            + "ItsPaint will open new images that appear in it."
        panel.directoryURL = Self.systemScreenshotLocation

        panel.begin { [weak self] response in
            guard let self, response == .OK, let picked = panel.url else {
                completion(false)
                return
            }
            MainActor.assumeIsolated {
                self.adopt(picked)
                completion(self.folder != nil)
            }
        }
    }

    /// Where the system is set to save screenshots.
    ///
    /// `com.apple.screencapture location` is only written once someone has
    /// changed it, so its absence means the default rather than "unknown".
    /// Reading another domain's defaults is allowed under the sandbox for this
    /// key; it is a hint for the panel's starting directory, never access.
    static var systemScreenshotLocation: URL {
        let fallback = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        guard let raw = UserDefaults(suiteName: "com.apple.screencapture")?
            .string(forKey: "location"), !raw.isEmpty
        else { return fallback }
        return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
    }

    private func adopt(_ url: URL) {
        do {
            let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(data, forKey: Key.bookmark)
            stop()
            folder = url
            problem = nil
            if isEnabled { start() }
        } catch {
            problem = "That folder could not be saved for next launch: "
                + error.localizedDescription
        }
    }

    private func resolveBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: Key.bookmark) else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }
        // A stale bookmark still resolves; re-saving it keeps the grant alive
        // across the folder being moved or renamed.
        if stale, let fresh = try? url.bookmarkData(
            options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil
        ) {
            UserDefaults.standard.set(fresh, forKey: Key.bookmark)
        }
        return url
    }

    // MARK: - Watching

    private func start() {
        stop()
        guard let folder else {
            problem = "Choose a folder to watch."
            return
        }

        // The security-scoped grant has to be held for as long as the directory
        // is open, not just while resolving the bookmark.
        guard folder.startAccessingSecurityScopedResource() else {
            problem = "ItsPaint no longer has permission to read that folder. Choose it again."
            return
        }
        accessing = folder

        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else {
            problem = "That folder could not be opened for watching."
            releaseAccess()
            return
        }
        descriptor = fd
        known = Self.imageNames(in: folder)
        problem = nil

        // `.write` on the directory covers a file appearing in it. `.delete` and
        // `.rename` are watched too so the source tears itself down instead of
        // holding a descriptor for a directory that is no longer there.
        let created = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        // Reads the event off `self.source` rather than capturing `created`,
        // which would be the source retaining a closure that retains the source.
        created.setEventHandler { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated {
                let event = self.source?.data ?? []
                if event.contains(.delete) || event.contains(.rename) {
                    self.problem = "The watched folder was moved or deleted. Choose it again."
                    self.stop()
                    return
                }
                self.directoryChanged()
            }
        }
        // Ownership of the descriptor passes to the source, by value.
        //
        // Reading `self.descriptor` here instead would close whatever descriptor
        // the property holds *when cancellation lands*, not the one this source
        // was built on — and `stop()` is the first thing `start()` does, so a
        // restart opens a new directory and reassigns that property before the
        // old cancel handler has run. The watcher would then be holding a source
        // for a descriptor its own predecessor had closed.
        descriptor = -1
        created.setCancelHandler { close(fd) }
        source = created
        created.resume()
    }

    private func stop() {
        // Whoever owns the descriptor closes it, and only one of them does.
        //
        // Closing it here while a source is cancelling is a use-after-close: the
        // source still holds the number until cancellation completes, and the
        // kernel is free to hand that number to the next `open` in the process.
        // So when a source exists, its cancel handler closes; only when there is
        // no source is closing here correct. Writing this as
        // `source = nil; if source == nil { close() }` reads like a check and is
        // an unconditional close.
        if let live = source {
            source = nil
            live.cancel()
        } else {
            closeDescriptor()
        }
        releaseAccess()
        known = []
    }

    private func closeDescriptor() {
        if descriptor >= 0 {
            close(descriptor)
            descriptor = -1
        }
    }

    private func releaseAccess() {
        accessing?.stopAccessingSecurityScopedResource()
        accessing = nil
    }

    // MARK: - Opening what lands

    private func directoryChanged() {
        guard let folder else { return }
        let now = Self.imageNames(in: folder)
        let appeared = now.subtracting(known)
        // Recorded before anything is opened, and set to the full listing rather
        // than the union: a file that appears and is deleted again must not come
        // back as "new" the next time the directory changes.
        known = now
        for name in appeared.sorted() {
            openWhenComplete(folder.appendingPathComponent(name))
        }
    }

    /// Open the file once it has stopped growing.
    ///
    /// The directory event fires when the entry appears, which is before the
    /// bytes are all there. Decoding then yields a truncated image or nothing at
    /// all, and the failure looks like a broken screenshot rather than a race.
    /// Waiting for the size to hold still twice is cruder than watching for a
    /// close, and it does not need a second API or an exclusive open.
    private func openWhenComplete(_ url: URL, attempt: Int = 0, lastSize: Int = -1) {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1

        // ~3s at 150ms. A screenshot that has not settled by then is not one.
        guard attempt < 20 else { return }
        guard size > 0, size == lastSize else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                MainActor.assumeIsolated {
                    self?.openWhenComplete(url, attempt: attempt + 1, lastSize: size)
                }
            }
            return
        }

        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in
            // A failure here is not worth an alert. The file is still on disk
            // exactly where the user expects it, and an app that throws a modal
            // because something it was watching could not be decoded is worse
            // than one that stays quiet.
        }
    }

    /// Image files directly in the folder, by name.
    ///
    /// Not recursive: screenshots land beside each other, and walking a Desktop
    /// full of folders to find them would be work for nothing.
    ///
    /// Internal rather than private so a test can check what it admits. This is
    /// the function that decides what gets opened on somebody's Desktop, and the
    /// bad outcome is not subtle.
    ///
    /// `nonisolated` because it reads a directory and returns names — it touches
    /// no state on this actor, and inheriting the class's `@MainActor` would make
    /// a pure function callable only from the main thread for no reason.
    nonisolated static func imageNames(in folder: URL) -> Set<String> {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentTypeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )) ?? []

        return Set(contents.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isDirectoryKey])
            guard values?.isDirectory != true,
                  let type = values?.contentType,
                  type.conforms(to: .image)
            else { return nil }
            return url.lastPathComponent
        })
    }
}
