import AppIntents
import AppKit
import PaintKit
import UniformTypeIdentifiers

/// Where a Shortcuts action's image actually comes from.
///
/// Shortcuts hands over an `IntentFile` that may carry a file on disk, bytes in
/// memory, or both. The two routes are not interchangeable: a file URL keeps the
/// document tied to a real path, so a save goes back where the image came from,
/// while bytes can only ever become an untitled window. Preferring the URL is
/// the whole difference between "mark up this screenshot" and "mark up a copy of
/// this screenshot that you now have to file somewhere".
///
/// Split out and testable because the failure is silent: a wrong branch here
/// still opens a window, and nobody notices until a save lands in the wrong
/// place — or does not land at all.
enum IntentImage: Equatable {
    case file(URL)
    case bytes(Data)

    /// The picker filters by type as well (`supportedTypeIdentifiers` on the
    /// parameter), and this is the second check behind it: Shortcuts can hand an
    /// action a file the picker never saw, and a type nobody looked at opens a
    /// blank window instead of an error.
    ///
    /// A `nil` type is not a rejection. Shortcuts passes bytes with no type from
    /// plenty of steps, and the decoder is the honest oracle for those.
    ///
    /// **`data` is an autoclosure on purpose.** `IntentFile.data` maps the file's
    /// contents, and for an external file that read has to happen inside
    /// `startAccessingSecurityScopedResource()`. Evaluating it as an argument
    /// would do the read before the scope is open — a sandbox failure on the path
    /// that was never going to use the bytes, and a needless map of a large file
    /// on the path that was.
    static func source(
        fileURL: URL?, type: UTType?, data: @autoclosure () -> Data?
    ) throws -> IntentImage {
        if let type, !type.conforms(to: .image), !type.conforms(to: .pdf) {
            throw IntentImageError.cannotDecode
        }
        if let fileURL, fileURL.isFileURL { return .file(fileURL) }
        if let bytes = data(), !bytes.isEmpty { return .bytes(bytes) }
        throw IntentImageError.nothingToOpen
    }
}

enum IntentImageError: LocalizedError {
    case nothingToOpen
    case cannotDecode

    var errorDescription: String? {
        switch self {
        case .nothingToOpen: "That item has no image in it."
        case .cannotDecode: "That is not an image ItsPaint can open."
        }
    }
}

/// "Open in ItsPaint" as a Shortcuts action.
///
/// The point is not automation for its own sake. A Shortcuts action is a door:
/// it puts the app in the Shortcuts gallery, makes it reachable from Spotlight
/// and a Quick Action, and lets someone put a markup step inside a shortcut they
/// already run — none of which requires them to remember the app exists, which
/// is the whole problem a paint app has.
struct OpenImageIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Image in ItsPaint"

    static let description = IntentDescription(
        "Opens an image or PDF page in a new ItsPaint window, ready to mark up."
    )

    /// The window is the result, so the app has to come forward. A markup action
    /// that completes in the background has done nothing anyone can see.
    static let openAppWhenRun = true

    /// `supportedTypeIdentifiers` rather than `supportedContentTypes`, which is
    /// macOS 15. Without either, the parameter defaults to `public.item` and
    /// Shortcuts offers to feed the action an archive or a sound file.
    @Parameter(title: "Image", supportedTypeIdentifiers: ["public.image", "com.adobe.pdf"])
    var file: IntentFile

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$file) in ItsPaint")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        switch try IntentImage.source(fileURL: file.fileURL, type: file.type, data: file.data) {
        case .file(let url):
            // Shortcuts passes a security-scoped URL. Without the accessor the
            // read fails inside the sandbox, and the failure looks like a corrupt
            // file rather than a missing grant.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            try await NSDocumentController.shared.openDocument(
                withContentsOf: url, display: true
            )

        case .bytes(let data):
            guard let bitmap = ImageCodec.decode(data: data) else {
                throw IntentImageError.cannotDecode
            }
            try NewDocument.open(with: bitmap)
        }

        return .result()
    }
}

/// The phrases and the gallery tile.
///
/// One action, one tile. A provider that registers six variations of the same
/// verb fills the gallery with noise and gets the app ignored in it.
struct ItsPaintShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenImageIntent(),
            phrases: [
                "Open an image in \(.applicationName)",
                "Mark up an image with \(.applicationName)",
            ],
            shortTitle: "Open Image",
            systemImageName: "paintbrush.pointed"
        )
    }
}
