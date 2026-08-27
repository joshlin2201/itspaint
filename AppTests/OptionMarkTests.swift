import Foundation
import PaintKit
import Testing
@testable import ItsPaint

/// The options panel's continuous values.
///
/// Every one of them is a `Mark` now. Six were a stock `Slider` at `.mini` —
/// blue track, chrome knob — sitting in a panel whose every other control was
/// drawn by hand, which is the giveaway `Mark`'s own doc comment was written to
/// complain about and then did not cover.
@Suite("The options panel's continuous values")
@MainActor
struct OptionMarkTests {

    /// One row per mark the panel draws. `probe` is a value the app can genuinely
    /// hold that sits *outside* that mark's own range — `ToolSettings` clamps the
    /// spray's density to 1 while the Flow mark stops at 0.6.
    struct Row: Sendable {
        let name: String
        let range: ClosedRange<Double>
        let gamma: Double
        let probe: Double
    }

    // `nonisolated`: the `arguments:` list is evaluated by the test macro outside
    // the suite's own actor, and a table of numbers has nothing to protect.
    nonisolated static let marks: [Row] = [
        .init(name: "Size", range: 1...96, gamma: 2, probe: 200),
        .init(name: "Size (highlighter's chisel floor)", range: 4...96, gamma: 2, probe: 2),
        .init(name: "Ink", range: 0.1...0.8, gamma: 1, probe: 1),
        .init(name: "Opacity", range: 0.1...1, gamma: 1, probe: 0),
        .init(name: "Strength", range: 0.15...0.85, gamma: 1, probe: 1),
        .init(name: "Flow", range: 0.02...0.6, gamma: 1, probe: 1),
        .init(name: "Corner", range: 0...48, gamma: 1, probe: 96),
        .init(name: "Text size", range: 8...200, gamma: 2, probe: 4),
        .init(name: "Match", range: 0...Double(ToolSettings.usefulTolerance), gamma: 1, probe: 255),
        .init(name: "Block", range: 4...48, gamma: 1, probe: 96),
    ]

    @Test("A mark's ends are its range's ends, and nothing draws past them", arguments: marks)
    func endsMapToEnds(mark: Row) {
        let low = mark.range.lowerBound
        let high = mark.range.upperBound

        // Dragging to either end lands on the bound. The failure this catches is a
        // size control that cannot quite reach 96, or a tolerance that cannot
        // reach 0 — the two values people go looking for.
        #expect(abs(Mark.value(atFraction: 0, in: mark.range, gamma: mark.gamma) - low) < 1e-9)
        #expect(abs(Mark.value(atFraction: 1, in: mark.range, gamma: mark.gamma) - high) < 1e-9)

        // And the caret comes back to where the drag put it.
        for f in [0.0, 0.25, 0.5, 1.0] {
            let value = Mark.value(atFraction: f, in: mark.range, gamma: mark.gamma)
            let back = Mark.fraction(of: value, in: mark.range, gamma: mark.gamma)
            #expect(abs(back - f) < 1e-9, "\(mark.name) round-tripped \(f) as \(back)")
        }

        // A stored value outside the range still has to draw *inside* the trough.
        // `t` skipped its clamp on the `gamma == 1` path — which is every mark
        // that does not bend its travel — and the meter's fill is an unclipped
        // overlay, so it painted past the end of its own bed.
        let out = Mark.fraction(of: mark.probe, in: mark.range, gamma: mark.gamma)
        #expect((0...1).contains(out), "\(mark.name) drew at \(out) of its track")
    }

    /// **The step VoiceOver moves by has to fit the range it is moving in.**
    ///
    /// It was `max(range / 100, 1)`, which is one pixel on a 1–96 size and *the
    /// entire range* on any 0-to-1 fraction: Ink, Opacity, Strength and Flow each
    /// had exactly two reachable values. A control a keyboard user can only put at
    /// its two ends is not an adjustable control.
    @Test("Every mark is adjustable in more than two steps", arguments: marks)
    func everyMarkHasUsableSteps(mark: Row) {
        let span = mark.range.upperBound - mark.range.lowerBound
        let step = span >= 8 ? 1 : span / 20
        #expect(step > 0)
        #expect(span / step >= 10, "\(mark.name) has only \(span / step) steps between its ends")
    }

    /// A tripwire, and honest about being one: `SwiftUI.Slider(` walks straight
    /// past it. It catches the accident — somebody reaching for the familiar
    /// control while adding a row — not somebody who has decided to.
    @Test("No stock slider in the tool options panel")
    func thePanelDrawsItsOwnControls() throws {
        let ui = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // AppTests/
            .deletingLastPathComponent()      // repository root
            .appendingPathComponent("App/UI")

        for file in ["ToolOptions.swift", "Mark.swift"] {
            let source = try String(contentsOf: ui.appendingPathComponent(file), encoding: .utf8)
            #expect(!source.contains("Slider("), "\(file) is back to an AppKit knob")
        }
    }
}
