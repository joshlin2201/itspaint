import Testing
@testable import PaintKit

// MARK: - Controls that cannot lie about the stroke

@Suite("Size ranges follow the armed tool")
struct ToolSizeRangeTests {

    /// `nib` clamps the highlighter to a 4px chisel, and for a long time nothing
    /// told the options panel that: the slider offered 1, the stop strip lit up 2,
    /// the readout said 2, and the stroke came out 4.
    @Test func highlighterRangeStartsAtItsChiselFloor() {
        #expect(ToolSettings.sizeRange(for: .highlighter).lowerBound == 4)
        #expect(ToolSettings.sizeRange(for: .brush).lowerBound == 1)
    }

    /// The bug in one assertion: every size a tool offers is the size it paints.
    @Test(arguments: ToolKind.allCases.filter(\.usesBrushSize))
    func everyOfferedSizePaintsAtThatSize(tool: ToolKind) {
        for size in ToolSettings.sizeRange(for: tool) {
            let settings = ToolSettings(tool: tool, brushSize: size)
            #expect(settings.nib.size == size, "\(tool) offers \(size)px and paints \(settings.nib.size)px")
        }
    }

    /// A stop strip with nothing lit reads as a disabled control, which is exactly
    /// what a 2px stop did for a tool whose floor is 4.
    @Test(arguments: ToolKind.allCases.filter(\.usesBrushSize))
    func everyStopIsReachable(tool: ToolKind) {
        let allowed = ToolSettings.sizeRange(for: tool)
        for stop in ToolSettings.sizeStops(for: tool) {
            #expect(allowed.contains(stop), "\(tool) shows an unreachable \(stop)px stop")
        }
    }

    @Test func stopsStayDistinctAndOrdered() {
        #expect(ToolSettings.sizeStops(for: .highlighter) == [4, 6, 14, 28])
        #expect(ToolSettings.sizeStops(for: .brush) == ToolSettings.sizeStops)
    }

    /// The slider must not travel past the point the sweep in `init` measured as
    /// flooding rather than matching.
    @Test func toleranceCeilingStaysBelowTheMeasuredCliff() {
        #expect(ToolSettings.usefulTolerance < 48)
        #expect(ToolSettings.usefulTolerance >= 32)
    }
}

@Suite("Badge numbering")
struct BadgeNumberingTests {

    /// A run of badges often spans two screenshots, and the second one starts at 4.
    @Test func aSequenceCanStartAnywhere() {
        let engine = PaintEngine(width: 40, height: 40)
        engine.setNextBadgeNumber(4)
        #expect(engine.nextBadgeNumber == 4)
    }

    @Test(arguments: [(0, 1), (-7, 1), (100, 99), (50, 50)])
    func outOfRangeStartsAreClamped(given: Int, expected: Int) {
        let engine = PaintEngine(width: 40, height: 40)
        engine.setNextBadgeNumber(given)
        #expect(engine.nextBadgeNumber == expected)
    }
}

@Suite("Smooth edges")
@MainActor
struct SmoothEdgeTests {

    private func line(smooth: Bool) -> Bitmap {
        let engine = PaintEngine(width: 60, height: 40)
        engine.colours.foreground = PaintColour(hex: "000000")!
        engine.settings.brushSize = 3
        engine.settings.smoothEdges = smooth
        engine.settings.tool = .shape
        engine.settings.shapeKind = .line
        _ = engine.beginStroke(at: PixelPoint(x: 4, y: 6))
        _ = engine.continueStroke(to: PixelPoint(x: 55, y: 33))
        _ = engine.endStroke(at: PixelPoint(x: 55, y: 33))
        return engine.canvas
    }

    /// Partial coverage over an opaque canvas shows up in the colour channels, not
    /// in alpha: black composited over white at 40% is mid grey with `a` still 255.
    /// An earlier version of this counted partial *alpha* and found none, which is
    /// true of a correct antialiased stroke and would have passed on a broken one.
    private func midTones(_ bitmap: Bitmap) -> Int {
        bitmap.pixels.filter { $0.r > 8 && $0.r < 247 }.count
    }

    /// The staircase in one assertion: an aliased diagonal is only ink or paper,
    /// so there is nothing in between to soften the step.
    @Test func aliasedDiagonalHasNoMidTones() {
        #expect(midTones(line(smooth: false)) == 0, "the hard path is supposed to be hard")
    }

    @Test func smoothDiagonalFillsTheStepsWithMidTones() {
        let found = midTones(line(smooth: true))
        #expect(found > 40, "only \(found) mid-tone pixels; the edge is still a staircase")
    }

