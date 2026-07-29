import CoreGraphics
import CoreText
import Foundation

/// Lays out and draws text into a bitmap.
///
/// CoreText rather than AppKit so `PaintKit` stays UI-free and testable without
/// a running app — the same reason the rest of the engine avoids `NSImage` and
/// friends.
///
/// Text is **rasterised on commit**, not kept as an editable object. That is the
/// honest model for a paint app: once you click away, the letters are pixels
/// like everything else, and pretending otherwise would mean a document format
/// carrying live text that the PNG export silently flattens anyway.
public enum TextRenderer {

    public struct Style: Equatable, Sendable {
        public var fontName: String
        public var pointSize: Double
        public var colour: PaintColour
        public var alignment: Alignment

        public enum Alignment: String, CaseIterable, Codable, Sendable, Identifiable {
            case left, centre, right
            public var id: String { rawValue }
            public var displayName: String {
                switch self {
                case .left: "Left"
                case .centre: "Centre"
                case .right: "Right"
                }
            }

            var ctAlignment: CTTextAlignment {
                switch self {
                case .left: .left
                case .centre: .center
                case .right: .right
                }
            }
        }

        public init(
            fontName: String = "Helvetica",
            pointSize: Double = 36,
            colour: PaintColour = .black,
            alignment: Alignment = .left
        ) {
            self.fontName = fontName
            self.pointSize = max(6, pointSize)
            self.colour = colour
            self.alignment = alignment
        }

        /// Faces that ship with every macOS install, so a document opened on
        /// another Mac renders the same text.
        public static let availableFonts = [
            "Helvetica", "Helvetica Neue", "Avenir Next", "Georgia",
            "Menlo", "Times New Roman", "Impact",
        ]
    }

    /// Draw `string` inside `rect`, returning the rect actually touched.
    @discardableResult
    public static func draw(
        _ string: String,
        in rect: PixelRect,
        style: Style,
        into bitmap: inout Bitmap
    ) -> PixelRect {
        guard !string.isEmpty, !rect.isEmpty else { return .empty }

        let attributed = attributedString(string, style: style)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: rect.width, height: rect.height), transform: nil)
        let frame = CTFramesetterCreateFrame(
            framesetter, CFRangeMake(0, 0), path, nil
        )

        bitmap.drawWithCoreGraphics { context in
            context.saveGState()
            // The surrounding context is flipped so canvas coordinates work;
            // CoreText draws glyphs in its own y-up space, so flip back inside
            // the text box or every line renders mirrored.
            context.translateBy(x: CGFloat(rect.minX), y: CGFloat(rect.minY + rect.height))
            context.scaleBy(x: 1, y: -1)
            context.textMatrix = .identity
            CTFrameDraw(frame, context)
            context.restoreGState()
        }
        return rect.intersection(bitmap.bounds)
    }

    /// The size `string` needs at this style, for auto-growing the text box as
    /// the user types.
    public static func measure(_ string: String, style: Style, maxWidth: Int) -> (width: Int, height: Int) {
        guard !string.isEmpty else { return (0, Int(style.pointSize * 1.3)) }
        let attributed = attributedString(string, style: style)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let constraint = CGSize(width: Double(maxWidth), height: .greatestFiniteMagnitude)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRangeMake(0, 0), nil, constraint, nil
        )
        return (Int(size.width.rounded(.up)), Int(size.height.rounded(.up)))
    }

    private static func attributedString(_ string: String, style: Style) -> CFAttributedString {
        let font = CTFontCreateWithName(style.fontName as CFString, style.pointSize, nil)

        // The setting borrows the pointer, so it has to stay valid for the
        // whole `CTParagraphStyleCreate` call — `&alignment` inline would hand
        // it a temporary that is already gone.
        var alignment = style.alignment.ctAlignment
        let paragraph = withUnsafePointer(to: &alignment) { pointer in
            let settings = [
                CTParagraphStyleSetting(
                    spec: .alignment,
                    valueSize: MemoryLayout<CTTextAlignment>.size,
                    value: pointer
                )
            ]
            return CTParagraphStyleCreate(settings, settings.count)
        }

        let attributes: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: font,
            kCTForegroundColorAttributeName as NSAttributedString.Key: style.colour.cgColor,
            kCTParagraphStyleAttributeName as NSAttributedString.Key: paragraph,
        ]
        return NSAttributedString(string: string, attributes: attributes) as CFAttributedString
    }
}
