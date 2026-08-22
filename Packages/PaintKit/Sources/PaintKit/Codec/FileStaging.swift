import Foundation

/// Build a file somewhere safe, then put it where it was asked for.
///
/// **The staging copy lives in this app's own temporary directory and never
/// beside the destination.** A sandboxed app is granted the *path the user
/// chose in the save panel* — not its folder — so a sibling
/// `.itspaint-<uuid>.pdf` next to the chosen file is a new path nobody granted.
/// Core Graphics reported that as a destination it could not create, the export
/// surfaced *Couldn't write the image as PDF*, and the recovery text sent people
/// to PNG, which took the same denied route. The format was never the problem.
///
/// Staging still buys what it was added for: the bytes land under their final
/// name only once the encoder has finished, so a failure half-way through cannot
/// leave someone with a truncated version of their artwork.
enum FileStaging {

    /// Run `body` against a staging URL, then move the result onto `url`.
    ///
    /// The staging file keeps the destination's last path component, so an
    /// encoder that reads the extension sees the one the user typed.
    static func replaceItem(at url: URL, writing body: (URL) throws -> Void) throws {
        let manager = FileManager.default
        let staging = manager.temporaryDirectory
            .appendingPathComponent("itspaint-write-\(UUID().uuidString)", isDirectory: true)

        do {
            try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        } catch {
            // No staging area at all — a full or read-only container. The
            // destination is the only place left, and refusing to save at that
            // point would lose the work outright.
            try body(url)
            return
        }
        defer { try? manager.removeItem(at: staging) }

        let temporary = staging.appendingPathComponent(url.lastPathComponent)
        try body(temporary)

        do {
            if manager.fileExists(atPath: url.path) {
                _ = try manager.replaceItemAt(url, withItemAt: temporary)
            } else {
                try manager.moveItem(at: temporary, to: url)
            }
        } catch {
            // Moving into place is a directory operation, and the grant may
            // cover only the file itself; the same is true across volumes, where
            // a rename cannot work at all. Writing the finished bytes *into* the
            // granted path is the route that is left, and by this point they are
            // complete — the encoder has already succeeded.
            try copy(from: temporary, onto: url)
        }
    }

    /// Stream a finished file onto an existing path, in place.
    ///
    /// **Nothing is deleted first.** The obvious version — remove the
    /// destination, then copy — spends a moment where the user's artwork exists
    /// nowhere but a temporary directory, and if the copy then fails they have
    /// lost the file they were saving over. Truncating and writing keeps the
    /// path, and a chunked copy keeps a 100 MB export from being held in memory
    /// twice on the way through.
    static func copy(from source: URL, onto destination: URL) throws {
        let manager = FileManager.default
        if !manager.fileExists(atPath: destination.path) {
            guard manager.createFile(atPath: destination.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }

        let reading = try FileHandle(forReadingFrom: source)
        defer { try? reading.close() }
        let writing = try FileHandle(forWritingTo: destination)
        defer { try? writing.close() }
        try writing.truncate(atOffset: 0)

        while let chunk = try reading.read(upToCount: 1 << 20), !chunk.isEmpty {
            try writing.write(contentsOf: chunk)
        }
        try writing.synchronize()
    }
}
