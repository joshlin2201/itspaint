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

    /// The declared type is checked here rather than on the `@Parameter`.
    /// `supportedContentTypes:` would do it in the Shortcuts picker itself, and
    /// it is macOS 15 only — this app runs on 14, so the filter has to live
    /// somewhere a test can reach anyway.
    ///
    /// A `nil` type is not a rejection. Shortcuts passes bytes with no type from
    /// plenty of steps, and the decoder is the honest oracle for those.
    static func source(fileURL: URL?, data: Data?, type: UTType?) throws -> IntentImage {
        if let type, !type.conforms(to: .image), !type.conforms(to: .pdf) {
            throw IntentImageError.cannotDecode
        }
        if let fileURL, fileURL.isFileURL { return .file(fileURL) }
        if let data, !data.isEmpty { return .bytes(data) }
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

    @Parameter(title: "Image")
    var file: IntentFile

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$file) in ItsPaint")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        switch try IntentImage.source(fileURL: file.fileURL, data: file.data, type: file.type) {
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
