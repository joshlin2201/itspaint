import AppKit
import PaintKit
import UniformTypeIdentifiers

/// "Edit in ItsPaint", wherever macOS already offers to hand an image somewhere.
///
/// The Services menu is the oldest and cheapest of those doors: select an image
/// in the Finder, or a picture in Mail or Safari, and the app appears under
/// **Services** without being launched, without a share sheet, and without a
/// single permission prompt. The pasteboard the system hands over is the grant —
/// the sandbox lets us read exactly what the user chose to send and nothing else,
/// which is the same bargain the open panel makes.
///
/// Registered at launch. `NSApp.servicesProvider` is what makes the `NSServices`
/// entry in `Info.plist` do anything: without it the menu item appears, does
/// nothing, and looks broken.
@MainActor
final class ImageService: NSObject {
    static let shared = ImageService()

    /// The most windows one invocation may open.
    ///
    /// Selecting a folder of screenshots in the Finder and picking a service is
    /// one gesture, and without a ceiling it is one gesture that opens two
    /// hundred windows. Ten is enough for the real case — a handful of shots for
    /// one bug report — and small enough that the mistake is recoverable by hand.
    ///
    /// `nonisolated` because the filter below is, and a main-actor constant read
    /// from a nonisolated function does not compile under strict concurrency.
    nonisolated static let maxFiles = 10

    /// Image files on a pasteboard, in name order, capped.
    ///
    /// Internal and `nonisolated` for the same reason the watcher's filter is:
    /// this is the function that decides what gets opened, the bad outcome is a
    /// screenful of windows, and a test has to be able to call it.
    ///
    /// Sorted because the cap has to be deterministic. Pasteboard order is the
    /// selection order the sending app happened to use, so "the first ten" would
    /// otherwise mean a different ten each time.
    nonisolated static func openableFiles(on board: NSPasteboard) -> [URL] {
        let urls = board.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []

        let images = urls.filter { url in
            let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isDirectoryKey])
            guard values?.isDirectory != true, let type = values?.contentType else { return false }
            return ImageCodec.readableContentTypes.contains { type.conforms(to: $0) }
        }

        return Array(images.sorted { $0.lastPathComponent < $1.lastPathComponent }
            .prefix(maxFiles))
    }

    /// The Services entry point. The selector name is the `NSMessage` value in
    /// `Info.plist`; changing one without the other silently unhooks the menu.
    @objc func openImageFromService(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        NSApp.activate(ignoringOtherApps: true)

        let files = Self.openableFiles(on: pasteboard)
        if !files.isEmpty {
            for url in files {
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in
                    // Quiet on failure, as the watcher is: the file is still on
                    // disk where the user left it, and a modal for something they
                    // pointed at in another app is worse than an absent window.
                }
            }
            return
        }

        // No file, but the sender may have put pixels on the pasteboard — a
        // selection in Preview, an image dragged out of a web page.
        guard Bitmap.canDecode(pasteboard: pasteboard) else {
            error.pointee = "That is not an image ItsPaint can open." as NSString
            return
        }

        do {
            try NewDocument.open(with: Bitmap(pasteboard: pasteboard))
        } catch let failure {
            error.pointee = failure.localizedDescription as NSString
        }
    }
}

/// Opening a window on an image that came from outside any document.
///
/// Shared by the clipboard shortcut and the Services entry because both arrive
/// the same way: an image from somewhere else, no document to put it in, and the
/// wrong answer is pasting it into whatever happened to be frontmost.
enum NewDocument {
    @MainActor
    static func open(with bitmap: Bitmap) throws {
        guard let document = try NSDocumentController.shared
            .openUntitledDocumentAndDisplay(false) as? DrawingDocument
        else { throw NewDocumentError.noDocument }

        // `load` rather than `replaceCanvas`: this is the document's initial
        // content, not an edit to it. The undo-recording path would open a window
        // already dirty, offering to save a file that never existed.
        document.model.load(canvas: bitmap, metadata: nil)
        document.makeWindowControllers()
        document.showWindows()
    }
}

enum NewDocumentError: LocalizedError {
    case noDocument

    var errorDescription: String? { "That image could not be opened." }
}
