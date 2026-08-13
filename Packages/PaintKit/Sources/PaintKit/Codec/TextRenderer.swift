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
        /// Bold and italic are applied as **symbolic traits**, so a face that
        /// ships a real bold or italic cut is used rather than the synthesised
        /// slant CoreText would otherwise fake. Where a face has no such cut,
        /// `CTFontCreateCopyWithSymbolicTraits` returns nil and the request is
        /// dropped — a missing italic is better than a sheared upright.
        public var isBold: Bool
        public var isItalic: Bool
        public var isUnderlined: Bool

        /// A contrasting rim drawn *outside* the glyphs, or `nil` for none.
        ///
        /// **This is a legibility fix before it is a style.** Annotation text
        /// goes on top of a screenshot, and a screenshot is not a colour — it is
        /// a light sidebar next to a dark editor next to a photograph. Any single
        /// text colour is unreadable somewhere in that frame, and the usual
        /// answer, "pick a colour that works", cannot be picked once for an
        /// image the app has never seen.
        ///
        /// A rim in the opposite tone makes one colour work everywhere, which is
        /// why every tool that annotates screenshots ends up with one and why
        /// ex-Skitch users name it specifically as the thing they lost — "the
        /// default annotation font with the white border".
        public var haloColour: PaintColour?

        /// Rim thickness as a fraction of the point size, so it holds its
        /// proportion at 12pt and at 96pt instead of vanishing or swallowing the
        /// letterforms.
        public var haloWidth: Double

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
            alignment: Alignment = .left,
            isBold: Bool = false,
            isItalic: Bool = false,
            isUnderlined: Bool = false,
            // On by default. Text over a screenshot without a rim is the defect,
            // not the plain version — and a default nobody discovers is the same
            // as not having built it.
            haloColour: PaintColour? = .white,
            haloWidth: Double = 0.08
        ) {
            self.fontName = fontName
            self.pointSize = max(6, pointSize)
            self.colour = colour
            self.alignment = alignment
            self.isBold = isBold
            self.isItalic = isItalic
            self.isUnderlined = isUnderlined
            self.haloColour = haloColour
            self.haloWidth = max(0, haloWidth)
        }

        /// The font these settings resolve to, traits and all.
        ///
        /// Shared with the app so the live editor and the rasteriser cannot
        /// disagree about what you are about to get — the whole point of
        /// editing in place is that the preview *is* the result.
        public func makeFont() -> CTFont {
            let base = CTFontCreateWithName(fontName as CFString, pointSize, nil)
            var traits: CTFontSymbolicTraits = []
            if isBold { traits.insert(.traitBold) }
            if isItalic { traits.insert(.traitItalic) }
            guard !traits.isEmpty else { return base }
            return CTFontCreateCopyWithSymbolicTraits(base, pointSize, nil, traits, traits) ?? base
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

        let path = CGPath(rect: CGRect(x: 0, y: 0, width: rect.width, height: rect.height), transform: nil)

        func frame(isHaloPass: Bool) -> CTFrame {
            let attributed = attributedString(string, style: style, isHaloPass: isHaloPass)
            return CTFramesetterCreateFrame(
                CTFramesetterCreateWithAttributedString(attributed), CFRangeMake(0, 0), path, nil
            )
        }

        // **Two passes, rim then body.** The rim is stroke-only and therefore
        // hollow; drawing the filled text over it leaves the stroke showing on
        // the outside only, which is the whole point — a rim that ate the letter
        // it was meant to make legible would be worse than no rim.
        let wantsHalo = style.haloColour != nil && style.haloWidth > 0
        let passes = wantsHalo ? [frame(isHaloPass: true), frame(isHaloPass: false)]
                               : [frame(isHaloPass: false)]

        bitmap.drawWithCoreGraphics { context in
            // A bitmap `CGContext` does not turn these on for you, and without them
            // every glyph origin is rounded to a whole pixel. That is why committed
            // text read as coarse next to the live editor: AppKit positions glyphs on
            // fractions of a pixel and this context was quantising them, so stem
            // spacing came out uneven and small sizes looked chunky.
            //
            // The canvas is still one pixel per pixel, so a commit at 100% zoom on a
            // Retina display will always carry less detail than an editor drawn at the
            // screen's own scale. This closes the part of the gap that was ours.
            context.setShouldAntialias(true)
            context.setAllowsAntialiasing(true)
            context.setShouldSmoothFonts(false)   // greyscale AA; subpixel RGB would
                                                  // bake the display's stripe order
                                                  // into an image that gets shared
            context.setAllowsFontSubpixelPositioning(true)
            context.setShouldSubpixelPositionFonts(true)
            context.setAllowsFontSubpixelQuantization(false)
            context.setShouldSubpixelQuantizeFonts(false)
            for pass in passes {
                context.saveGState()
                // The surrounding context is flipped so canvas coordinates work;
                // CoreText draws glyphs in its own y-up space, so flip back inside
                // the text box or every line renders mirrored.
                context.translateBy(x: CGFloat(rect.minX), y: CGFloat(rect.minY + rect.height))
                context.scaleBy(x: 1, y: -1)
                context.textMatrix = .identity
                CTFrameDraw(pass, context)
                context.restoreGState()
            }
        }
        return rect.intersection(bitmap.bounds)
    }

    /// The size `string` needs at this style, for auto-growing the text box as
    /// the user types.
    /// One line of this style, in pixels, from the font rather than from a guess.
    ///
    /// This used to be four different guesses at the same quantity: `pointSize * 1.3`
    /// in `measure`, `* 1.35` where the box grew for a new line, `* 1.4` where a
    /// clicked box got its minimum height, and AppKit's own metrics inside the live
    /// editor. So the box the caret sat in and the box the text landed in were sized
    /// by two numbers that had never agreed, and a new line moved them further apart.
    ///
    /// Measured by laying out one line through the same framesetter that draws them,
    /// because every other way of computing it is a different answer.
    ///
    /// The first repair here replaced the multipliers with the font's own metrics,
    /// `CTFontGetAscent + Descent + Leading`, which sounds authoritative and is not
    /// the number CoreText uses to stack lines. For Helvetica those three sum to
    /// exactly the point size while the framesetter lays a line out 25% taller, so a
    /// box sized from the font metrics was a quarter of a line short at every size.
    /// Swapping one guess for a more official-looking guess is not measuring.
    public static func lineHeight(for style: Style) -> Int {
        // A wide-but-sane constraint. `Int.max / 2` reaches CoreText as ~4.6e18 and,
        // while finite, is the kind of number that turns into an infinity the first
        // time anything multiplies it. One line of one character never wraps at 100k.
        max(1, measure("H", style: style, maxWidth: 100_000).height)
    }

    public static func measure(_ string: String, style: Style, maxWidth: Int) -> (width: Int, height: Int) {
        guard !string.isEmpty else { return (0, lineHeight(for: style)) }
        let attributed = attributedString(string, style: style)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let constraint = CGSize(width: Double(maxWidth), height: .greatestFiniteMagnitude)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRangeMake(0, 0), nil, constraint, nil
        )
        return (Int(size.width.rounded(.up)), Int(size.height.rounded(.up)))
    }

    private static func attributedString(
        _ string: String, style: Style, isHaloPass: Bool = false
    ) -> CFAttributedString {
        let font = style.makeFont()

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

        var attributes: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: font,
            kCTForegroundColorAttributeName as NSAttributedString.Key: style.colour.cgColor,
            kCTParagraphStyleAttributeName as NSAttributedString.Key: paragraph,
        ]
        if style.isUnderlined {
            attributes[kCTUnderlineStyleAttributeName as NSAttributedString.Key] =
                CTUnderlineStyle.single.rawValue
        }
        // The rim is its own pass (see `draw`). CoreText's negative stroke width
        // looks like the shortcut for this and is not: measured on Helvetica, a
        // negative width centres the stroke on the glyph outline and eats inward,
        // so at 8% of the point size the *entire* body of "Il", "W" and "Step 1"
        // was consumed at both 18pt and 40pt — 290 dark pixels became 0. Half of
        // the stroke lands inside the letter, and thin stems are thinner than
        // half a rim.
        if isHaloPass, let halo = style.haloColour {
            attributes[kCTForegroundColorAttributeName as NSAttributedString.Key] = halo.cgColor
            attributes[kCTStrokeColorAttributeName as NSAttributedString.Key] = halo.cgColor
            // Positive: stroke only. The body arrives with the second pass.
            attributes[kCTStrokeWidthAttributeName as NSAttributedString.Key] =
                style.haloWidth * 100
        }
        return NSAttributedString(string: string, attributes: attributes) as CFAttributedString
    }
}
