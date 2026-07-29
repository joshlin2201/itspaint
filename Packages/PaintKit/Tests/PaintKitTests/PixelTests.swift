import Testing
@testable import PaintKit

// Deterministic pixel assertions rather than image snapshots: they run in
// milliseconds, need no Git LFS or third-party package, and when one fails it
// names the exact pixel that moved instead of showing two similar-looking PNGs.

@Suite("RGBA8 compositing")
struct RGBA8Tests {

    @Test("Opaque source replaces the destination exactly")
    func opaqueReplaces() {
        let src = RGBA8(r: 10, g: 20, b: 30, a: 255)
        #expect(src.overCompositing(.white) == src)
    }

    @Test("Fully transparent source leaves the destination untouched")
    func transparentIsNoOp() {
        let dst = RGBA8(r: 1, g: 2, b: 3, a: 255)
        #expect(RGBA8.clear.overCompositing(dst) == dst)
    }

    @Test("Half-alpha black over white lands mid-grey")
    func halfAlphaBlend() {
        // Premultiplied 50% black is (0,0,0,128).
        let src = RGBA8(r: 0, g: 0, b: 0, a: 128)
        let out = src.overCompositing(.white)
        // white * (1 - 128/255) ≈ 127
        #expect(out.r == 127 && out.g == 127 && out.b == 127)
        #expect(out.a == 255)
    }

    @Test("Repeated compositing does not drift darker")
    func noRoundingDrift() {
        // Rounding to nearest (not truncating) keeps a long chain of fully
        // opaque stamps stable. Truncation used to bleed one level per pass.
        var pixel = RGBA8.white
        let opaque = RGBA8(r: 200, g: 100, b: 50, a: 255)
        for _ in 0..<500 { pixel = opaque.overCompositing(pixel) }
        #expect(pixel == opaque)
    }

    @Test("Coverage scales all premultiplied channels")
    func coverageScales() {
        let full = RGBA8(r: 200, g: 100, b: 50, a: 255)
        #expect(full.withCoverage(255) == full)
        #expect(full.withCoverage(0) == .clear)
        let half = full.withCoverage(128)
        #expect(half.a == 128)
        #expect(half.r == 100)
    }

    @Test("Unpremultiply round-trips an opaque colour")
    func unpremultiplyOpaque() {
        let c = RGBA8(r: 12, g: 34, b: 56, a: 255)
        let (r, g, b, a) = c.unpremultiplied
        #expect((r, g, b, a) == (12, 34, 56, 255))
    }
}

@Suite("PixelRect")
struct PixelRectTests {

    @Test("Corner init is inclusive of both corners")
    func cornersInclusive() {
        let r = PixelRect(corners: PixelPoint(x: 2, y: 3), PixelPoint(x: 4, y: 6))
        #expect(r == PixelRect(x: 2, y: 3, width: 3, height: 4))
    }

    @Test("Corner init is order independent")
    func cornersOrderIndependent() {
        let a = PixelRect(corners: PixelPoint(x: 9, y: 9), PixelPoint(x: 1, y: 1))
        let b = PixelRect(corners: PixelPoint(x: 1, y: 1), PixelPoint(x: 9, y: 9))
        #expect(a == b)
    }

    @Test("Disjoint rects intersect to empty, not to a negative size")
    func disjointIntersection() {
        let a = PixelRect(x: 0, y: 0, width: 5, height: 5)
        let b = PixelRect(x: 100, y: 100, width: 5, height: 5)
        #expect(a.intersection(b).isEmpty)
    }

    @Test("Union with empty is identity in both directions")
    func unionWithEmpty() {
        let a = PixelRect(x: 3, y: 4, width: 5, height: 6)
        #expect(a.union(.empty) == a)
        #expect(PixelRect.empty.union(a) == a)
    }

