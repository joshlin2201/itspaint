import AppKit
import CoreGraphics
import CoreText
import Foundation
import PaintKit
import Testing
@testable import ItsPaint

/// Signing a PDF, at the document layer.
///
/// PaintKit proves the codec keeps every page; these prove the *document* does —
/// that opening a contract fills the canvas, that the header is told which page
/// it is on, that turning a page keeps what was drawn on the last one, and that
/// Save writes a PDF rather than a picture of one.
@Suite("PDF documents", .serialized)
@MainActor
struct PDFDocumentTests {

    private func container() throws -> URL {
        // Inside the app's own container: these tests run in the sandboxed app,
        // and nowhere else is writable without a save panel.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdf-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writeSample(pages: Int, to url: URL) throws {
        let output = NSMutableData()
        let consumer = try #require(CGDataConsumer(data: output))
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        for page in 1...pages {
            context.beginPDFPage(nil)
            let font = CTFontCreateWithName("Helvetica" as CFString, 32, nil)
            let line = CTLineCreateWithAttributedString(NSAttributedString(
                string: "Agreement — page \(page)",
                attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
            ))
            context.textPosition = CGPoint(x: 64, y: 680)
            CTLineDraw(line, context)
            context.endPDFPage()
        }
        context.closePDF()
        try (output as Data).write(to: url)
    }

    private func pageCount(of url: URL) throws -> Int {
        let document = try #require(CGPDFDocument(url as CFURL))
        return document.numberOfPages
    }

    @Test("Opening a PDF fills the canvas and names the page")
    func opensAPage() throws {
        let directory = try container()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("agreement.pdf")
        try writeSample(pages: 3, to: url)

        let document = DrawingDocument()
        try document.read(from: url, ofType: "com.adobe.pdf")

        #expect(document.model.canvasSize.width == 1224)
        #expect(document.model.canvasSize.height == 1584)
        let page = try #require(document.model.pdfPage)
        #expect(page.index == 0)
        #expect(page.count == 3)
    }

    @Test("Saving a signed page writes a PDF that still has every page")
    func savesEveryPage() throws {
        let directory = try container()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("lease.pdf")
        try writeSample(pages: 4, to: url)

        let document = DrawingDocument()
        try document.read(from: url, ofType: "com.adobe.pdf")

        // Sign it: a stroke, through the engine, exactly as the brush would.
        document.model.selectTool(.brush)
        document.model.brushSize = 12
        document.model.foreground = .black
        document.model.noteChange(document.model.engine.beginStroke(at: PixelPoint(x: 200, y: 1400)))
        document.model.noteChange(document.model.engine.endStroke(at: PixelPoint(x: 600, y: 1420)))

        let saved = directory.appendingPathComponent("lease-signed.pdf")
        try document.write(to: saved, ofType: "com.adobe.pdf")

        #expect(try pageCount(of: saved) == 4)

        // And it reopens as a PDF, on a page the same size as the original.
        let reopened = DrawingDocument()
        try reopened.read(from: saved, ofType: "com.adobe.pdf")
        #expect(reopened.model.canvasSize.width == 1224)
        #expect(reopened.model.canvasSize.height == 1584)
    }

    @Test("Exporting at 200% sharpens the page, it does not double its size")
    func exportScaleDoesNotResizeThePage() throws {
        let directory = try container()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("invoice.pdf")
        try writeSample(pages: 2, to: url)

        let document = DrawingDocument()
        try document.read(from: url, ofType: "com.adobe.pdf")

        let options = ExportOptions()
        options.format = .pdf
        options.scale = 2
        let job = options.job(
            canvas: document.model.canvas,
            matte: .white,
            pdfSource: document.pdfSourceForTesting
        )
        let exported = directory.appendingPathComponent("invoice-2x.pdf")
        try job.write(to: exported)

        let written = try #require(CGPDFDocument(exported as CFURL))
        #expect(written.numberOfPages == 2)
        let page = try #require(written.page(at: 1))
        #expect(page.getBoxRect(.mediaBox).size == CGSize(width: 612, height: 792))
    }

    @Test("Saving over the original keeps the document intact")
    func savingInPlaceIsSafe() throws {
        let directory = try container()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("terms.pdf")
        try writeSample(pages: 3, to: url)

        let document = DrawingDocument()
        try document.read(from: url, ofType: "com.adobe.pdf")
        var canvas = document.model.canvas
        Raster.fillRect(
            PixelRect(x: 100, y: 1200, width: 300, height: 60), colour: .black, into: &canvas
        )
        document.model.engine.reset(to: canvas)

        try document.write(to: url, ofType: "com.adobe.pdf")

        #expect(try pageCount(of: url) == 3)
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["terms.pdf"],
            "saving left a staging file in the document's own folder"
        )

        let reopened = DrawingDocument()
        try reopened.read(from: url, ofType: "com.adobe.pdf")
        let signed = try #require(
            reopened.model.canvas.pixel(at: PixelPoint(x: 200, y: 1230))
        )
        #expect(signed.r < 60, "the mark did not survive saving over the original")
    }

    @Test("Turning the page keeps what was drawn on the page before it")
    func pageTurnKeepsInk() throws {
        let directory = try container()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("contract.pdf")
        try writeSample(pages: 3, to: url)

        let document = DrawingDocument()
        try document.read(from: url, ofType: "com.adobe.pdf")

        // A solid mark low on page one, well clear of the printed line.
        let mark = PixelRect(x: 120, y: 1300, width: 360, height: 90)
        var canvas = document.model.canvas
        Raster.fillRect(mark, colour: .black, into: &canvas)
        document.model.engine.reset(to: canvas)

        document.model.turnToPage(1)
        #expect(try #require(document.model.pdfPage).index == 1)
        let onPageTwo = try #require(
            document.model.canvas.pixel(at: PixelPoint(x: 300, y: 1340))
        )
        #expect(onPageTwo.r > 200, "page two came up carrying page one's ink")

        document.model.turnToPage(0)
        #expect(try #require(document.model.pdfPage).index == 0)
        let backOnPageOne = try #require(
            document.model.canvas.pixel(at: PixelPoint(x: 300, y: 1340))
        )
        #expect(backOnPageOne.r < 60, "the mark on page one was lost by turning the page")
    }

    /// The window, with a contract open in it, rendered to a PNG.
    ///
    /// Same harness as the README captures: set `ITSPAINT_PDF_CAPTURE_OUT` and it
    /// writes the window; unset, it is a plain document test that costs CI
    /// nothing.
    @Test("Captures the window with a PDF open when asked")
    func capturesTheWindow() throws {
        let directory = try container()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Rental agreement.pdf")
        try writeSample(pages: 5, to: url)

        let document = DrawingDocument()
        try document.read(from: url, ofType: "com.adobe.pdf")
        document.fileURL = url
        document.makeWindowControllers()
        document.showWindows()

        let window = try #require(document.windowControllers.first?.window)
        window.makeKeyAndOrderFront(nil)
        #expect(document.model.pdfPage?.count == 5)

        guard let out = ProcessInfo.processInfo.environment["ITSPAINT_PDF_CAPTURE_OUT"] else {
            document.close()
            return
        }

        var patience = 100
        while !NSApp.isActive && patience > 0 {
            NSApp.activate(ignoringOtherApps: true)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            patience -= 1
        }
        for _ in 0..<20 {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }

        let themeFrame = try #require(window.contentView?.superview)
        let rep = try #require(themeFrame.bitmapImageRepForCachingDisplay(in: themeFrame.bounds))
        themeFrame.cacheDisplay(in: themeFrame.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: out))
        document.close()
    }
}
