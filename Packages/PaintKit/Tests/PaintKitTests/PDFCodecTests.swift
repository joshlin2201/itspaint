import CoreGraphics
import CoreText
import Foundation
import Testing

@testable import PaintKit

/// Opening a PDF, signing a page, and getting the *document* back.
///
/// The feature these tests defend is the one thing a signature is for: the other
/// pages of the contract still being there, and the page still being the size it
/// was printed at.
struct PDFCodecTests {

    /// A PDF with `pages` letter pages, each carrying real text so a rasterised
    /// page can be told apart from a blank one.
    private func sampleDocument(pages: Int, size: CGSize = CGSize(width: 612, height: 792)) throws -> Data {
        let output = NSMutableData()
        let consumer = try #require(CGDataConsumer(data: output))
        var box = CGRect(origin: .zero, size: size)
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))

        for page in 1...pages {
            context.beginPDFPage(nil)
            let font = CTFontCreateWithName("Helvetica" as CFString, 36, nil)
            let line = CTLineCreateWithAttributedString(NSAttributedString(
                string: "Page \(page)",
                attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
            ))
            context.textPosition = CGPoint(x: 72, y: size.height - 120)
            CTLineDraw(line, context)
            context.endPDFPage()
        }
        context.closePDF()
        return output as Data
    }

    private func pageCount(of data: Data) throws -> Int {
        let provider = try #require(CGDataProvider(data: data as CFData))
        let document = try #require(CGPDFDocument(provider))
        return document.numberOfPages
    }

    private func pageSize(of data: Data, page: Int) throws -> CGSize {
        let provider = try #require(CGDataProvider(data: data as CFData))
        let document = try #require(CGPDFDocument(provider))
        let page = try #require(document.page(at: page))
        return page.getBoxRect(.mediaBox).size
    }

    @Test("A page opens as pixels, at twice its point size")
    func opensAPage() throws {
        let (bitmap, source) = try PDFCodec.open(
            data: try sampleDocument(pages: 1), named: "contract.pdf"
        )
        #expect(source.pageCount == 1)
        #expect(source.pageIndex == 0)
        #expect(source.renderScale == PDFCodec.preferredScale)
        #expect(source.pageSize == CGSize(width: 612, height: 792))
        #expect(bitmap.width == 1224)
        #expect(bitmap.height == 1584)
    }

    @Test("The page arrives on white paper, with its ink on it")
    func rendersInkOnPaper() throws {
        let (bitmap, _) = try PDFCodec.open(
            data: try sampleDocument(pages: 1), named: "contract.pdf"
        )
        let corner = try #require(bitmap.pixel(at: PixelPoint(x: 4, y: 4)))
        #expect(corner == RGBA8(r: 255, g: 255, b: 255, a: 255))

        // Somewhere in the text band there has to be ink, or the page rendered
        // blank and the signature would be laid over nothing.
        var darkest = 255
        for y in 130..<220 {
            for x in 140..<600 {
                if let pixel = bitmap.pixel(at: PixelPoint(x: x, y: y)) {
                    darkest = min(darkest, Int(pixel.r))
                }
            }
        }
        #expect(darkest < 100, "no text found on the rasterised page")
    }

    @Test("Signing page two keeps all five pages and their size")
    func writeBackKeepsEveryPage() throws {
        let original = try sampleDocument(pages: 5)
        var (bitmap, source) = try PDFCodec.open(data: original, page: 1, named: "lease.pdf")

        // The signature: a black block where nobody's text is.
        Raster.fillRect(
            PixelRect(x: 100, y: bitmap.height - 300, width: 400, height: 80),
            colour: .black, into: &bitmap
        )

        let signed = try PDFCodec.encode(bitmap, replacing: source)
        #expect(try pageCount(of: signed) == 5)
        for page in 1...5 {
            #expect(try pageSize(of: signed, page: page) == CGSize(width: 612, height: 792))
        }

        // And the edited page really is the edited one: reopening it finds the
        // block, while its neighbour is untouched paper there.
        let reopened = try PDFCodec.open(data: signed, page: 1, named: "lease.pdf")
        let inSignature = try #require(
            reopened.bitmap.pixel(at: PixelPoint(x: 300, y: reopened.bitmap.height - 260))
        )
        #expect(inSignature.r < 60)

        let neighbour = try PDFCodec.open(data: signed, page: 2, named: "lease.pdf")
        let sameSpot = try #require(
            neighbour.bitmap.pixel(at: PixelPoint(x: 300, y: neighbour.bitmap.height - 260))
        )
        #expect(sameSpot.r > 200)

        source = reopened.source
        #expect(source.pageIndex == 1)
        #expect(source.pageCount == 5)
    }

    @Test("A cropped page comes back smaller, not stretched")
    func croppingShrinksThePage() throws {
        let (bitmap, source) = try PDFCodec.open(
            data: try sampleDocument(pages: 1), named: "form.pdf"
        )
        let cropped = try #require(ImageTransform.cropped(
            bitmap, to: PixelRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height / 2)
        ))
        let written = try PDFCodec.encode(cropped, replacing: source)
        #expect(try pageSize(of: written, page: 1) == CGSize(width: 612, height: 396))
    }

    @Test("A canvas that never came from a PDF is one page, a point per pixel")
    func plainCanvasBecomesOnePage() throws {
        let bitmap = Bitmap(width: 300, height: 200, fill: .white)
        let data = try PDFCodec.encode(bitmap, replacing: nil)
        #expect(try pageCount(of: data) == 1)
        #expect(try pageSize(of: data, page: 1) == CGSize(width: 300, height: 200))
    }

    @Test("PDF is writable and exportable, whatever ImageIO thinks")
    func pdfIsOffered() {
        #expect(ImageCodec.Format.pdf.isWritable)
        #expect(ImageCodec.Format.exportable.contains(.pdf))
    }

    @Test("Opening a PDF through the image codec goes to the PDF reader")
    func imageCodecOpensPDFs() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("statement.pdf")
        try sampleDocument(pages: 2).write(to: url)

        let bitmap = try ImageCodec.decode(contentsOf: url)
        #expect(bitmap.width == 1224)
        #expect(bitmap.height == 1584)
    }

    @Test("Damaged bytes fail with something a person can act on")
    func rejectsRubbish() {
        #expect(throws: PDFCodec.Failure.unreadable("nonsense.pdf")) {
            try PDFCodec.open(data: Data("not a pdf at all".utf8), named: "nonsense.pdf")
        }
    }

    /// The export bug: a staged write must never create a second file in the
    /// directory the save panel granted a single path in.
    @Test("Writing a file leaves nothing else behind in the destination folder")
    func writingCreatesNoSiblings() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let bitmap = Bitmap(width: 32, height: 32, fill: .white)
        for format in ImageCodec.Format.exportable {
            let url = directory.appendingPathComponent("art.\(format.fileExtension)")
            try ImageCodec.write(bitmap, to: url, as: format)
            #expect(FileManager.default.fileExists(atPath: url.path))

            let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            #expect(
                contents == ["art.\(format.fileExtension)"],
                "\(format.displayName) left \(contents) in the destination folder"
            )
            try FileManager.default.removeItem(at: url)
        }
    }

    /// The route taken when the sandbox will not let the staged file be moved
    /// into place: the destination is written *through*, never deleted first.
    @Test("The in-place fallback replaces the bytes and keeps the same file")
    func inPlaceFallbackKeepsTheFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let destination = directory.appendingPathComponent("art.png")
        try Data(repeating: 0x41, count: 4096).write(to: destination)
        let before = try FileManager.default.attributesOfItem(atPath: destination.path)

        let staged = directory.appendingPathComponent("staged.png")
        let fresh = Data(repeating: 0x42, count: 3 << 20)
        try fresh.write(to: staged)

        try FileStaging.copy(from: staged, onto: destination)

        #expect(try Data(contentsOf: destination) == fresh, "the file was not fully replaced")
        let after = try FileManager.default.attributesOfItem(atPath: destination.path)
        #expect(
            before[.systemFileNumber] as? Int == after[.systemFileNumber] as? Int,
            "the destination was recreated rather than written through"
        )

        // And onto a path that does not exist yet, which is the ordinary export.
        let new = directory.appendingPathComponent("new.png")
        try FileStaging.copy(from: staged, onto: new)
        #expect(try Data(contentsOf: new) == fresh)
    }

    @Test("Overwriting an existing file replaces it and stages nothing beside it")
    func overwritingIsClean() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("art.png")
        try Data("stale".utf8).write(to: url)
        try ImageCodec.write(Bitmap(width: 16, height: 16, fill: .black), to: url, as: .png)

        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["art.png"])
        let reopened = try ImageCodec.decode(contentsOf: url)
        #expect(reopened.width == 16)
    }
}
