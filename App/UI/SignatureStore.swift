import AppKit
import Observation
import PaintKit

/// The saved signatures, shared by every document.
///
/// A signature is not document state. You capture it once and stamp it on
/// everything you ever sign, which is why Preview keeps its own library rather
/// than a per-file one and why this is a singleton.
///
/// **Stored as one keyed PNG per signature, and nothing else.** No index file, no
/// plist of metadata: the directory listing *is* the library, so there is no second
/// source of truth to fall out of step with the files, and a signature that goes
/// missing on disk simply stops appearing instead of leaving a dangling entry.
/// PNG because it is the only format here that carries the alpha the whole feature
/// depends on.
@MainActor
@Observable
final class SignatureStore {
    static let shared = SignatureStore()

    struct Signature: Identifiable, Sendable {
        let id: String
        let bitmap: Bitmap
        /// Sorted on, so the newest capture is offered first.
        let created: Date

        /// A short label for a menu item, since a signature has no name.
        ///
        /// Its proportions are the only thing distinguishing two of them at a
        /// glance, and the menu draws the image anyway — this is what a screen
        /// reader gets.
        var accessibilityLabel: String {
            "Signature, \(bitmap.width) by \(bitmap.height) pixels"
        }
    }

    private(set) var signatures: [Signature] = []

    private init() {
        reload()
    }

    /// Inside the container, so it survives an app update and is covered by the
    /// same sandbox as everything else the app writes.
    private var directory: URL? {
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return nil }
        return support.appendingPathComponent("Signatures", isDirectory: true)
    }

    func reload() {
        guard let directory,
              let entries = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
              )
        else {
            signatures = []
            return
        }

        signatures = entries
            .filter { $0.pathExtension.lowercased() == "png" }
            .compactMap { url in
                guard let bitmap = try? ImageCodec.decode(contentsOf: url) else { return nil }
                let created = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                return Signature(
                    id: url.deletingPathExtension().lastPathComponent,
                    bitmap: bitmap,
                    created: created
                )
            }
            .sorted { $0.created > $1.created }
    }

    /// Key the ink out of `captured` and keep it.
    ///
    /// Extraction happens on the way *in*, once, rather than at every insert: it is
    /// the expensive step, the result is what you actually want to look at in the
    /// library, and storing the raw photo would mean re-deciding what counts as
    /// paper every time you signed something.
    @discardableResult
    func add(capturing captured: Bitmap, colour: PaintColour) throws -> Signature {
        let keyed = try InkExtractor.ink(from: captured, colour: colour.rgba8)
        guard let directory else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )

        let id = UUID().uuidString
        let url = directory.appendingPathComponent("\(id).png")
        try ImageCodec.encode(keyed, as: .png).write(to: url, options: .atomic)
        reload()
        return signatures.first { $0.id == id }
            ?? Signature(id: id, bitmap: keyed, created: Date())
    }

    func remove(_ signature: Signature) {
        guard let directory else { return }
        let url = directory.appendingPathComponent("\(signature.id).png")
        try? FileManager.default.removeItem(at: url)
        reload()
    }
}
