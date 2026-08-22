import CoreGraphics
import Foundation

/// PDF, which this app treats as paper rather than as one more image format.
///
/// ImageIO can write a PDF and cannot read one. That asymmetry is what made
/// "open the contract, sign it, save it" impossible: the open failed outright
/// with *isn't an image ItsPaint can read*, and the write wrapped the canvas in
/// a page whose size was the pixel count in points — a letter page rasterised
/// for editing came back seventeen inches wide. Core Graphics' own PDF document
/// and PDF context do both jobs properly, so the format lives here instead.
///
/// **Every page the reader did not touch is copied through as itself.** A
/// signature on page four of a lease must not cost the other pages their text,
/// and must not cost them their existence either.
public enum PDFCodec {

    /// What a document opened from a PDF has to remember in order to write
    /// itself back as one.
    ///
    /// `data` is the whole file, and it is the *working* copy rather than the
    /// one on disk: turning to another page folds the edited canvas back into it
    /// first, so page four's signature survives a trip to page five.
    public struct Source: Sendable, Equatable {
        public let data: Data
        /// Zero-based, because every other index in this codebase is.
        public let pageIndex: Int
        public let pageCount: Int
        /// The edited page's size in points, in the orientation it is displayed
        /// in — a page carrying `/Rotate 90` is stored here already landscape,
        /// so writing never has to think about rotation again.
        public let pageSize: CGSize
        /// Pixels per point the page was rasterised at. Writing divides by it,
        /// which is what keeps a signed page the size it was printed at.
        public let renderScale: Double

        public var hasMorePages: Bool { pageCount > 1 }

        /// The same page, about to be written from a canvas that has been
        /// resampled by `factor`.
        ///
        /// Exporting a signed page at 200% should produce a sharper page, not a
        /// page twice the size — so the extra pixels are recorded as extra
        /// resolution rather than as extra paper.
        public func resampled(by factor: Double) -> Source {
            guard factor > 0, factor != 1 else { return self }
            return Source(
                data: data,
                pageIndex: pageIndex,
                pageCount: pageCount,
                pageSize: pageSize,
                renderScale: renderScale * factor
            )
        }
    }

    public enum Failure: LocalizedError, Equatable {
        case unreadable(String)
        case locked(String)
        case empty(String)
        case pageTooLarge(String, width: Double, height: Double)
        case renderFailed(String)
        case encodeFailed

        public var errorDescription: String? {
            switch self {
            case .unreadable(let name):
                "Couldn't open \(name)."
            case .locked(let name):
                "\(name) is password-protected."
            case .empty(let name):
                "\(name) has no pages."
            case .pageTooLarge(let name, let width, let height):
                "A page of \(name) is \(Int(width)) × \(Int(height)) points, which is too large to open."
            case .renderFailed(let name):
                "Couldn't draw the pages of \(name)."
            case .encodeFailed:
                "Couldn't write the image as PDF."
            }
        }

        public var recoverySuggestion: String? {
            switch self {
            case .unreadable:
                "It may be damaged, or it may not be a PDF."
            case .locked:
                "Open it in Preview, enter the password, and save a copy without one."
            case .empty:
                "Open it in Preview to check that it still has pages."
            case .pageTooLarge:
                "Scale the page down in Preview first, or export it as PNG and open that."
            case .renderFailed, .encodeFailed:
                "Try exporting the page as PNG instead."
            }
        }
    }

    /// 144 dpi. Twice the PDF's own unit, which is the point where body text
    /// stays legible on screen and a signature laid over it does not look
    /// pasted, while a letter page is still under two megapixels.
    public static let preferredScale: Double = 2

    // MARK: - Reading

