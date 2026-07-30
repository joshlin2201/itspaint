import Foundation
import Testing
@testable import PaintKit

/// Keying ink off paper, tested against the paper you actually get: cream, noisy,
/// and lit unevenly.
@Suite("Ink extraction")
struct InkExtractorTests {

    /// A signature-ish stroke on paper, with the two things that break a fixed
    /// threshold: per-pixel noise, and a brightness gradient across the sheet.
    ///
    /// Deterministic — a failure has to be reproducible, and a random fixture that
    /// fails one run in twenty is worse than no fixture.
    private func photographedSignature(
        width: Int = 120,
        height: Int = 60,
        gradient: Int = 0,
        paper: Int = 236,
        ink: Int = 58
    ) -> (bitmap: Bitmap, strokeRect: PixelRect) {
        var bmp = Bitmap(width: width, height: height, fill: .white)
        for y in 0..<height {
            for x in 0..<width {
                // Paper: base level, a lighting ramp left to right, and ±4 noise.
                let ramp = gradient * x / max(1, width - 1)
                let noise = ((x * 13 + y * 7) % 9) - 4
                let level = min(255, max(0, paper - ramp + noise))
                bmp.setPixel(
                    RGBA8(r: UInt8(level), g: UInt8(level), b: UInt8(level), a: 255),
                    at: PixelPoint(x: x, y: y)
                )
            }
        }

        // A stroke through the middle third, two rows thick.
        let stroke = PixelRect(x: 30, y: 26, width: 60, height: 8)
        for y in stroke.minY..<stroke.maxY {
            for x in stroke.minX..<stroke.maxX {
                let ramp = gradient * x / max(1, width - 1)
                let level = min(255, max(0, ink - ramp / 3))
                bmp.setPixel(
                    RGBA8(r: UInt8(level), g: UInt8(level), b: UInt8(level), a: 255),
                    at: PixelPoint(x: x, y: y)
                )
            }
        }
        return (bmp, stroke)
    }

    @Test("Paper becomes transparent and ink becomes opaque")
    func keysPaperAway() throws {
        let (source, stroke) = photographedSignature()
        let keyed = try InkExtractor.ink(from: source, colour: .black)

        // Trimmed to the stroke, so the result is the signature and not the sheet.
        #expect(keyed.width == stroke.width)
        #expect(keyed.height == stroke.height)
        // And every pixel of it is ink.
        #expect(keyed.pixels.allSatisfy { $0.a > 200 }, "the stroke did not come out solid")
    }

    /// The case a global threshold cannot survive: the dark end of the paper is
    /// darker than the light end of the ink would be under uniform light.
    @Test("A lighting gradient across the page does not become a grey wash")
    func survivesALightingGradient() throws {
        let (source, stroke) = photographedSignature(gradient: 70)
        let keyed = try InkExtractor.ink(from: source, colour: .black)

        #expect(keyed.width == stroke.width, "trim caught paper, not just ink")
        #expect(keyed.height == stroke.height)
        #expect(keyed.pixels.allSatisfy { $0.a > 150 })
    }

    @Test("The ink takes the colour it is asked for, not the colour it was")
    func recoloursInk() throws {
        let (source, _) = photographedSignature()
        let blue = RGBA8(r: 20, g: 40, b: 200)
        let keyed = try InkExtractor.ink(from: source, colour: blue)

        let opaque = keyed.pixels.filter { $0.a == 255 }
        #expect(!opaque.isEmpty)
        #expect(opaque.allSatisfy { $0.r == blue.r && $0.g == blue.g && $0.b == blue.b })
    }

    @Test("Edges keep partial coverage instead of stair-stepping")
    func edgesStaySoft() throws {
        // A stroke with a genuinely grey halo, the way any real photograph has.
        var bmp = Bitmap(width: 40, height: 40, fill: RGBA8(r: 240, g: 240, b: 240))
        for y in 14..<26 {
            for x in 14..<26 {
                let edge = (x == 14 || x == 25 || y == 14 || y == 25)
                let level: UInt8 = edge ? 150 : 40
                bmp.setPixel(RGBA8(r: level, g: level, b: level), at: PixelPoint(x: x, y: y))
            }
        }
        let keyed = try InkExtractor.ink(from: bmp)
        let partial = keyed.pixels.filter { $0.a > 0 && $0.a < 250 }
        #expect(!partial.isEmpty, "every pixel went fully in or out — that is a fax, not a signature")
    }

