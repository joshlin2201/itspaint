import CoreGraphics
import CoreText
import Foundation

/// Lays out and draws text into a bitmap.
///
/// CoreText rather than AppKit so `PaintKit` stays UI-free and testable without
/// a running app — the same reason the rest of the engine avoids `NSImage` and
/// friends.
///
/// Retained styled text uses this renderer for canvas compositing and flattened
/// image exports. Native documents keep the text objects separately.
public enum TextRenderer {

    public struct Style: Codable, Equatable, Sendable {
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

        public var isValid: Bool {
            pointSize.isFinite && pointSize >= 6 && pointSize <= 4_096
                && colour.red.isFinite && colour.green.isFinite
                && colour.blue.isFinite && colour.alpha.isFinite
                && (0...1).contains(colour.red) && (0...1).contains(colour.green)
                && (0...1).contains(colour.blue) && (0...1).contains(colour.alpha)
                && !fontName.isEmpty && fontName.utf8.count <= 256
                && haloWidth.isFinite && (0...1).contains(haloWidth)
                && (haloColour.map {
                    [$0.red, $0.green, $0.blue, $0.alpha].allSatisfy { (0...1).contains($0) }
                } ?? true)
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

    /// One uniformly styled span in a retained text object. Runs are ordered
    /// and adjacent runs are intentionally not merged: selection formatting is
    /// an editing concern, not a serialisation optimisation.
    public struct TextRun: Codable, Equatable, Sendable {
        public var text: String
        public var style: Style

        public init(text: String, style: Style) {
            self.text = text
            self.style = style
        }
    }

    /// Text retained separately from the paint bitmap. Keeping its stable ID
    /// lets a live native editor update one box without touching its siblings.
    public struct TextObject: Codable, Equatable, Sendable, Identifiable {
        public var id: UUID
        public var frame: PixelRect
        public var runs: [TextRun]

        public init(id: UUID = UUID(), frame: PixelRect, runs: [TextRun]) {
            self.id = id
            self.frame = frame
            self.runs = runs
        }

        /// Structural validation for untrusted document data. Canvas-relative
        /// bounds belong to the document reader, which knows the canvas size.
        public var isValid: Bool {
            frame.width > 0 && frame.height > 0 && frame.x >= 0 && frame.y >= 0
                && frame.width <= Bitmap.maximumDimension && frame.height <= Bitmap.maximumDimension
                && frame.x <= Bitmap.maximumDimension - frame.width
                && frame.y <= Bitmap.maximumDimension - frame.height
                && !runs.isEmpty && runs.count <= 64 * 1024
                && runs.reduce(0, { $0 + $1.text.utf8.count }) <= 64 * 1024
                && runs.allSatisfy {
                    !$0.text.isEmpty && $0.text.utf8.count <= 64 * 1024 && $0.style.isValid
                }
        }
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
        return draw([TextRun(text: string, style: style)], in: rect, into: &bitmap)
    }

    /// Draw styled runs without collapsing their font, colour, or traits.
    @discardableResult
    public static func draw(
        _ runs: [TextRun], in rect: PixelRect, into bitmap: inout Bitmap
    ) -> PixelRect {
        guard !runs.isEmpty, !rect.isEmpty else { return .empty }

        let layout = layout(runs, width: rect.width)
        guard !layout.lines.isEmpty else { return .empty }

        // **Up to three passes over one layout: rim, body, then cut-out.** Each run
        // takes part only in the passes its own style asks for, so one box can
        // mix a rimmed word, a plain one and a transparent one.
        //
        // The rim is stroke-only and therefore hollow; drawing the filled text
        // over it leaves the stroke showing on the outside only, which is the
        // whole point — a rim that ate the letter it was meant to make legible
        // would be worse than no rim.
        //
        // **Text set in a transparent colour cuts the letters out of the picture.**
        // Core Graphics cannot express that as a colour: source-over with a zero
        // alpha source is a no-op, so typing in a clear colour changed nothing and
        // said nothing — the same silence every other tool used to keep. The
        // letterforms are drawn opaque and the blend mode does the erasing, which
        // is what `destination-out` is: it takes the *source's* alpha away from
        // the destination and ignores the source's colour entirely. The halo goes
        // with it. A rim around a hole is a rim around nothing.
        let passes = Pass.allCases.filter { pass in runs.contains { pass.includes($0.style) } }

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
                // Colour and stroke do not move glyphs, so each pass re-sets the
                // body's own line ranges and lands on the body's own positions.
                let typesetter = pass == .body
                    ? nil : CTTypesetterCreateWithAttributedString(attributedString(runs, pass: pass))
                context.saveGState()
                if pass == .erase { context.setBlendMode(.destinationOut) }
                // The surrounding context is flipped so canvas coordinates work;
                // CoreText draws glyphs in its own y-up space, so flip back inside
                // the text box or every line renders mirrored.
                context.translateBy(x: CGFloat(rect.minX), y: CGFloat(rect.minY + rect.height))
                context.scaleBy(x: 1, y: -1)
                // Kept inside the box, because the box is what a retained object
                // repaints and what its undo restores.
                context.clip(to: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
                context.textMatrix = .identity
                for line in layout.lines {
                    // NSTextView only lays a line into a fragment that can hold
                    // its full typographic bounds. Skipping an incomplete fragment
                    // avoids drawing the top sliver of the next line at the box
                    // edge when a caller has not grown the editor yet.
                    guard line.fragmentBottom <= CGFloat(rect.height) else { continue }
                    // Core Text uses y-up; our layout deliberately uses the same
                    // top-down baseline and line advance as NSTextView/TextKit.
                    context.textPosition = CGPoint(
                        x: xOffset(for: line, in: rect.width),
                        y: CGFloat(rect.height) - line.baseline
                    )
                    CTLineDraw(typesetter.map { CTTypesetterCreateLine($0, line.range) } ?? line.line, context)
                }
                context.restoreGState()
            }
        }
        return rect.intersection(bitmap.bounds)
    }

