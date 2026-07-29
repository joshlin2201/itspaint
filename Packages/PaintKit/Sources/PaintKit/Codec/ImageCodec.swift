import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Import and export via ImageIO.
///
/// ImageIO rather than a hand-rolled encoder for every format: it is the same
/// code path Preview and Finder use, so a file that opens here opens
/// everywhere, and format support tracks the OS instead of our release
/// schedule.
public enum ImageCodec {

    public enum Format: String, CaseIterable, Sendable, Identifiable {
        case png
        case jpeg
        case tiff
        case bmp
        case gif
        case heic
        /// Modern, small, and what a screenshot posted today usually wants.
        case avif
        /// Vector container around the bitmap — what a document workflow asks
        /// for when it says "send me a file I can print".
        case pdf
        /// App icons. Capped at 256px by the format itself.
        case ico

        public var id: String { rawValue }

        public var utType: UTType {
            switch self {
            case .png: .png
            case .jpeg: .jpeg
            case .tiff: .tiff
            case .bmp: .bmp
            case .gif: .gif
            case .heic: UTType("public.heic") ?? .heic
            case .avif: UTType("public.avif") ?? .heic
            case .pdf: .pdf
            case .ico: UTType("com.microsoft.ico") ?? .ico
            }
        }

        public var displayName: String {
            switch self {
            case .png: "PNG"
            case .jpeg: "JPEG"
            case .tiff: "TIFF"
            case .bmp: "BMP"
            case .gif: "GIF"
            case .heic: "HEIC"
            case .avif: "AVIF"
            case .pdf: "PDF"
            case .ico: "ICO"
            }
        }

        public var fileExtension: String {
            switch self {
            case .png: "png"
            case .jpeg: "jpg"
            case .tiff: "tiff"
            case .bmp: "bmp"
            case .gif: "gif"
            case .heic: "heic"
            case .avif: "avif"
            case .pdf: "pdf"
            case .ico: "ico"
            }
        }

        /// Formats with no alpha channel. Exporting to one flattens the image
        /// onto an opaque matte first — silently dropping transparency to black
        /// is a classic way to ruin someone's export.
        public var supportsAlpha: Bool {
            switch self {
            case .png, .tiff, .gif, .heic, .avif, .ico, .pdf: true
            case .jpeg, .bmp: false
            }
        }

        public var supportsQuality: Bool {
            switch self {
            case .jpeg, .heic, .avif: true
            default: false
            }
        }

        /// Sizes an ICO is actually allowed to be. ImageIO refuses anything
        /// else outright — 100×60 and 8×8 both fail — so the export fits the
        /// artwork to one of these rather than handing back an error.
        public static let iconSizes = [16, 32, 48, 64, 128, 256]

        /// Whether this format only accepts a fixed set of square sizes.
        public var requiresIconSize: Bool { self == .ico }

        /// Whether this machine's ImageIO can actually write it. Checked
        /// against the installed encoders rather than assumed, so the export
        /// list never offers a format that will fail at the last step.
        public var isWritable: Bool { Self.writableIdentifiers.contains(utType.identifier) }

        private static let writableIdentifiers: Set<String> = Set(
            (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
        )

        /// Formats offered in the export panel, in the order people reach for
        /// them.
        public static var exportable: [Format] { allCases.filter(\.isWritable) }

        public static func inferred(from url: URL) -> Format? {
            let ext = url.pathExtension.lowercased()
            return allCases.first { $0.fileExtension == ext }
                ?? (ext == "jpeg" ? .jpeg : nil)
                ?? (ext == "tif" ? .tiff : nil)
        }
    }

    public enum CodecError: LocalizedError {
        case unreadableSource(URL)
        case unsupportedFormat(String)
        case decodeFailed(URL)
        case imageTooLarge(width: Int, height: Int)
        case encodeFailed(Format)

        public var errorDescription: String? {
            switch self {
            case .unreadableSource(let url):
                "Couldn't read \(url.lastPathComponent)."
            case .unsupportedFormat(let ext):
                "ItsPaint can't open .\(ext) files."
            case .decodeFailed(let url):
                "\(url.lastPathComponent) isn't an image ItsPaint can read."
            case .imageTooLarge(let width, let height):
                "This \(width) × \(height) image is too large to open safely."
            case .encodeFailed(let format):
                "Couldn't write the image as \(format.displayName)."
            }
        }

        /// Recovery text. Every failure the user can act on says what to do —
        /// an error with no next step is just a dead end with an OK button.
        public var recoverySuggestion: String? {
            switch self {
            case .unreadableSource:
                "Check that the file still exists and you have permission to open it."
            case .unsupportedFormat:
                "Try converting it to PNG or JPEG first."
            case .decodeFailed:
                "The file may be damaged or may not be an image."
            case .imageTooLarge:
                "Choose an image no larger than \(Bitmap.maximumDimension) pixels on either side and about 33.5 megapixels."
            case .encodeFailed:
                "Try exporting as PNG."
            }
        }
    }

    // MARK: - Decoding

    public static func decode(contentsOf url: URL) throws -> Bitmap {
        guard let source = CGImageSourceCreateWithURL(
            url as CFURL,
            decodingOptions
        ) else {
            throw CodecError.unreadableSource(url)
        }
        return try decode(source: source, sourceURL: url)
    }

    /// Compatibility entry point for pasteboard callers that do not present
    /// errors. UI surfaces should prefer the throwing overload below so an
    /// oversized image produces an actionable message rather than a silent
    /// no-op.
    public static func decode(data: Data) -> Bitmap? {
        try? decode(
            data: data,
            sourceURL: URL(fileURLWithPath: "Imported image")
        )
    }

