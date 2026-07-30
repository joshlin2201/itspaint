import Foundation

/// Turns a picture of ink on paper into ink on nothing.
///
/// This is what makes an inserted signature look signed rather than pasted. A
/// photo of a signature is dark strokes on off-white paper: drop it onto artwork
/// unchanged and you get a white rectangle with a scribble in it. What you want is
/// the strokes, keyed to transparent, in a colour you chose.
///
/// The tricky part is that "white paper" is never white and never uniform. A phone
/// photo has a lighting gradient across it, the paper is cream or grey, JPEG has
/// been through it, and the ink itself is not black but a dark blue-grey with
/// antialiased edges. A fixed threshold gives you either a chopped-up signature or
/// a grey haze of paper.
public enum InkExtractor {

    /// How the extraction went, and why not when it did not.
    public enum Failure: Error, Equatable, Sendable {
        /// Nothing dark enough to be ink, relative to the paper.
        case noInkFound
        /// Ink was found, but it covered essentially the whole frame — a photo of
        /// a dark surface rather than of a signature.
        case notASignature
    }

    /// Ink lifted from `bitmap`, recoloured and trimmed to its own bounds.
    ///
    /// **Alpha comes from how dark a pixel is relative to its own local paper**,
    /// so stroke ends and antialiased edges stay soft instead of turning into
    /// stair-steps — a hard threshold is what makes a keyed signature look like a
    /// fax.
    ///
    /// *Local*, not global, and that is the whole difficulty. A phone photo of a
    /// page has a lighting falloff across it, and one paper level for the whole
    /// frame cannot serve both ends: set it for the bright side and the dim side
    /// keys in as a grey wash at a third opacity; set it for the dim side and the
    /// bright side eats the lighter parts of the strokes. So the paper level is
    /// estimated per tile and interpolated between tiles, which costs one coarse
    /// grid and removes the gradient from the problem entirely.
    ///
    /// - Parameters:
    ///   - bitmap: the captured or photographed signature.
    ///   - colour: the colour the ink becomes. The photographed colour is
    ///     discarded on purpose — it is paper-tinted and rarely what anyone wants.
    ///   - softness: how much of the paper-to-ink ramp is kept as partial alpha.
    ///     Lower is more contrast; the default keeps edges smooth.
    public static func ink(
        from bitmap: Bitmap,
        colour: RGBA8 = .black,
        softness: Double = 0.55
    ) throws -> Bitmap {
        guard bitmap.width > 0, bitmap.height > 0 else { throw Failure.noInkFound }

        var out = Bitmap(width: bitmap.width, height: bitmap.height, fill: .clear)
        var inked = 0

        // **A mostly transparent source was drawn, not photographed**, and there is
        // no paper in it to estimate. Alpha already *is* the coverage, so it is
        // taken at face value — this is the trackpad path.
        //
        // It has to be decided before the paper estimate rather than per pixel,
        // because a clear pixel reads as 255 luminance. A signed box is around one
        // percent ink, so both percentiles below land on 255, the span collapses to
        // zero, and the blank-page guard rejects a perfectly good signature. Half
        // the frame is the test because a photo cropped to a non-rectangular shape
        // carries some transparency too, and that one does need the estimate.
        let clear = bitmap.pixels.lazy.filter { $0.a == 0 }.count
        if clear * 2 > bitmap.count {
            for i in 0..<bitmap.count where bitmap.pixels[i].a > 0 {
                out.pixels[i] = premultiplied(colour, alpha: bitmap.pixels[i].a)
                inked += 1
            }
        } else {
            // Luminance up front: every step below reads it more than once, and
            // recomputing per pass is the difference between one pass over the image
            // and three.
            var luminance = [UInt8](repeating: 0, count: bitmap.count)
            for i in 0..<bitmap.count {
                luminance[i] = Self.luminance(of: bitmap.pixels[i])
            }

            let paper = percentile(luminance, 0.92)
            let core = percentile(luminance, 0.04)

            // Under about a sixth of the range there is no signature here — a blank
            // page, or a photo of something uniformly dark. Keying it anyway produces
            // a rectangle of noise, which is worse than saying so.
            let span = Int(paper) - Int(core)
            guard span >= 40 else { throw Failure.noInkFound }

            let field = PaperField(
                luminance: luminance, width: bitmap.width, height: bitmap.height,
                // An ink-flooded tile would otherwise report the ink as its paper and
                // erase the very stroke that filled it. Nothing may claim its paper is
                // darker than halfway to the ink.
                floor: Double(core) + Double(span) * 0.5
            )

            // How much darker than its own paper a pixel has to be to count as solid.
            // Scaled by `softness` so the caller can trade edge smoothness for punch.
            let solidFraction = 0.55 + 0.25 * (1 - softness)

            for y in 0..<bitmap.height {
                for x in 0..<bitmap.width {
                    let i = y * bitmap.width + x

                    let localPaper = field.level(atX: x, y: y)
                    let depth = localPaper - Double(luminance[i])
                    let solidDepth = max(1, (localPaper - Double(core)) * solidFraction)
                    let coverage = min(1, max(0, depth / solidDepth))

                    // A floor, not a fade to nothing. Paper noise still clears zero
                    // even against a local estimate — ±4 levels of sensor grain on a
                    // ramp of ninety is a few percent of coverage across the entire
                    // sheet, which reads as a grey haze the moment the signature lands
                    // on light artwork. Real ink is nowhere near this faint.
                    guard coverage > 0.15 else { continue }

                    let alpha = UInt8(min(255, (coverage * 255).rounded()))
                    out.pixels[i] = premultiplied(colour, alpha: alpha)
                    inked += 1
                }
            }
        }

        guard inked > 0 else { throw Failure.noInkFound }
        // A signature is strokes on a page. Past about two thirds coverage this is
        // a photo of a dark wall, and keying it would hand back a solid slab.
        guard Double(inked) / Double(bitmap.count) < 0.66 else { throw Failure.notASignature }

        despeckle(&out)
        return trimmedToInk(out) ?? out
    }