    /// A stroke has to be a function of the segment, not of the direction it was
    /// walked, or scrubbing back and forth thickens it.
    @Test func smoothStrokeIsTheSameBothWays() {
        var forward = Bitmap(width: 40, height: 30, fill: RGBA8(r: 255, g: 255, b: 255))
        var backward = forward
        let a = PixelPoint(x: 3, y: 4), b = PixelPoint(x: 36, y: 25)
        Raster.strokeSegmentSmooth(from: a, to: b, width: 3, colour: .black, into: &forward)
        Raster.strokeSegmentSmooth(from: b, to: a, width: 3, colour: .black, into: &backward)
        #expect(forward.pixels == backward.pixels)
    }

    /// A stray click must not leave a stroke wider than the nib.
    @Test func aZeroLengthSegmentIsOneRoundCap() {
        var bmp = Bitmap(width: 20, height: 20, fill: RGBA8(r: 255, g: 255, b: 255))
        let p = PixelPoint(x: 10, y: 10)
        let dirty = Raster.strokeSegmentSmooth(from: p, to: p, width: 4, colour: .black, into: &bmp)
        #expect(!dirty.isEmpty)
        #expect(dirty.width <= 6 && dirty.height <= 6, "a dot spread to \(dirty.width)x\(dirty.height)")
    }

    @Test func smoothingStaysInsideTheCanvas() {
        var bmp = Bitmap(width: 12, height: 12, fill: RGBA8(r: 255, g: 255, b: 255))
        Raster.strokeSegmentSmooth(
            from: PixelPoint(x: -20, y: -20), to: PixelPoint(x: 30, y: 30),
            width: 6, colour: .black, into: &bmp)
        #expect(bmp.pixels.count == 144)
    }
}

/// The edge cases a smoothed freehand path has to survive. Short strokes are the
/// common case — a tap, a tick, a two-sample flick — and they are the ones a
/// smoother written for long drags gets wrong.
@Suite("Short and degenerate strokes")
@MainActor
struct ShortStrokeTests {

    private func engine() -> PaintEngine {
        let e = PaintEngine(width: 80, height: 80)
        e.reset(to: Bitmap(width: 80, height: 80, fill: RGBA8(r: 255, g: 255, b: 255)))
        e.colours.foreground = PaintColour(hex: "000000")!
        e.settings.tool = .brush
        e.settings.brushShape = .round
        e.settings.brushSize = 4
        return e
    }

    private func inked(_ e: PaintEngine) -> Int {
        e.canvas.pixels.filter { $0.r < 200 }.count
    }

    /// A click with no movement must still leave a mark. A path smoother that only
    /// draws between distinct samples leaves nothing at all.
    @Test func aClickWithNoMovementStillMarks() {
        let e = engine()
        let p = PixelPoint(x: 40, y: 40)
        _ = e.beginStroke(at: p)
        _ = e.endStroke(at: p)
        #expect(inked(e) > 0, "a click left no pixels")
    }

    @Test func repeatedIdenticalSamplesDoNotCrashOrSpread() {
        let e = engine()
        let p = PixelPoint(x: 40, y: 40)
        _ = e.beginStroke(at: p)
        for _ in 0..<20 { _ = e.continueStroke(to: p) }
        _ = e.endStroke(at: p)
        // A round 4px nib on one spot covers well under a 12x12 box.
        #expect(inked(e) < 144, "holding still spread the mark over \(inked(e)) pixels")
    }

    /// Two, three and four samples each take a different branch through the tail
    /// window, and all three have to reach the last point the hand visited.
    @Test(arguments: [2, 3, 4, 5])
    func aShortStrokeReachesItsFinalPoint(samples: Int) {
        let e = engine()
        let points = (0..<samples).map { PixelPoint(x: 10 + $0 * 12, y: 40) }
        _ = e.beginStroke(at: points[0])
        for p in points.dropFirst() { _ = e.continueStroke(to: p) }
        _ = e.endStroke(at: points.last!)

        let last = points.last!
        let nearEnd = e.canvas.pixels.enumerated().contains { index, pixel in
            let x = index % 80, y = index / 80
            return pixel.r < 200 && abs(x - last.x) <= 3 && abs(y - last.y) <= 3
        }
        #expect(nearEnd, "a \(samples)-sample stroke stopped short of its last point")
    }

    /// The stroke must be continuous: no gap left undrawn between the samples.
    @Test func aStrokeHasNoHoleAlongItsLength() {
        let e = engine()
        let points = (0..<8).map { PixelPoint(x: 8 + $0 * 8, y: 40) }
        _ = e.beginStroke(at: points[0])
        for p in points.dropFirst() { _ = e.continueStroke(to: p) }
        _ = e.endStroke(at: points.last!)

        // Every column between the first and last sample should carry some ink.
        var empty: [Int] = []
        for x in (points[0].x + 2)...(points.last!.x - 2) {
            let any = (0..<80).contains { y in e.canvas.pixels[y * 80 + x].r < 200 }
            if !any { empty.append(x) }
        }
        #expect(empty.isEmpty, "columns with no ink: \(empty)")
    }
}
