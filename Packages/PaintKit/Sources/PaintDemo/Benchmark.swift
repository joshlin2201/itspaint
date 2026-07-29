import PaintKit
import Foundation

/// Prints real timings for the paths that run per input event.
///
/// The unit tests assert *budgets* so a regression fails the build; this prints
/// *numbers* so you can tell where the time actually goes before optimising.
/// Run with `swift run -c release paint-demo --bench`.
@MainActor
enum Benchmark {

    static func run() {
        print("ItsPaint — per-event path timings (2000×1500 canvas unless noted)\n")

        measure("brush stamp ×1000 (soft, 48px)") {
            var bitmap = Bitmap(width: 1200, height: 1200)
            let brush = Brush(shape: .soft, size: 48)
            for i in 0..<1000 {
                Raster.stamp(
                    brush, colour: .black,
                    at: PixelPoint(x: 60 + (i % 40) * 26, y: 60 + (i / 40) * 26),
                    into: &bitmap
                )
            }
        }

        measure("freehand stroke, 490 segments") {
            let engine = PaintEngine(canvas: Bitmap(width: 2000, height: 1500))
            engine.settings.tool = .brush
            engine.settings.brushSize = 24
            engine.settings.brushShape = .soft
            engine.beginStroke(at: PixelPoint(x: 20, y: 750))
            for x in stride(from: 20, through: 1980, by: 4) {
                engine.continueStroke(to: PixelPoint(x: x, y: 750 + Int(200 * sin(Double(x) / 90))))
            }
            engine.endStroke()
        }

        measure("shape preview, 120 frames") {
            let engine = PaintEngine(canvas: Bitmap(width: 2000, height: 1500))
            engine.settings.tool = .shape
            engine.settings.shapeKind = .ellipse
            engine.settings.brushSize = 3
            engine.beginStroke(at: PixelPoint(x: 100, y: 100))
            for i in 1...120 {
                engine.continueStroke(to: PixelPoint(x: 100 + i * 12, y: 100 + i * 9))
            }
            engine.endStroke()
        }

        measure("flood fill, 3M pixels") {
            var bitmap = Bitmap(width: 2000, height: 1500)
            Raster.floodFill(from: PixelPoint(x: 1000, y: 750), with: .black, into: &bitmap)
        }

        // The view rebuilds a display image whenever the canvas changes, so this
        // one runs at pointer-event rate. It is the number that decides whether
        // a large canvas feels immediate or syrupy.
        let bitmap = Bitmap(width: 2000, height: 1500)
        measure("makeCGImage ×60 (one second of frames)") {
            for _ in 0..<60 { _ = bitmap.makeCGImage() }
        }

        measure("extract 64×64 patch ×1000 (undo capture)") {
            for _ in 0..<1000 {
                _ = bitmap.extract(PixelRect(x: 500, y: 500, width: 64, height: 64))
            }
        }
    }

    private static func measure(_ label: String, _ body: () -> Void) {
        // One warm-up pass so allocation and first-touch page faults do not get
        // attributed to the work itself.
        body()
        let start = DispatchTime.now().uptimeNanoseconds
        body()
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        print(String(format: "  %-42s %8.2f ms", (label as NSString).utf8String!, ms))
    }
}
