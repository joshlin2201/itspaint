import AppKit
import Foundation
import Testing
@testable import ItsPaint

/// What "Edit in ItsPaint" is allowed to open.
///
/// The same failure the screenshot watcher guards against, arriving through a
/// different door: the Services menu hands over whatever the user had selected,
/// and a folder of two hundred screenshots is one click away from two hundred
/// windows. This suite is the ceiling and the filter.
@Suite("Edit in ItsPaint service")
struct ImageServiceTests {

    /// A 1x1 PNG, as real bytes. The filter reads each file's content type,
    /// which comes from the data and not from the extension.
    private static let onePixelPNG = Data(base64Encoded: """
        iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==
        """)!

    private func makeFolder(_ build: (URL) throws -> Void) throws -> URL {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("service-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try build(folder)
        return folder
    }

    /// A pasteboard of our own, so a test never touches the machine's clipboard.
    private func pasteboard(with urls: [URL]) -> NSPasteboard {
        let board = NSPasteboard(name: NSPasteboard.Name("itspaint-test-\(UUID().uuidString)"))
        board.clearContents()
        board.writeObjects(urls.map { $0 as NSURL })
        return board
    }

    @Test("Images are admitted, and nothing else is")
    func admitsOnlyImages() throws {
        let folder = try makeFolder { folder in
            try Self.onePixelPNG.write(to: folder.appendingPathComponent("shot.png"))
            try "notes".write(
                to: folder.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8
            )
            try FileManager.default.createDirectory(
                at: folder.appendingPathComponent("Archive"), withIntermediateDirectories: true
            )
        }
        defer { try? FileManager.default.removeItem(at: folder) }

        let everything = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil
        )
        let admitted = ImageService.openableFiles(on: pasteboard(with: everything))

        #expect(admitted.map(\.lastPathComponent) == ["shot.png"])
    }

    /// The ceiling, and the control that proves the ceiling is not just "ten".
    ///
    /// A cap implemented as an unconditional `prefix` would pass a test that only
    /// checked the over-limit case, and would then be indistinguishable from a
    /// filter that always returns ten — so the under-limit case is asserted too.
    @Test("A selection above the cap is trimmed, and one below it is not")
    func capsWithoutTruncatingSmallSelections() throws {
        let over = try makeFolder { folder in
            for index in 0..<(ImageService.maxFiles + 2) {
                try Self.onePixelPNG.write(
                    to: folder.appendingPathComponent(String(format: "shot-%02d.png", index))
                )
            }
        }
        let under = try makeFolder { folder in
            for index in 0..<3 {
                try Self.onePixelPNG.write(
                    to: folder.appendingPathComponent("small-\(index).png")
                )
            }
        }
        defer {
            try? FileManager.default.removeItem(at: over)
            try? FileManager.default.removeItem(at: under)
        }

        let overFiles = try FileManager.default.contentsOfDirectory(
            at: over, includingPropertiesForKeys: nil
        )
        let underFiles = try FileManager.default.contentsOfDirectory(
            at: under, includingPropertiesForKeys: nil
        )

        #expect(overFiles.count == ImageService.maxFiles + 2)
        #expect(ImageService.openableFiles(on: pasteboard(with: overFiles)).count
            == ImageService.maxFiles)
        #expect(ImageService.openableFiles(on: pasteboard(with: underFiles)).count == 3)
    }

    /// Which ten, when there are more than ten.
    ///
    /// Pasteboard order is whatever order the sending app wrote, so without a
    /// sort the cap keeps an arbitrary and unrepeatable subset.
    @Test("The kept files are the first by name, not by pasteboard order")
    func capIsDeterministic() throws {
        let folder = try makeFolder { folder in
            for index in 0..<(ImageService.maxFiles + 2) {
                try Self.onePixelPNG.write(
                    to: folder.appendingPathComponent(String(format: "shot-%02d.png", index))
                )
            }
        }
        defer { try? FileManager.default.removeItem(at: folder) }

        let files = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil
        )
        let kept = ImageService.openableFiles(on: pasteboard(with: files.reversed()))

        #expect(kept.map(\.lastPathComponent)
            == (0..<ImageService.maxFiles).map { String(format: "shot-%02d.png", $0) })
    }

    /// An empty pasteboard must come back empty rather than throwing, because
    /// the service is reachable from any app and some of them send nothing
    /// useful at all.
    @Test("Nothing on the pasteboard admits nothing")
    func emptyPasteboardAdmitsNothing() {
        #expect(ImageService.openableFiles(on: pasteboard(with: [])).isEmpty)
    }
}
