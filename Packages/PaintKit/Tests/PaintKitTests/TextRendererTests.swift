import Testing
@testable import PaintKit

/// Text, and specifically the two things that were silently wrong about it.
///
/// **The box clips.** `CTFrameDraw` draws into a path, and anything that does
/// not fit inside it is not drawn — no error, no overflow, no partial glyph.
/// So a box sized for one line rendered exactly one line no matter how much
/// was typed, which is why Return appeared to work and the second line never
/// appeared. The fix is that the box grows; the guard is that a short box
/// genuinely does lose text, so the growth is load-bearing rather than
/// cosmetic.
@Suite("Text")
struct TextRendererTests {

    private func canvas() -> Bitmap { Bitmap(width: 400, height: 400, fill: .white) }

    private func inkedPixels(_ bitmap: Bitmap) -> Int {
        var count = 0
        let white = PaintColour.white.rgba8
        for y in 0..<bitmap.height {
            for x in 0..<bitmap.width
            where bitmap.pixel(at: PixelPoint(x: x, y: y)) != white {
                count += 1
            }
        }
        return count
    }

    @Test("A box too short for the text loses the lines that do not fit")
    func shortBoxClipsLaterLines() {
        let style = TextRenderer.Style(pointSize: 20, colour: .black)
        let oneLineTall = PixelRect(x: 10, y: 10, width: 300, height: 26)

        var single = canvas()
        TextRenderer.draw("First", in: oneLineTall, style: style, into: &single)

        var triple = canvas()
        TextRenderer.draw("First\nSecond\nThird", in: oneLineTall, style: style, into: &triple)

        // Identical ink from three lines and from one is the bug: the extra
        // lines fell outside the frame path and were dropped.
        #expect(inkedPixels(single) == inkedPixels(triple),
                "the short box unexpectedly rendered more than its first line")
        #expect(inkedPixels(single) > 0, "nothing rendered at all")
    }

    @Test("A box grown to the measured height keeps every line")
    func measuredBoxKeepsEveryLine() {
        let style = TextRenderer.Style(pointSize: 20, colour: .black)
        let width = 300
        let text = "First\nSecond\nThird"

        // This is exactly what the editor now does on every keystroke.
        let needed = TextRenderer.measure(text, style: style, maxWidth: width)
        let grown = PixelRect(x: 10, y: 10, width: width, height: needed.height + 8)

        var one = canvas()
        TextRenderer.draw("First", in: grown, style: style, into: &one)

        var three = canvas()
        TextRenderer.draw(text, in: grown, style: style, into: &three)

        #expect(inkedPixels(three) > inkedPixels(one) * 2,
                "three lines should carry roughly three lines of ink")
    }

    @Test("measure grows with the number of lines")
    func measureGrowsWithLines() {
        let style = TextRenderer.Style(pointSize: 20)
        let one = TextRenderer.measure("First", style: style, maxWidth: 300)
        let three = TextRenderer.measure("First\nSecond\nThird", style: style, maxWidth: 300)
        #expect(three.height > one.height * 2)
    }

    @Test("A narrow box wraps rather than truncating")
    func narrowBoxWraps() {
        let style = TextRenderer.Style(pointSize: 16)
        let wide = TextRenderer.measure("one two three four five", style: style, maxWidth: 400)
        let narrow = TextRenderer.measure("one two three four five", style: style, maxWidth: 80)
        #expect(narrow.height > wide.height, "the narrow box did not wrap")
    }

    // MARK: - Traits

    @Test("Bold and italic resolve to a different face")
    func traitsChangeTheFont() {
        let plain = TextRenderer.Style(fontName: "Helvetica", pointSize: 24)
        var bold = plain
        bold.isBold = true
        var italic = plain
        italic.isItalic = true

        // Helvetica ships both cuts, so these must genuinely differ.
        #expect(plain.makeFont() != bold.makeFont())
        #expect(plain.makeFont() != italic.makeFont())
        #expect(bold.makeFont() != italic.makeFont())
    }

    @Test("Bold lays down more ink than regular")
    func boldIsHeavier() {
        let box = PixelRect(x: 10, y: 10, width: 360, height: 80)
        var style = TextRenderer.Style(fontName: "Helvetica", pointSize: 40, colour: .black)

        var regular = canvas()
        TextRenderer.draw("Handgloves", in: box, style: style, into: &regular)

        style.isBold = true
        var bold = canvas()
        TextRenderer.draw("Handgloves", in: box, style: style, into: &bold)

        #expect(inkedPixels(bold) > inkedPixels(regular))
    }

    @Test("Underline adds a rule under the text")
    func underlineAddsInk() {
        let box = PixelRect(x: 10, y: 10, width: 360, height: 80)
        var style = TextRenderer.Style(fontName: "Helvetica", pointSize: 40, colour: .black)

        var plain = canvas()
        TextRenderer.draw("Handgloves", in: box, style: style, into: &plain)

        style.isUnderlined = true
        var underlined = canvas()
        TextRenderer.draw("Handgloves", in: box, style: style, into: &underlined)

        #expect(inkedPixels(underlined) > inkedPixels(plain))
    }

    @Test("A face with no italic cut falls back rather than shearing")
    func missingTraitFallsBack() {
        // Whatever the installed faces are, resolving a trait must always
        // return a usable font rather than nil-ing out the draw.
        for name in TextRenderer.Style.availableFonts {
            var style = TextRenderer.Style(fontName: name, pointSize: 24)
            style.isBold = true
            style.isItalic = true
            var bitmap = Bitmap(width: 200, height: 60, fill: .white)
            let dirty = TextRenderer.draw(
                "Ag", in: PixelRect(x: 2, y: 2, width: 190, height: 50),
                style: style, into: &bitmap
            )
            #expect(!dirty.isEmpty, "\(name) rendered nothing with bold+italic")
        }
    }
}