    /// Drop pixels that have almost no inked neighbours.
    ///
    /// **A signature is connected strokes**, so an isolated dot is not part of one.
    /// Sensor grain and the estimate's own error at the frame edge — where there is
    /// no further tile centre to interpolate towards, so the local paper level is
    /// slightly too bright — both surface as single stray pixels a few percent over
    /// the coverage floor. Seven of them in a 120×60 fixture was enough to stretch
    /// the trim box from the signature to most of the page, which is the visible
    /// symptom: a stamp whose resize handles sit far away from any ink.
    ///
    /// This is why the fix is not simply a higher floor. The floor that would catch
    /// these also erases genuinely faint pencil, and faint pencil is connected.
    static func despeckle(_ bitmap: inout Bitmap) {
        let source = bitmap.pixels
        for y in 0..<bitmap.height {
            for x in 0..<bitmap.width {
                let i = y * bitmap.width + x
                guard source[i].a > 0 else { continue }

                var neighbours = 0
                for dy in -1...1 {
                    let ny = y + dy
                    guard ny >= 0, ny < bitmap.height else { continue }
                    for dx in -1...1 where !(dx == 0 && dy == 0) {
                        let nx = x + dx
                        guard nx >= 0, nx < bitmap.width else { continue }
                        if source[ny * bitmap.width + nx].a > 0 { neighbours += 1 }
                    }
                }
                if neighbours < 2 { bitmap.pixels[i] = .clear }
            }
        }
    }

    /// The paper level across the image, estimated per tile and read back
    /// bilinearly.
    ///
    /// Tiles are deliberately coarse. Fine tiles track the lighting more closely
    /// but each one sees less paper, so a tile landing inside a thick stroke has
    /// nothing but ink to measure; coarse tiles always have paper in view. Around
    /// 24px is the balance, bounded so a thumbnail still gets a grid and a photo
    /// does not get a thousand of them.
    struct PaperField {
        private let levels: [Double]
        private let columns: Int
        private let rows: Int
        private let tile: Double

        init(luminance: [UInt8], width: Int, height: Int, floor: Double) {
            let tileSize = max(8, min(64, max(width, height) / 12))
            let columns = max(1, (width + tileSize - 1) / tileSize)
            let rows = max(1, (height + tileSize - 1) / tileSize)

            var levels = [Double](repeating: 0, count: columns * rows)
            for row in 0..<rows {
                for column in 0..<columns {
                    var histogram = [Int](repeating: 0, count: 256)
                    var count = 0
                    let y0 = row * tileSize, y1 = min(height, y0 + tileSize)
                    let x0 = column * tileSize, x1 = min(width, x0 + tileSize)
                    for y in y0..<y1 {
                        let base = y * width
                        for x in x0..<x1 {
                            histogram[Int(luminance[base + x])] += 1
                            count += 1
                        }
                    }
                    // The *top* of the tile's distribution, not its middle:
                    // an estimate sitting inside the paper's own noise leaves
                    // half of every tile reading a few percent darker than
                    // "paper", and that is precisely the haze.
                    levels[row * columns + column] = max(
                        floor, Double(Self.level(histogram, count: count, fraction: 0.97))
                    )
                }
            }

            self.levels = levels
            self.columns = columns
            self.rows = rows
            self.tile = Double(tileSize)
        }