    /// One line of this style, in pixels, from the font rather than from a guess.
    ///
    /// This used to be four different guesses at the same quantity: `pointSize * 1.3`
    /// in `measure`, `* 1.35` where the box grew for a new line, `* 1.4` where a
    /// clicked box got its minimum height, and AppKit's own metrics inside the live
    /// editor. So the box the caret sat in and the box the text landed in were sized
    /// by two numbers that had never agreed, and a new line moved them further apart.
    ///
    /// Measured by laying out one line through the same layout that draws them,
    /// because every other way of computing it is a different answer. While the
    /// renderer drew through a framesetter, the font's own metrics came out a
    /// quarter of a line short of what it stacked; lines are now stacked the way
    /// NSTextView stacks them, so this and the editor agree by construction.
    public static func lineHeight(for style: Style) -> Int {
        // A wide-but-sane constraint. `Int.max / 2` reaches CoreText as ~4.6e18 and,
        // while finite, is the kind of number that turns into an infinity the first
        // time anything multiplies it. One line of one character never wraps at 100k.
        max(1, measure("H", style: style, maxWidth: 100_000).height)
    }

    /// The size `string` needs at this style, for auto-growing the text box as
    /// the user types.
    public static func measure(_ string: String, style: Style, maxWidth: Int) -> (width: Int, height: Int) {
        guard !string.isEmpty else { return (0, lineHeight(for: style)) }
        return measure([TextRun(text: string, style: style)], maxWidth: maxWidth)
    }

    /// The frame needed for styled runs. The caller owns the width; this only
    /// answers the resulting wrapped height and intrinsic line width.
    public static func measure(_ runs: [TextRun], maxWidth: Int) -> (width: Int, height: Int) {
        guard !runs.isEmpty, maxWidth > 0 else { return (0, 0) }
        let layout = layout(runs, width: maxWidth)
        let widest = layout.lines.map(\.width).max() ?? 0
        return (
            min(maxWidth, Int(widest.rounded(.up))),
            Int(layout.height.rounded(.up))
        )
    }

    private enum Pass: CaseIterable {
        case halo, body, erase

        func includes(_ style: Style) -> Bool {
            let erases = style.colour.alpha == 0
            return switch self {
            case .halo: !erases && style.haloColour != nil && style.haloWidth > 0
            case .body: !erases
            case .erase: erases
            }
        }
    }

    private struct LineLayout {
        let line: CTLine
        let range: CFRange
        let width: CGFloat
        let baseline: CGFloat
        let fragmentBottom: CGFloat
        let alignment: Style.Alignment
    }