    @Test("Contains uses half-open bounds")
    func containsHalfOpen() {
        let r = PixelRect(x: 0, y: 0, width: 4, height: 4)
        #expect(r.contains(PixelPoint(x: 0, y: 0)))
        #expect(r.contains(PixelPoint(x: 3, y: 3)))
        #expect(!r.contains(PixelPoint(x: 4, y: 0)))
    }

    @Test("Over-inset collapses to empty rather than inverting")
    func overInset() {
        let r = PixelRect(x: 0, y: 0, width: 4, height: 4)
        #expect(r.insetBy(10).isEmpty)
    }
}

@Suite("Bitmap")
struct BitmapTests {

    @Test("The shared size budget accepts 8K and rejects hostile dimensions")
    func sizeBudget() {
        #expect(Bitmap.maximumDimension == 20_000)
        #expect(Bitmap.maximumPixelCount == 33_554_432)
        #expect(Bitmap.isSizeSupported(width: 7_680, height: 4_320))
        #expect(Bitmap.isSizeSupported(width: 8_192, height: 4_096))

        #expect(!Bitmap.isSizeSupported(width: 20_001, height: 1))
        #expect(!Bitmap.isSizeSupported(width: 8_193, height: 4_096))
        #expect(!Bitmap.isSizeSupported(width: Int.max, height: 2))
        #expect(!Bitmap.isSizeSupported(width: 0, height: 100))
    }

    @Test("The failable pixel initializer rejects unsupported and overflowing sizes")
    func pixelInitializerRejectsUnsupportedSize() {
        #expect(Bitmap(width: 20_001, height: 1, pixels: []) == nil)
        #expect(Bitmap(width: Int.max, height: 2, pixels: []) == nil)
    }

    @Test("A new bitmap is uniformly filled")
    func initialFill() {
        let bmp = Bitmap(width: 4, height: 3, fill: .white)
        #expect(bmp.count == 12)
        #expect(bmp.pixels.allSatisfy { $0 == .white })
    }

    @Test("Out-of-bounds writes are ignored, not crashes")
    func outOfBoundsWriteIgnored() {
        var bmp = Bitmap(width: 4, height: 4)
        bmp.setPixel(.black, at: PixelPoint(x: -1, y: 0))
        bmp.setPixel(.black, at: PixelPoint(x: 99, y: 99))
        #expect(bmp.pixels.allSatisfy { $0 == .white })
    }

    @Test("extract then restore is lossless — the undo contract")
    func extractRestoreRoundTrip() {
        var bmp = Bitmap(width: 8, height: 8)
        Raster.fillRect(PixelRect(x: 2, y: 2, width: 4, height: 4), colour: .black, into: &bmp)
        let before = bmp

        let rect = PixelRect(x: 1, y: 1, width: 6, height: 6)
        let patch = bmp.extract(rect)

        Raster.floodFill(from: PixelPoint(x: 3, y: 3), with: RGBA8(r: 255, g: 0, b: 0), into: &bmp)
        #expect(bmp != before)

        bmp.restore(patch.pixels, to: patch.rect)
        #expect(bmp == before)
    }

    @Test("extract clips to bounds instead of reading past the edge")
    func extractClips() {
        let bmp = Bitmap(width: 4, height: 4)
        let patch = bmp.extract(PixelRect(x: 2, y: 2, width: 10, height: 10))
        #expect(patch.rect == PixelRect(x: 2, y: 2, width: 2, height: 2))
        #expect(patch.pixels.count == 4)
    }

    @Test("Compositing skips fully transparent source pixels")
    func compositeSkipsTransparent() {
        var dst = Bitmap(width: 4, height: 4, fill: .white)
        var src = Bitmap(width: 2, height: 2, fill: .clear)
        src.setPixel(.black, at: PixelPoint(x: 0, y: 0))
        dst.composite(src, at: PixelPoint(x: 1, y: 1))
        #expect(dst.pixel(at: PixelPoint(x: 1, y: 1)) == .black)
        #expect(dst.pixel(at: PixelPoint(x: 2, y: 2)) == .white)
    }
}
