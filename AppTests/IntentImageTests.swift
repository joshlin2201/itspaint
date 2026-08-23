import Foundation
import Testing
import UniformTypeIdentifiers
@testable import ItsPaint

/// Which of the two things a Shortcuts action can hand over gets opened.
///
/// The bug this suite exists for does not crash and does not show an error: pick
/// the bytes when a file URL was available and the window opens fine, untitled,
/// so a save goes to a panel instead of back to the screenshot it came from.
@Suite("Shortcuts image source")
struct IntentImageTests {

    private static let onePixelPNG = Data(base64Encoded: """
        iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==
        """)!

    @Test("A file on disk wins, even when the bytes are there too")
    func fileBeatsBytes() throws {
        let url = URL(fileURLWithPath: "/tmp/shot.png")

        #expect(try IntentImage.source(fileURL: url, type: .png, data: Self.onePixelPNG) == .file(url))
    }

    @Test("Bytes are used when there is no file")
    func bytesWithoutFile() throws {
        #expect(try IntentImage.source(fileURL: nil, type: .png, data: Self.onePixelPNG)
            == .bytes(Self.onePixelPNG))
    }

    /// A remote URL is not a file. Shortcuts can pass one through from a web
    /// step, and handing it to the document controller opens nothing.
    @Test("A non-file URL falls through to the bytes")
    func remoteURLIsNotAFile() throws {
        let remote = URL(string: "https://example.com/shot.png")!

        #expect(try IntentImage.source(fileURL: remote, type: nil, data: Self.onePixelPNG)
            == .bytes(Self.onePixelPNG))
    }

    /// Nothing usable must be an error rather than a silently empty window: an
    /// untitled canvas appearing in place of the image you asked for reads as the
    /// app losing your file.
    @Test("Neither a file nor bytes is an error")
    func nothingIsAnError() {
        #expect(throws: IntentImageError.self) {
            try IntentImage.source(fileURL: nil, type: nil, data: nil)
        }
        #expect(throws: IntentImageError.self) {
            try IntentImage.source(fileURL: nil, type: nil, data: Data())
        }
    }

    /// A type the app cannot open is refused before a window appears. Shortcuts
    /// will hand over whatever the previous step produced, and a text file
    /// opening as a blank canvas is worse than an error.
    @Test("A type that is not an image or a PDF is refused")
    func refusesOtherTypes() {
        #expect(throws: IntentImageError.self) {
            try IntentImage.source(fileURL: URL(fileURLWithPath: "/tmp/notes.txt"),
                                   type: .plainText, data: nil)
        }
    }

    /// A PDF is admitted, because 0.17.0 opens one as a page.
    @Test("A PDF is admitted")
    func admitsPDF() throws {
        let url = URL(fileURLWithPath: "/tmp/contract.pdf")

        #expect(try IntentImage.source(fileURL: url, type: .pdf, data: nil) == .file(url))
    }

    /// The bytes must not be touched when a file URL is going to win.
    ///
    /// `IntentFile.data` maps the file, and for an external file that read only
    /// succeeds inside a security scope this function's caller has not opened
    /// yet. A plain parameter would be evaluated at the call site — this asserts
    /// the autoclosure is not.
    @Test("The bytes are not read when a file wins")
    func fileBranchNeverReadsBytes() throws {
        nonisolated(unsafe) var reads = 0
        let url = URL(fileURLWithPath: "/tmp/shot.png")

        _ = try IntentImage.source(fileURL: url, type: .png, data: {
            reads += 1
            return Self.onePixelPNG
        }())

        #expect(reads == 0)
    }
}
