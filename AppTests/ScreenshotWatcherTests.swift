import Foundation
import Testing
@testable import ItsPaint

/// What the screenshot watcher is allowed to open.
///
/// The failure this guards against is not cosmetic: the watcher points at a
/// folder the user chose, which for most people is the Desktop. Admitting the
/// wrong entries there means opening a window per file — a directory, a PDF, a
/// hundred old screenshots — the moment the switch goes on.
@Suite("Screenshot watcher")
struct ScreenshotWatcherTests {

    private func makeFolder(_ build: (URL) throws -> Void) throws -> URL {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("watcher-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try build(folder)
        return folder
    }

    /// A 1x1 PNG. Written as real bytes because the filter reads the file's
    /// content type, which comes from the data and not from the extension.
    private static let onePixelPNG = Data(base64Encoded: """
        iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==
        """)!

    @Test("Images are admitted, and nothing else is")
    func admitsOnlyImages() throws {
        let folder = try makeFolder { folder in
            try Self.onePixelPNG.write(to: folder.appendingPathComponent("Screenshot 1.png"))
            try Self.onePixelPNG.write(to: folder.appendingPathComponent("Screenshot 2.png"))
            // Not an image, and the one a naive extension check would let through.
            try Data("notes".utf8).write(to: folder.appendingPathComponent("notes.txt"))
            // A directory. `contentsOfDirectory` returns these too.
            try FileManager.default.createDirectory(
                at: folder.appendingPathComponent("a folder"), withIntermediateDirectories: true
            )
            // A directory whose name ends in an image extension — a real shape on
            // a Mac, and one that a suffix test admits and then fails to decode.
            try FileManager.default.createDirectory(
                at: folder.appendingPathComponent("bundle.png"), withIntermediateDirectories: true
            )
            // Hidden files are skipped, so a partial download must not appear.
            try Self.onePixelPNG.write(to: folder.appendingPathComponent(".hidden.png"))
        }
        defer { try? FileManager.default.removeItem(at: folder) }

        let found = ScreenshotWatcher.imageNames(in: folder)

        #expect(found == ["Screenshot 1.png", "Screenshot 2.png"])
    }

    @Test("A folder that cannot be read is empty, not a crash")
    func missingFolderIsEmpty() {
        let nowhere = URL(fileURLWithPath: "/var/empty/does-not-exist-\(UUID().uuidString)")

        #expect(ScreenshotWatcher.imageNames(in: nowhere).isEmpty)
    }

    /// The diff, stated as a test because the consequence of getting it backwards
    /// is a window for every screenshot already on the Desktop.
    @Test("Only names that were not there before count as new")
    func onlyNewNamesCount() throws {
        let folder = try makeFolder { folder in
            try Self.onePixelPNG.write(to: folder.appendingPathComponent("old.png"))
        }
        defer { try? FileManager.default.removeItem(at: folder) }

        let atStart = ScreenshotWatcher.imageNames(in: folder)
        #expect(atStart == ["old.png"])

        try Self.onePixelPNG.write(to: folder.appendingPathComponent("new.png"))
        let afterwards = ScreenshotWatcher.imageNames(in: folder)

        #expect(afterwards.subtracting(atStart) == ["new.png"], "the pre-existing file came back as new")
        #expect(afterwards.count == 2)
    }
}