    /// Decode in-memory image data while retaining a source label for errors.
    ///
    /// `sourceURL` may be a real file URL or a synthetic URL such as
    /// `Pasted image`; only its last path component is shown to the user.
    public static func decode(data: Data, sourceURL: URL) throws -> Bitmap {
        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            decodingOptions
        ) else {
            throw CodecError.decodeFailed(sourceURL)
        }
        return try decode(source: source, sourceURL: sourceURL)
    }

    /// ImageIO can discover encoded dimensions without decoding the pixel
    /// payload. Enforce the raster budget there, before a hostile header can
    /// cause `CGImageSourceCreateImageAtIndex` to reserve its advertised size.
    private static func decode(
        source: CGImageSource,
        sourceURL: URL
    ) throws -> Bitmap {
        guard CGImageSourceGetCount(source) > 0,
              let declared = encodedDimensions(of: source)
        else {
            throw CodecError.decodeFailed(sourceURL)
        }
        guard Bitmap.isSizeSupported(width: declared.width, height: declared.height) else {
            throw CodecError.imageTooLarge(width: declared.width, height: declared.height)
        }

        guard let image = CGImageSourceCreateImageAtIndex(
            source,
            0,
            decodingOptions
        ) else {
            throw CodecError.decodeFailed(sourceURL)
        }

        // Do not trust metadata alone. Recheck the actual decoder result and
        // require it to agree with the properties inspected above.
        guard Bitmap.isSizeSupported(width: image.width, height: image.height) else {
            throw CodecError.imageTooLarge(width: image.width, height: image.height)
        }
        guard image.width == declared.width, image.height == declared.height,
              let bitmap = Bitmap(cgImage: image)
        else {
            throw CodecError.decodeFailed(sourceURL)
        }
        return bitmap
    }

    private static var decodingOptions: CFDictionary {
        [kCGImageSourceShouldCache: false] as CFDictionary
    }

    /// Missing, fractional, or non-numeric dimensions are malformed input and
    /// deliberately fail closed.
    private static func encodedDimensions(
        of source: CGImageSource
    ) -> (width: Int, height: Int)? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(
            source,
            0,
            decodingOptions
        ) else { return nil }
        let dictionary = properties as NSDictionary
        guard let width = exactDimension(dictionary[kCGImagePropertyPixelWidth]),
              let height = exactDimension(dictionary[kCGImagePropertyPixelHeight])
        else { return nil }
        return (width, height)
    }

    private static func exactDimension(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        let raw = number.doubleValue
        guard raw.isFinite, raw > 0,
              raw.rounded(.towardZero) == raw,
              raw <= Double(Int.max)
        else { return nil }
        return Int(raw)
    }

    // MARK: - Encoding

    /// Encode to `format`. `quality` (0...1) applies to lossy formats only.
    /// `matte` is the colour transparent pixels are flattened onto for formats
    /// with no alpha channel.
    public static func encode(
        _ bitmap: Bitmap,
        as format: Format,
        quality: Double = 0.9,
        matte: PaintColour = .white
    ) throws -> Data {
        var source = bitmap
        if !format.supportsAlpha {
            source = flattened(bitmap, onto: matte)
        }
        if format.requiresIconSize {
            source = fittedToIconSize(source)
        }

        guard let image = source.makeCGImage() else {
            throw CodecError.encodeFailed(format)
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData,
            format.utType.identifier as CFString,
            1,
            nil
        ) else {
            throw CodecError.encodeFailed(format)
        }

        var properties: [CFString: Any] = [:]
        if format.supportsQuality {
            properties[kCGImageDestinationLossyCompressionQuality] = max(0, min(1, quality))
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw CodecError.encodeFailed(format)
        }
        return output as Data
    }

    public static func write(
        _ bitmap: Bitmap,
        to url: URL,
        as format: Format? = nil,
        quality: Double = 0.9,
        matte: PaintColour = .white
    ) throws {
        let resolved = format ?? Format.inferred(from: url) ?? .png
        let data = try encode(bitmap, as: resolved, quality: quality, matte: matte)
        try data.write(to: url, options: .atomic)
    }

    /// Scale the artwork into the nearest legal icon square, centred, with
    /// transparent margins.
    ///
    /// Fitting rather than stretching: an icon made by squashing a wide canvas
    /// into a square is not what anyone meant by "export as ICO".
    static func fittedToIconSize(_ bitmap: Bitmap) -> Bitmap {
        let longest = max(bitmap.width, bitmap.height)
        let side = Format.iconSizes.last(where: { $0 <= longest }) ?? Format.iconSizes[0]
        let scale = Double(side) / Double(longest)
        let target = (
            width: max(1, Int((Double(bitmap.width) * scale).rounded())),
            height: max(1, Int((Double(bitmap.height) * scale).rounded()))
        )
        guard let scaled = ImageTransform.scaled(bitmap, to: target, using: .smooth) else { return bitmap }

        var square = Bitmap(width: side, height: side, fill: .clear)
        square.composite(
            scaled,
            at: PixelPoint(x: (side - scaled.width) / 2, y: (side - scaled.height) / 2)
        )
        return square
    }

    /// Composite over an opaque matte, for formats that cannot carry alpha.
    public static func flattened(_ bitmap: Bitmap, onto colour: PaintColour) -> Bitmap {
        var flat = Bitmap(width: bitmap.width, height: bitmap.height, fill: colour.rgba8)
        flat.composite(bitmap, at: .zero)
        return flat
    }

    /// UTTypes accepted by the open panel.
    public static var readableContentTypes: [UTType] {
        Format.allCases.map(\.utType) + [.image]
    }
}