    public static func open(
        contentsOf url: URL, page pageIndex: Int = 0
    ) throws -> (bitmap: Bitmap, source: Source) {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            throw Failure.unreadable(url.lastPathComponent)
        }
        return try open(data: Data(data), page: pageIndex, named: url.lastPathComponent)
    }

    /// Rasterise one page of `data` and hand back everything needed to put it
    /// back where it came from.
    ///
    /// The page is drawn onto white rather than onto transparency. A PDF page
    /// has no background of its own, and a signed contract whose paper is
    /// transparent looks like a bug in every viewer that puts something dark
    /// behind it.
    public static func open(
        data: Data, page pageIndex: Int = 0, named name: String
    ) throws -> (bitmap: Bitmap, source: Source) {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider)
        else { throw Failure.unreadable(name) }

        // A locked document reports pages it will not draw, so the useful answer
        // is the password rather than "no pages" — bank statements and signed
        // contracts arrive encrypted often enough to be worth naming.
        guard !document.isEncrypted || document.isUnlocked else {
            throw Failure.locked(name)
        }

        let count = document.numberOfPages
        guard count > 0 else { throw Failure.empty(name) }
        // Clamped rather than refused: a stale page index in a reopened
        // document should land you on the last page, not on an error.
        let index = min(max(pageIndex, 0), count - 1)
        guard let page = document.page(at: index + 1) else { throw Failure.empty(name) }

        let size = displaySize(of: page)
        guard size.width >= 1, size.height >= 1 else { throw Failure.empty(name) }
        guard let scale = renderScale(for: size) else {
            throw Failure.pageTooLarge(name, width: size.width, height: size.height)
        }

        let width = max(1, Int((size.width * scale).rounded()))
        let height = max(1, Int((size.height * scale).rounded()))
        guard let rendered = render(page, at: scale, size: CGSize(width: width, height: height)),
              let bitmap = Bitmap(cgImage: rendered)
        else { throw Failure.renderFailed(name) }

        return (
            bitmap,
            Source(
                data: data,
                pageIndex: index,
                pageCount: count,
                pageSize: size,
                renderScale: scale
            )
        )
    }

    /// How many pages `url` has, without rasterising any of them. The open panel
    /// asks so it can offer a page to start on.
    public static func pageCount(contentsOf url: URL) -> Int {
        guard let document = CGPDFDocument(url as CFURL) else { return 0 }
        return document.numberOfPages
    }

    /// The page's box after its own `/Rotate` entry is applied, which is the
    /// shape the reader sees.
    private static func displaySize(of page: CGPDFPage) -> CGSize {
        let box = page.getBoxRect(.mediaBox)
        let quarterTurns = ((page.rotationAngle % 360) + 360) % 360
        return quarterTurns == 90 || quarterTurns == 270
            ? CGSize(width: box.height, height: box.width)
            : box.size
    }

    /// The largest scale at or below `preferredScale` that the canvas budget
    /// allows, halving until it fits. `nil` when even 1:1 is too big — an
    /// architectural drawing rather than a contract.
    private static func renderScale(for size: CGSize) -> Double? {
        var scale = preferredScale
        while scale >= 0.125 {
            let width = Int((size.width * scale).rounded())
            let height = Int((size.height * scale).rounded())
            if Bitmap.isSizeSupported(width: max(1, width), height: max(1, height)) {
                return scale
            }
            scale /= 2
        }
        return nil
    }

    /// Draw a page into its own bitmap context.
    ///
    /// Not `Bitmap.drawWithCoreGraphics`: that flips the context so path and
    /// text drawing can use canvas coordinates, and a PDF page drawn through
    /// that flip lands upside down. Rendering into a context here and importing
    /// the result through `Bitmap(cgImage:)` is the same route every other
    /// imported image takes.
    private static func render(_ page: CGPDFPage, at scale: Double, size: CGSize) -> CGImage? {
        let width = Int(size.width), height = Int(size.height)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: Bitmap.colourSpace,
            bitmapInfo: Bitmap.bitmapInfo.rawValue
        ) else { return nil }

        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        // `getDrawingTransform` is what applies the page's own rotation and
        // crop offset. Handing it the display-sized box means a rotated page
        // arrives upright and a page whose media box does not start at the
        // origin arrives in frame.
        context.concatenate(
            page.getDrawingTransform(
                .mediaBox,
                rect: CGRect(origin: .zero, size: displaySize(of: page)),
                rotate: 0,
                preserveAspectRatio: true
            )
        )
        context.drawPDFPage(page)
        return context.makeImage()
    }

    // MARK: - Writing

    /// The canvas as a PDF: one page when it came from nowhere, and the original
    /// document with one page replaced when it came from a PDF.
    public static func encode(_ bitmap: Bitmap, replacing source: Source?) throws -> Data {
        guard let image = bitmap.makeCGImage() else { throw Failure.encodeFailed }

        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output) else { throw Failure.encodeFailed }

        let edited = editedPageSize(for: bitmap, source: source)
        var mediaBox = CGRect(origin: .zero, size: edited)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw Failure.encodeFailed
        }

        let original = source.flatMap { source -> CGPDFDocument? in
            guard let provider = CGDataProvider(data: source.data as CFData) else { return nil }
            return CGPDFDocument(provider)
        }

        if let original, let source, original.numberOfPages > 0 {
            for number in 1...original.numberOfPages {
                guard let page = original.page(at: number) else { continue }
                let isEdited = number == source.pageIndex + 1
                let size = isEdited ? edited : displaySize(of: page)
                beginPage(context, size: size)
                if isEdited {
                    context.draw(image, in: CGRect(origin: .zero, size: size))
                } else {
                    // The untouched pages stay vector: drawing a PDF page into a
                    // PDF context copies its content streams rather than
                    // rasterising them, so page five is still selectable text
                    // after page four has been signed.
                    context.concatenate(
                        page.getDrawingTransform(
                            .mediaBox,
                            rect: CGRect(origin: .zero, size: size),
                            rotate: 0,
                            preserveAspectRatio: true
                        )
                    )
                    context.drawPDFPage(page)
                }
                context.endPDFPage()
            }
        } else {
            beginPage(context, size: edited)
            context.draw(image, in: CGRect(origin: .zero, size: edited))
            context.endPDFPage()
        }

        context.closePDF()
        guard output.length > 0 else { throw Failure.encodeFailed }
        return output as Data
    }

    /// Write `bitmap` as a PDF at `url`, staged so a failure part-way cannot
    /// leave a half-written document behind.
    public static func write(_ bitmap: Bitmap, to url: URL, replacing source: Source?) throws {
        let data = try encode(bitmap, replacing: source)
        try FileStaging.replaceItem(at: url) { staged in
            try data.write(to: staged)
        }
    }

    /// The size of the page being written.
    ///
    /// Divided by the scale it was rasterised at, so a page opened at 144 dpi
    /// and signed goes back out at its printed size. A canvas that never came
    /// from a PDF keeps the one mapping every other tool uses for this — a pixel
    /// is a point — because inventing a DPI for someone's screenshot would make
    /// the page a surprise.
    private static func editedPageSize(for bitmap: Bitmap, source: Source?) -> CGSize {
        guard let source, source.renderScale > 0 else {
            return CGSize(width: bitmap.width, height: bitmap.height)
        }
        // Cropping or resizing the canvas changes the page with it rather than
        // stretching the artwork back over the old box.
        return CGSize(
            width: Double(bitmap.width) / source.renderScale,
            height: Double(bitmap.height) / source.renderScale
        )
    }

    private static func beginPage(_ context: CGContext, size: CGSize) {
        var box = CGRect(origin: .zero, size: size)
        let info = [
            kCGPDFContextMediaBox as String: NSData(
                bytes: &box, length: MemoryLayout<CGRect>.size
            )
        ]
        context.beginPDFPage(info as CFDictionary)
    }
}