    /// This is the trackpad-capture path: there is no paper to estimate.
    ///
    /// **The sheet is deliberately mostly empty**, because that is the proportion a
    /// real signing box has — a thin stroke across a wide sheet is well under one
    /// percent ink. A denser fixture is what hid a bug that rejected every signature
    /// signed in the box: with ink over the fourth percentile the paper estimate's
    /// blank-page guard happened to survive, and at realistic sparsity both
    /// percentiles read 255 and it threw `noInkFound`.
    @Test("A sparse stroke drawn straight onto transparency keeps its own alpha")
    func trustsAnAlreadyKeyedSource() throws {
        var bmp = Bitmap(width: 200, height: 80, fill: .clear)
        for x in 60..<100 {
            bmp.setPixel(RGBA8(r: 0, g: 0, b: 0, a: 255), at: PixelPoint(x: x, y: 40))
            bmp.setPixel(RGBA8(r: 0, g: 0, b: 0, a: 128), at: PixelPoint(x: x, y: 41))
        }
        let keyed = try InkExtractor.ink(from: bmp)
        #expect(keyed.width == 40 && keyed.height == 2)
        #expect(keyed.pixels.contains { $0.a > 200 })
        #expect(keyed.pixels.contains { (100...160).contains(Int($0.a)) }, "the soft row was flattened")
    }

    @Test("A blank page is reported, not keyed into noise")
    func blankPageFails() {
        var bmp = Bitmap(width: 60, height: 60, fill: .white)
        // Only paper noise, no stroke.
        for y in 0..<60 {
            for x in 0..<60 {
                let level = UInt8(238 + ((x + y) % 5) - 2)
                bmp.setPixel(RGBA8(r: level, g: level, b: level), at: PixelPoint(x: x, y: y))
            }
        }
        #expect(throws: InkExtractor.Failure.noInkFound) {
            try InkExtractor.ink(from: bmp)
        }
    }

    @Test("A photo of something dark is not a signature")
    func darkPhotoFails() {
        // Real contrast, so this clears `noInkFound` — but three quarters of the
        // frame is the dark thing, which no signature ever is.
        var bmp = Bitmap(width: 60, height: 60, fill: RGBA8(r: 245, g: 245, b: 245))
        for y in 15..<60 {
            for x in 0..<60 {
                bmp.setPixel(RGBA8(r: 45, g: 45, b: 45), at: PixelPoint(x: x, y: y))
            }
        }
        #expect(throws: InkExtractor.Failure.notASignature) {
            try InkExtractor.ink(from: bmp)
        }
    }

    @Test("Premultiplied input does not read as darker than it is")
    func luminanceUnpremultiplies() {
        // A half-transparent black pixel stores as (0,0,0,128). Read raw it is the
        // darkest thing on the page; unpremultiplied it is still black but only
        // half covering, which is what alpha is for.
        let soft = RGBA8(r: 0, g: 0, b: 0, a: 128)
        let solid = RGBA8(r: 0, g: 0, b: 0, a: 255)
        #expect(InkExtractor.luminance(of: soft) == InkExtractor.luminance(of: solid))
        // And a fully transparent pixel is paper, not ink.
        #expect(InkExtractor.luminance(of: .clear) == 255)
    }

    /// The despeckle pass has to distinguish grain from faint writing, which is the
    /// whole reason it exists instead of a higher coverage floor.
    @Test("Isolated specks go, connected faint strokes stay")
    func despeckleKeepsStrokes() {
        var bmp = Bitmap(width: 20, height: 20, fill: .clear)
        // A faint but connected two-pixel-wide line.
        for x in 4..<16 {
            bmp.setPixel(RGBA8(r: 0, g: 0, b: 0, a: 60), at: PixelPoint(x: x, y: 9))
            bmp.setPixel(RGBA8(r: 0, g: 0, b: 0, a: 60), at: PixelPoint(x: x, y: 10))
        }
        // Three lone specks, one of them darker than the line.
        for p in [PixelPoint(x: 1, y: 1), PixelPoint(x: 18, y: 3), PixelPoint(x: 2, y: 17)] {
            bmp.setPixel(RGBA8(r: 0, g: 0, b: 0, a: 255), at: p)
        }

        InkExtractor.despeckle(&bmp)

        #expect(bmp.pixel(at: PixelPoint(x: 10, y: 9))?.a == 60, "the faint line was despeckled")
        #expect(bmp.pixel(at: PixelPoint(x: 1, y: 1))?.a == 0)
        #expect(bmp.pixel(at: PixelPoint(x: 18, y: 3))?.a == 0)
        #expect(bmp.pixel(at: PixelPoint(x: 2, y: 17))?.a == 0)
    }

    @Test("Percentiles ignore single outliers")
    func percentileIsRobust() {
        // 998 mid-greys, one black speck, one white speck.
        var values = [UInt8](repeating: 128, count: 998)
        values.append(0)
        values.append(255)
        #expect(InkExtractor.percentile(values, 0.92) == 128)
        #expect(InkExtractor.percentile(values, 0.04) == 128)
    }
}