/// Arbitrary rotation — the transform Windows 11 Paint shipped in 2026 and the
/// one we lacked.
///
/// The guard that matters is that it does **not** quietly replace the quarter
/// turns. Those are an index permutation and therefore lossless; routing them
/// through a resampling path would soften an image a little more every time
/// someone rotated it.
@Suite("Freeform rotate")
struct FreeformRotateTests {

    private func sample() -> Bitmap {
        var bitmap = Bitmap(width: 40, height: 20, fill: .white)
        for x in 0..<40 {
            bitmap.setPixel(PaintColour.black.rgba8, at: PixelPoint(x: x, y: 5))
        }
        return bitmap
    }

    @Test("The canvas grows to the rotated bounding box")
    func canvasGrowsToFitCorners() {
        let source = sample()
        let rotated = ImageTransform.rotated(source, degrees: 45, fill: .white)
        let result = try! #require(rotated)

        // A 40×20 rotated 45° needs ~42×42; nothing may be cropped.
        #expect(result.width > source.width)
        #expect(result.height > source.height)
        #expect(result.width >= 42 && result.width <= 44)
        #expect(result.height >= 42 && result.height <= 44)
    }

    @Test("Quarter turns stay lossless rather than resampling")
    func quarterTurnsTakeTheExactPath() {
        let source = sample()
        for (degrees, rotation) in [
            (90.0, ImageTransform.Rotation.clockwise90),
            (180.0, .half),
            (270.0, .counterClockwise90),
        ] {
            let viaDegrees = try! #require(ImageTransform.rotated(source, degrees: degrees))
            let exact = ImageTransform.rotated(source, by: rotation)
            #expect(viaDegrees == exact, "\(degrees)° did not take the exact path")
        }
    }

    @Test("Negative and wrapped angles land on the same result")
    func anglesNormalise() {
        let source = sample()
        let minus90 = try! #require(ImageTransform.rotated(source, degrees: -90))
        let plus270 = try! #require(ImageTransform.rotated(source, degrees: 270))
        let plus630 = try! #require(ImageTransform.rotated(source, degrees: 630))
        #expect(minus90 == plus270)
        #expect(plus270 == plus630)
    }

    @Test("Zero is a no-op")
    func zeroChangesNothing() {
        let source = sample()
        #expect(ImageTransform.rotated(source, degrees: 0) == source)
        #expect(ImageTransform.rotated(source, degrees: 360) == source)
    }

    @Test("Exposed corners take the fill colour, not transparency")
    func cornersAreFilled() {
        let source = sample()
        let red = PaintColour(hex: "FF0000")!
        let result = try! #require(ImageTransform.rotated(source, degrees: 30, fill: red))
        // The top-left corner of the bounding box is outside the rotated image.
        #expect(result.pixel(at: PixelPoint(x: 0, y: 0)) == red.rgba8)
    }

    @Test("The result is always a size the engine will accept")
    func resultIsAlwaysSupported() {
        // The size guard is what stops a rotation asking for a canvas the
        // engine refuses to allocate. Checked across the range rather than at
        // the limit: reaching the 20,000px ceiling means allocating 1.6GB, and
        // a test that needs 1.6GB to prove a two-line bounds check is a worse
        // test than one that proves the invariant it actually protects.
        let source = sample()
        for degrees in stride(from: -180.0, through: 180.0, by: 7.5) {
            guard let result = ImageTransform.rotated(source, degrees: degrees) else { continue }
            #expect(
                Bitmap.isSizeSupported(width: result.width, height: result.height),
                "\(degrees)° produced an unsupported \(result.width)×\(result.height)"
            )
            // And it never shrinks — a rotation that cropped would be silently
            // destroying the picture it was asked to straighten.
            #expect(result.width >= source.width || result.height >= source.height)
        }
    }
}