    private struct Layout {
        let lines: [LineLayout]
        let height: CGFloat
    }

    /// `CTFrameDraw` inserts Core Text's paragraph leading (Helvetica 36: 43px)
    /// while NSTextView advances its default line fragments by the font's
    /// typographic height (36px). Building and drawing `CTLine`s directly
    /// gives the renderer and the native editor the same baseline: ceil(ascent)
    /// for line one, then ceil(ascent + descent + leading) per line.
    private static func layout(_ runs: [TextRun], width: Int) -> Layout {
        let attributed = attributedString(runs, pass: .body)
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        let length = CFAttributedStringGetLength(attributed)
        guard length > 0 else {
            return Layout(lines: [], height: 0)
        }

        var lines: [LineLayout] = []
        var start = 0
        var top: CGFloat = 0
        var runIndex = 0
        var runEnd = runs[0].text.utf16.count
        while start < length {
            let count = CTTypesetterSuggestLineBreak(typesetter, start, CGFloat(width))
            guard count > 0 else { break }
            let range = CFRange(location: start, length: count)
            let line = CTTypesetterCreateLine(typesetter, range)
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            let baseline = top + ceil(ascent)
            let fragmentBottom = top + max(1, ceil(ascent + descent + leading))
            while start >= runEnd, runIndex + 1 < runs.count {
                runIndex += 1
                runEnd += runs[runIndex].text.utf16.count
            }
            lines.append(LineLayout(
                line: line, range: range, width: lineWidth, baseline: baseline,
                fragmentBottom: fragmentBottom, alignment: runs[runIndex].style.alignment
            ))
            top = fragmentBottom
            start += count
        }
        return Layout(lines: lines, height: top)
    }

    private static func xOffset(for line: LineLayout, in width: Int) -> CGFloat {
        let flush: CGFloat = switch line.alignment {
        case .left: 0
        case .centre: 0.5
        case .right: 1
        }
        // This also handles trailing whitespace the way CTFrameDraw did;
        // subtracting typographic width by hand does not.
        return CTLineGetPenOffsetForFlush(line.line, flush, CGFloat(width))
    }

    private static func attributedString(_ runs: [TextRun], pass: Pass) -> CFAttributedString {
        let result = NSMutableAttributedString()
        for run in runs {
            result.append(NSAttributedString(
                string: run.text, attributes: attributes(for: run.style, pass: pass)
            ))
        }
        return result as CFAttributedString
    }

    private static func attributes(for style: Style, pass: Pass) -> [NSAttributedString.Key: Any] {
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
        // A run that sits a pass out still occupies its place in the line, in a
        // colour that draws nothing.
        guard pass.includes(style) else {
            attributes[kCTForegroundColorAttributeName as NSAttributedString.Key] =
                PaintColour.clear.cgColor
            return attributes
        }
        switch pass {
        case .body:
            break
        case .erase:
            attributes[kCTForegroundColorAttributeName as NSAttributedString.Key] =
                PaintColour(red: 0, green: 0, blue: 0, alpha: 1).cgColor
        case .halo:
            // The rim is its own pass (see `draw`). CoreText's negative stroke width
            // looks like the shortcut for this and is not: measured on Helvetica, a
            // negative width centres the stroke on the glyph outline and eats inward,
            // so at 8% of the point size the *entire* body of "Il", "W" and "Step 1"
            // was consumed at both 18pt and 40pt — 290 dark pixels became 0. Half of
            // the stroke lands inside the letter, and thin stems are thinner than
            // half a rim.
            let halo = (style.haloColour ?? .white).cgColor
            attributes[kCTForegroundColorAttributeName as NSAttributedString.Key] = halo
            attributes[kCTStrokeColorAttributeName as NSAttributedString.Key] = halo
            // Positive: stroke only. The body arrives with the second pass.
            attributes[kCTStrokeWidthAttributeName as NSAttributedString.Key] =
                style.haloWidth * 100
        }
        return attributes
    }
}

/// Convenience names for document and UI code. The renderer remains the
/// namespace for layout, while retained content reads naturally in models.
public typealias TextRun = TextRenderer.TextRun
public typealias TextObject = TextRenderer.TextObject
