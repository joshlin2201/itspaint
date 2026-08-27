import Testing
@testable import PaintKit

/// **A colour with no colour in it takes paint away.**
///
/// The bucket has meant that since the first build — `SelectionMask.fill` assigns
/// the colour straight into the pixels, so filling a region with a transparent
/// colour knocks a hole in it. Every other tool disagreed, and disagreed silently:
/// source-over compositing with a transparent source is `out = dst`, so the pencil,
/// the brush, the shapes, the text and the *eraser* all did precisely nothing and
/// said nothing about it.
///
/// The eraser is the one that mattered. It paints Colour 2, and a transparent
/// Colour 2 is exactly what somebody loads when they want a hole — so the app's
/// most obvious route to transparency was the one route that was dead.
@Suite("Painting with a transparent colour")
struct TransparentPaintTests {

    private func opaqueCanvas() -> Bitmap {
        Bitmap(width: 16, height: 16, fill: RGBA8(r: 255, g: 0, b: 0, a: 255))
    }

    @Test("A hard brush loaded with a transparent colour clears what it covers")
    func stampErases() {
        var canvas = opaqueCanvas()
        Raster.stamp(Brush(shape: .square, size: 4), colour: .clear, at: PixelPoint(x: 8, y: 8), into: &canvas)

        #expect(canvas.pixel(at: PixelPoint(x: 8, y: 8))! == .clear, "a transparent stamp left the pixel at \(canvas.pixel(at: PixelPoint(x: 8, y: 8))!)")
        // And only where it covered: an erase that runs to the edges is a bug
        // wearing the same result as a working one on a small canvas.
        #expect(canvas.pixel(at: PixelPoint(x: 0, y: 0))!.a == 255, "the stamp cleared a pixel it never touched")
    }

    /// The property that makes this worth doing rather than special-casing the
    /// eraser: a soft brush erases *softly*, because coverage does the scaling.
    @Test("A soft brush erases by the same coverage it would have painted by")
    func softStampFeathers() {
        var painted = opaqueCanvas()
        var erased = opaqueCanvas()
        let brush = Brush(shape: .soft, size: 9)
        let at = PixelPoint(x: 8, y: 8)

        Raster.stamp(brush, colour: RGBA8(r: 0, g: 0, b: 255, a: 255), at: at, into: &painted)
        Raster.stamp(brush, colour: .clear, at: at, into: &erased)

        // Wherever the brush laid down blue, it took away exactly that much red.
        for y in 4..<13 {
            for x in 4..<13 {
                let laid = Int(painted.pixel(at: PixelPoint(x: x, y: y))!.b)
                let left = Int(erased.pixel(at: PixelPoint(x: x, y: y))!.a)
                #expect(abs((255 - laid) - left) <= 1, "at \(x),\(y): laid \(laid), left \(left)")
            }
        }
    }

    @Test("A filled shape in a transparent colour cuts a hole rather than doing nothing")
    func blendErases() {
        var canvas = opaqueCanvas()
        canvas.blend(PixelRect(x: 2, y: 2, width: 4, height: 4), with: .clear)

        #expect(canvas.pixel(at: PixelPoint(x: 3, y: 3))! == .clear)
        #expect(canvas.pixel(at: PixelPoint(x: 10, y: 10))!.a == 255)
    }

