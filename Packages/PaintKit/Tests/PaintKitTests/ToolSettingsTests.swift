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