        /// Bilinear between tile centres, so the estimate has no visible tile
        /// edges — a nearest-tile lookup would print the grid into the alpha.
        func level(atX x: Int, y: Int) -> Double {
            let gx = min(max((Double(x) + 0.5) / tile - 0.5, 0), Double(columns - 1))
            let gy = min(max((Double(y) + 0.5) / tile - 0.5, 0), Double(rows - 1))
            let x0 = Int(gx), y0 = Int(gy)
            let x1 = min(x0 + 1, columns - 1), y1 = min(y0 + 1, rows - 1)
            let fx = gx - Double(x0), fy = gy - Double(y0)

            let top = levels[y0 * columns + x0] * (1 - fx) + levels[y0 * columns + x1] * fx
            let bottom = levels[y1 * columns + x0] * (1 - fx) + levels[y1 * columns + x1] * fx
            return top * (1 - fy) + bottom * fy
        }

        private static func level(_ histogram: [Int], count: Int, fraction: Double) -> Int {
            guard count > 0 else { return 255 }
            let target = Int((Double(count - 1) * fraction).rounded())
            var seen = 0
            for level in 0..<256 {
                seen += histogram[level]
                if seen > target { return level }
            }
            return 255
        }
    }

    /// The bitmap cropped to the pixels that carry any coverage.
    ///
    /// Captured signatures are mostly empty — a trackpad sheet or a photo frames
    /// far more page than writing — and an untrimmed stamp would insert a mostly
    /// invisible rectangle whose resize handles sit nowhere near the ink.
    public static func trimmedToInk(_ bitmap: Bitmap) -> Bitmap? {
        var minX = bitmap.width, minY = bitmap.height, maxX = -1, maxY = -1
        for y in 0..<bitmap.height {
            let row = y * bitmap.width
            for x in 0..<bitmap.width where bitmap.pixels[row + x].a > 0 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return ImageTransform.cropped(
            bitmap,
            to: PixelRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        )
    }

    // MARK: - Internals

    /// Rec. 601 luma on **un**premultiplied channels.
    ///
    /// Bitmaps here are premultiplied, so a half-transparent black stroke stores
    /// as near-zero in every channel and would read as the darkest ink on the
    /// page. Dividing the alpha back out is what stops a soft stroke edge scoring
    /// darker than the stroke itself.
    static func luminance(of pixel: RGBA8) -> UInt8 {
        guard pixel.a > 0 else { return 255 }
        let scale = 255.0 / Double(pixel.a)
        let r = min(255, Double(pixel.r) * scale)
        let g = min(255, Double(pixel.g) * scale)
        let b = min(255, Double(pixel.b) * scale)
        return UInt8(min(255, (0.299 * r + 0.587 * g + 0.114 * b).rounded()))
    }

    /// The value at `fraction` through the sorted distribution.
    ///
    /// Counting sort over 256 buckets rather than sorting the array: this runs on
    /// every pixel of a phone photo, and `sort()` on twelve million elements to
    /// read two numbers off it is the wrong shape of work.
    static func percentile(_ values: [UInt8], _ fraction: Double) -> UInt8 {
        guard !values.isEmpty else { return 0 }
        var histogram = [Int](repeating: 0, count: 256)
        for v in values { histogram[Int(v)] += 1 }

        let target = Int((Double(values.count - 1) * fraction).rounded())
        var seen = 0
        for level in 0..<256 {
            seen += histogram[level]
            if seen > target { return UInt8(level) }
        }
        return 255
    }

    private static func premultiplied(_ colour: RGBA8, alpha: UInt8) -> RGBA8 {
        guard alpha < 255 else { return RGBA8(r: colour.r, g: colour.g, b: colour.b, a: 255) }
        let f = Double(alpha) / 255
        return RGBA8(
            r: UInt8((Double(colour.r) * f).rounded()),
            g: UInt8((Double(colour.g) * f).rounded()),
            b: UInt8((Double(colour.b) * f).rounded()),
            a: alpha
        )
    }
}