    /// **A drag, not a click — and every freehand tool, not one.**
    ///
    /// The first version of this test pressed and released on the same pixel,
    /// which only ever reaches `PaintEngine.beginStroke`'s direct `Raster.stamp`.
    /// It passed with the entire antialiased stroke path still dead, and that path
    /// is the *shipping default*: a round brush with smooth edges. So a
    /// transparent colour rubbed out one dot under the press and then did nothing
    /// for the rest of the drag — which is worse than doing nothing at all,
    /// because the first dot proves the feature works.
    ///
    /// A test that cannot see the middle of a stroke cannot check a stroke.
    @Test(
        "Every freehand tool erases along a whole drag when its colour is transparent",
        arguments: [ToolKind.eraser, .brush, .pencil]
    )
    func freehandToolsEraseAlongADrag(tool: ToolKind) {
        let engine = PaintEngine(canvas: Bitmap(width: 64, height: 32, fill: RGBA8(r: 0, g: 0, b: 0, a: 255)))
        engine.settings.tool = tool
        engine.settings.brushSize = 6
        // The eraser paints Colour 2; everything else paints Colour 1.
        engine.colours.background = .clear
        engine.colours.foreground = .clear

        engine.beginStroke(at: PixelPoint(x: 8, y: 16))
        engine.continueStroke(to: PixelPoint(x: 32, y: 16))
        _ = engine.endStroke(at: PixelPoint(x: 56, y: 16))

        // The middle of the drag, which is the part a press-and-release cannot see.
        for x in [8, 32, 56] {
            let pixel = engine.canvas.pixel(at: PixelPoint(x: x, y: 16))!
            #expect(pixel.a == 0, "\(tool) left \(pixel) at x \(x)")
        }
    }

    /// The airbrush lays loose dots rather than a continuous band, so it has its
    /// own compositor and its own way of having been missed.
    @Test("A transparent airbrush takes paint out")
    func sprayErases() {
        let engine = PaintEngine(canvas: Bitmap(width: 48, height: 48, fill: RGBA8(r: 0, g: 0, b: 0, a: 255)))
        engine.settings.tool = .brush
        engine.settings.brushShape = .spray
        engine.settings.brushSize = 16
        engine.settings.sprayDensity = 0.6
        engine.colours.foreground = .clear

        engine.beginStroke(at: PixelPoint(x: 24, y: 24))
        engine.continueStroke(to: PixelPoint(x: 24, y: 24))
        _ = engine.endStroke(at: PixelPoint(x: 24, y: 24))

        let cleared = (0..<48).flatMap { y in (0..<48).map { engine.canvas.pixel(at: PixelPoint(x: $0, y: y))! } }
            .filter { $0.a == 0 }
        #expect(!cleared.isEmpty, "the airbrush cleared nothing")
    }

    /// Text set in a transparent colour cuts the letters out. Core Graphics cannot
    /// say that with a colour — source-over at zero alpha is a no-op — so it is
    /// said with a blend mode instead.
    @Test("Transparent text knocks a hole in the shape of the letters")
    func textErases() {
        var canvas = Bitmap(width: 200, height: 60, fill: RGBA8(r: 0, g: 0, b: 255, a: 255))
        TextRenderer.draw(
            "Hole",
            in: PixelRect(x: 4, y: 4, width: 192, height: 52),
            style: TextRenderer.Style(fontName: "Helvetica", pointSize: 36, colour: .clear),
            into: &canvas
        )

        let cleared = (0..<60).flatMap { y in (0..<200).map { canvas.pixel(at: PixelPoint(x: $0, y: y))! } }
            .filter { $0.a == 0 }
        #expect(cleared.count > 50, "only \(cleared.count) pixels went clear")
    }

    /// And the case that still has to behave exactly as it did: *partial* alpha is
    /// paint, not erasure. Nothing above may turn a 50% wash into a 50% hole.
    @Test("Partial alpha still composites, and still darkens what is under it")
    func partialAlphaStillPaints() {
        var canvas = Bitmap(width: 8, height: 8, fill: RGBA8(r: 255, g: 255, b: 255, a: 255))
        // Premultiplied: half-alpha black is (0, 0, 0, 128).
        canvas.blend(canvas.bounds, with: RGBA8(r: 0, g: 0, b: 0, a: 128))

        #expect(canvas.pixel(at: PixelPoint(x: 4, y: 4))!.a == 255, "compositing over opaque paint must stay opaque")
        #expect(canvas.pixel(at: PixelPoint(x: 4, y: 4))!.r < 200, "a half-alpha black wash did not darken the page")
    }
}
