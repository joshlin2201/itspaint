import Foundation
import Testing
@testable import PaintKit

#if DEBUG
/// Unoptimised builds run this engine 40–140× slower, so timings there measure
/// the compiler rather than the algorithm. Asserting against them would produce
/// a permanently red suite that everyone learns to ignore.
let performanceBudgetsApply = false
#else
let performanceBudgetsApply = true
#endif

/// Throughput guards. Run with `swift test -c release`.
///
/// Deliberately generous — they exist to catch an order-of-magnitude regression
/// (an O(canvas) operation sneaking into a per-event path), not to police
/// microseconds. A tight bound would fail on a loaded machine and teach
/// everyone to ignore the suite.
@Suite("Performance", .serialized, .enabled(if: performanceBudgetsApply))
struct PerformanceTests {

    /// Wall-clock milliseconds for `body`.
    private func milliseconds(_ body: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        body()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    @Test("A long freehand stroke on a large canvas stays interactive")
    func freehandThroughput() {
        // 2000×1500 is a realistic large canvas (a retina screenshot).
        let engine = PaintEngine(canvas: Bitmap(width: 2000, height: 1500))
        engine.settings.tool = .brush
        engine.settings.brushSize = 24
        engine.settings.brushShape = .soft

        let elapsed = milliseconds {
            engine.beginStroke(at: PixelPoint(x: 20, y: 750))
            for x in stride(from: 20, through: 1980, by: 4) {
                engine.continueStroke(to: PixelPoint(x: x, y: 750 + Int(200 * sin(Double(x) / 90))))
            }
            engine.endStroke()
        }

        // ~490 segments. Budget allows ~1ms each; the real figure is far lower.
        #expect(elapsed < 500, "freehand stroke took \(Int(elapsed))ms")
    }

    @Test("A live shape preview does not cost a full canvas per frame")
    func shapePreviewThroughput() {
        // Each preview frame rolls back the previous one and redraws. If that
        // rollback ever became full-canvas, this is where it would show.
        let engine = PaintEngine(canvas: Bitmap(width: 2000, height: 1500))
        engine.settings.tool = .shape
        engine.settings.shapeKind = .ellipse
        engine.settings.shapeStyle = .outline
        engine.settings.brushSize = 3

        let elapsed = milliseconds {
            engine.beginStroke(at: PixelPoint(x: 100, y: 100))
            for i in 1...120 {
                engine.continueStroke(to: PixelPoint(x: 100 + i * 12, y: 100 + i * 9))
            }
            engine.endStroke()
        }

        #expect(elapsed < 900, "shape preview took \(Int(elapsed))ms")
    }

    @Test("Stamping is not dominated by per-pixel transcendental maths")
    func stampThroughput() {
        // The brush mask is precomputed; if someone reintroduces a sqrt inside
        // the per-pixel loop this budget is what catches it.
        var bitmap = Bitmap(width: 1200, height: 1200)
        let brush = Brush(shape: .soft, size: 48)

        let elapsed = milliseconds {
            for i in 0..<400 {
                Raster.stamp(
                    brush, colour: .black,
                    at: PixelPoint(x: 60 + (i % 40) * 26, y: 60 + (i / 40) * 26),
                    into: &bitmap
                )
            }
        }

        #expect(elapsed < 400, "400 soft stamps took \(Int(elapsed))ms")
    }

    @Test("Filling a large region completes promptly")
    func floodFillThroughput() {
        var bitmap = Bitmap(width: 2000, height: 1500)
        let elapsed = milliseconds {
            Raster.floodFill(
                from: PixelPoint(x: 1000, y: 750),
                with: RGBA8(r: 10, g: 120, b: 200),
                into: &bitmap
            )
        }
        #expect(elapsed < 600, "3M-pixel flood fill took \(Int(elapsed))ms")
    }

    @Test("Undo capture is proportional to the stroke, not the canvas")
    func undoCaptureIsScoped() {
        // The load-bearing property of rect-scoped undo. A tiny dot on a huge
        // canvas must not retain a full frame.
        let engine = PaintEngine(canvas: Bitmap(width: 3000, height: 2000))
        engine.settings.tool = .pencil
        engine.beginStroke(at: PixelPoint(x: 1500, y: 1000))
        engine.endStroke()

        // A whole frame would be 3000×2000×4 = 24 MB. A dot is a few bytes.
        #expect(engine.undoStack.byteCount < 4_096,
                "one dot retained \(engine.undoStack.byteCount) bytes of history")
    }

    @Test("Building a display image from a large canvas is fast enough to be per-frame")
    func imageEncodeThroughput() {
        let bitmap = Bitmap(width: 2000, height: 1500)
        let elapsed = milliseconds {
            for _ in 0..<20 { _ = bitmap.makeCGImage() }
        }
        // 20 frames of a 12 MB canvas.
        #expect(elapsed < 900, "20 image builds took \(Int(elapsed))ms")
    }

    @Test("A small Core Graphics mark does not copy the whole canvas")
    func coreGraphicsDrawingDoesNotCopyTheCanvas() {
        // A single mark should cost what was drawn, not two extra copies of a
        // 96 MB canvas. Eight passes make the old full-raster copy path visible
        // while leaving ample headroom for context creation on a loaded runner.
        var bitmap = Bitmap(width: 6000, height: 4000)
        let elapsed = milliseconds {
            for offset in 0..<8 {
                bitmap.drawWithCoreGraphics { context in
                    context.setFillColor(PaintColour.black.cgColor)
                    context.fill(CGRect(x: offset, y: offset, width: 1, height: 1))
                }
            }
        }

        #expect(elapsed < 80, "eight tiny Core Graphics marks took \(Int(elapsed))ms")
    }
}
