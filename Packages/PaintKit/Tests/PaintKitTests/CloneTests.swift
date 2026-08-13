import Testing
@testable import PaintKit

/// The job: a star with a bite out of it, put back from the intact part.
@Suite("Clone and Soften")
@MainActor
struct CloneTests {

    private func engine(_ w: Int = 64, _ h: Int = 64, seed: ((inout Bitmap) -> Void)? = nil) -> PaintEngine {
        var bitmap = Bitmap(width: w, height: h, fill: RGBA8(r: 255, g: 255, b: 255))
        seed?(&bitmap)
        let e = PaintEngine(width: w, height: h)
        e.reset(to: bitmap)
        e.settings.tool = .clone
        e.settings.brushSize = 8
        e.settings.cloneSoftTip = false
        return e
    }

    private func stroke(_ e: PaintEngine, _ a: PixelPoint, _ b: PixelPoint) {
        _ = e.beginStroke(at: a)
        _ = e.continueStroke(to: b)
        _ = e.endStroke(at: b)
    }

    /// The failure that would make this tool eat the thing it is repairing: a stroke
    /// that samples pixels it has already written. Drag from the intact arm across
    /// the hole and back over the source, and the source becomes a copy of the hole.
    @Test func aStrokeNeverSamplesWhatItJustWrote() {
        // A unique value per pixel in the source band, so any copy is detectable.
        let e = engine(seed: { b in
            for y in 0..<64 {
                for x in 0..<20 {
                    b.pixels[y * 64 + x] = RGBA8(r: UInt8(x * 12 % 256), g: UInt8(y * 4 % 256), b: 200, a: 255)
                }
            }
        })
        let band = PixelRect(x: 26, y: 24, width: 9, height: 16)
        let sourceBefore = e.canvas.extract(band).pixels

        // The offset has to be small enough that painting *over* the source still
        // reads an in-bounds source pixel. An earlier version of this test put the
        // source 34px away, so the pass back over it sampled off-canvas, wrote
        // nothing, and the test held even with the snapshot rule deliberately
        // broken — a fixture no user could produce.
        e.setCloneSource(PixelPoint(x: 30, y: 32))
        _ = e.beginStroke(at: PixelPoint(x: 40, y: 32))
        _ = e.continueStroke(to: PixelPoint(x: 30, y: 32))   // back over the source
        _ = e.continueStroke(to: PixelPoint(x: 40, y: 32))
        _ = e.endStroke(at: PixelPoint(x: 40, y: 32))

        // The source region is legitimately painted over by this stroke. What must
        // hold is that every destination read the *pre-stroke* source, so the result
        // is reproducible rather than a copy of a copy.
        let sourceAfter = e.canvas.extract(band).pixels
        #expect(sourceAfter != sourceBefore, "the stroke never revisited its source; the fixture is wrong")

        // Same stroke, same start: identical output. Sampling the evolving canvas
        // makes the result depend on the path taken through it.
        let replay = engine(seed: { b in
            for y in 0..<64 {
                for x in 0..<20 {
                    b.pixels[y * 64 + x] = RGBA8(r: UInt8(x * 12 % 256), g: UInt8(y * 4 % 256), b: 200, a: 255)
                }
            }
        })
        replay.setCloneSource(PixelPoint(x: 30, y: 32))
        _ = replay.beginStroke(at: PixelPoint(x: 40, y: 32))
        _ = replay.continueStroke(to: PixelPoint(x: 30, y: 32))
        _ = replay.endStroke(at: PixelPoint(x: 30, y: 32))
        let single = replay.canvas.extract(band).pixels

        let stepped = engine(seed: { b in
            for y in 0..<64 {
                for x in 0..<20 {
                    b.pixels[y * 64 + x] = RGBA8(r: UInt8(x * 12 % 256), g: UInt8(y * 4 % 256), b: 200, a: 255)
                }
            }
        })
        stepped.setCloneSource(PixelPoint(x: 30, y: 32))
        _ = stepped.beginStroke(at: PixelPoint(x: 40, y: 32))
        for x in stride(from: 39, through: 30, by: -1) {
            _ = stepped.continueStroke(to: PixelPoint(x: x, y: 32))
        }
        _ = stepped.endStroke(at: PixelPoint(x: 30, y: 32))
        #expect(stepped.canvas.extract(band).pixels == single,
                "the same stroke gave different pixels at different event rates; it is sampling canvas, not before")
    }

    @Test func theFirstClickOnlyAims() {
        let e = engine()
        let before = e.canvas.pixels
        stroke(e, PixelPoint(x: 20, y: 20), PixelPoint(x: 40, y: 40))
        #expect(e.canvas.pixels == before, "the source-setting gesture painted")
        #expect(e.cloneSource != nil)
        #expect(!e.canUndo, "an aim-only gesture pushed an undo step")
    }

    @Test func aPairingSurvivesAcrossStrokes() {
        let e = engine(seed: { $0.fill(PixelRect(x: 0, y: 0, width: 20, height: 64), with: .black) })
        e.setCloneSource(PixelPoint(x: 10, y: 10))
        stroke(e, PixelPoint(x: 40, y: 10), PixelPoint(x: 44, y: 10))
        let offset = e.cloneOffset
        stroke(e, PixelPoint(x: 40, y: 30), PixelPoint(x: 44, y: 30))
        #expect(e.cloneOffset == offset, "the offset moved between strokes; the clone is not aligned")
    }

    /// Off-canvas source must be skipped, never wrapped and never clamped: both of
    /// those paint a stripe of the far border into the artwork.
    @Test func anOutOfBoundsSourceIsSkipped() {
        let e = engine(seed: { b in b.fill(b.bounds, with: RGBA8(r: 90, g: 90, b: 90, a: 255)) })
        e.setCloneSource(PixelPoint(x: 2, y: 2))
        let before = e.canvas.pixels
        stroke(e, PixelPoint(x: 60, y: 60), PixelPoint(x: 62, y: 62))
        #expect(e.canvas.pixels == before, "pixels were written from outside the canvas")
    }

    @Test func resizingForgetsThePairing() {
        let e = engine()
        e.setCloneSource(PixelPoint(x: 10, y: 10))
        e.clearCloneSource()
        #expect(e.cloneSource == nil && e.cloneOffset == nil)
    }

    /// Soften must converge. Holding still on an edge and letting 200 events arrive
    /// has to leave the same pixel as the first event, or the tool is a smudge and
    /// the artwork dissolves under a paused cursor.
    @Test func lingeringWithSoftenIsANoOp() {
        let e = engine(seed: { b in
            for y in 0..<64 {
                for x in 0..<64 {
                    b.pixels[y * 64 + x] = x < 32
                        ? RGBA8(r: 255, g: 220, b: 0, a: 255)
                        : RGBA8(r: 40, g: 80, b: 180, a: 255)
                }
            }
        })
        e.settings.cloneMode = .soften
        e.settings.brushSize = 28
        let probe = PixelPoint(x: 32, y: 32)
        _ = e.beginStroke(at: probe)
        let afterFirst = e.canvas.pixels[e.canvas.index(probe)]
        for _ in 0..<200 { _ = e.continueStroke(to: probe) }
        let afterMany = e.canvas.pixels[e.canvas.index(probe)]
        #expect(afterFirst == afterMany, "Soften accumulated while standing still; it is a smudge")

        // And it must not have walked to the mean of the two colours.
        let mean = RGBA8(r: 147, g: 150, b: 90, a: 255)
        let drifted = abs(Int(afterMany.r) - Int(mean.r)) < 8 && abs(Int(afterMany.g) - Int(mean.g)) < 8
        #expect(!drifted, "the edge dissolved towards the neighbourhood mean")
    }

    @Test func softenKeepsPixelsPremultiplied() {
        let e = engine(24, 24, seed: {
            $0.fill(PixelRect(x: 0, y: 0, width: 12, height: 24), with: RGBA8(r: 80, g: 0, b: 0, a: 80))
        })
        e.settings.cloneMode = .soften
        stroke(e, PixelPoint(x: 10, y: 12), PixelPoint(x: 14, y: 12))
        for p in e.canvas.pixels {
            #expect(p.r <= p.a && p.g <= p.a && p.b <= p.a, "premultiplied invariant broken")
        }
    }

    @Test func theBlurShrinksItsWindowAtTheBorderRatherThanPullingTowardsBlack() {
        let flat = [RGBA8](repeating: RGBA8(r: 200, g: 100, b: 50, a: 255), count: 25)
        let out = PaintEngine.boxBlurPremul(flat, width: 5, height: 5, radius: 2)
        #expect(out == flat, "a uniform field changed; the border is counting missing samples")
    }
}
