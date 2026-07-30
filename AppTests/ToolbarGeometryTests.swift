import Foundation
import PaintKit
import Testing
@testable import ItsPaint

/// The toolbar's two formatting rules: **the palette is exactly two swatches
/// across the rail**, and **the rail is one cell thick on either edge**.
///
/// `Rail.thickness` is a constant the canvas inset is computed from *before*
/// any layout pass runs, so if the rendered palette ever grows a third row it
/// starts describing a bar smaller than the one on screen and the artwork
/// slides underneath it. That is exactly what used to happen the first time
/// anyone picked a custom colour.
///
/// These are arithmetic checks, not snapshot tests. They fail on the change
/// that would cause the drift — a wider run, a bigger swatch, a palette that
/// grew a row — rather than on a repaint.
@Suite("Toolbar geometry")
struct ToolbarGeometryTests {

    @Test("The palette is two rows at every rail width")
    func paletteIsAlwaysTwoRows() {
        let palette = Palette.standard
        #expect(palette.rows == 2)

        // Every width the rail can ask for, including the degenerate ends.
        for columns in 0...Palette.columns + 4 {
            let visible = palette.leadingColumns(columns)
            let expected = min(columns, Palette.columns) * 2
            #expect(visible.count == expected, "\(columns) columns produced \(visible.count) swatches")
        }
    }

    @Test("Truncating by column keeps the muted-over-saturated row pairing")
    func leadingColumnsKeepsRowPairing() {
        let palette = Palette.standard
        let six = palette.leadingColumns(6)

        // The failure this guards against is truncating in *reading* order,
        // which would return fourteen dark swatches and no white at all.
        #expect(six.first == palette.swatches.first)
        #expect(six[6] == palette.swatches[Palette.columns])
        #expect(six.contains(PaintColour(hex: "FFFFFF")!))
        #expect(six.contains(PaintColour(hex: "FF0000")!))

        // A swatch keeps its column index whatever the rail width.
        for width in 1...Palette.columns {
            let row = palette.leadingColumns(width)
            #expect(row[0] == palette.swatches[0])
            #expect(row[width] == palette.swatches[Palette.columns])
        }
    }

    @Test("The full palette still fits the widest grid")
    func fullWidthReturnsEverything() {
        let all = Palette.standard.leadingColumns(Palette.columns)
        #expect(all == Palette.standard.swatches)
    }

    @Test("A side rail carries the palette turned on its side")
    func columnPairsTransposeTheGrid() {
        let palette = Palette.standard
        let pairs = palette.leadingColumnPairs(Tokens.Rail.swatchPairs)

        #expect(pairs.count == Tokens.Rail.swatchPairs * 2)
        // Each consecutive pair is one column of the classic grid, so a muted
        // swatch always sits next to its saturated partner.
        for column in 0..<Tokens.Rail.swatchPairs {
            #expect(pairs[column * 2] == palette.swatches[column])
            #expect(pairs[column * 2 + 1] == palette.swatches[column + Palette.columns])
        }
    }

    @Test("Nothing in the rail is wider than the rail")
    func nothingExceedsTheCrossAxis() {
        let columns = CGFloat(Tokens.Rail.swatchColumns)
        let swatches = columns * Tokens.Size.swatch + (columns - 1) * Tokens.Rail.swatchGap

        #expect(swatches <= Tokens.Rail.cross, "the palette is wider than the rail it sits in")
        #expect(Tokens.Size.toolCell <= Tokens.Rail.cross)
        #expect(Tokens.Size.colourWell * 1.42 <= Tokens.Rail.cross)
    }

    @Test("One thickness serves both edges, and it stays thin")
    func railIsEquallyThinOnEitherEdge() {
        #expect(Tokens.Rail.thickness
            == Tokens.Rail.cross + Tokens.Rail.colourInset * 2 + Tokens.Rail.padding * 2)

        // A side rail is width taken from the artwork permanently. One tool
        // cell plus its padding is the budget; anything approaching a second
        // column of cells is a panel, not a toolbar.
        #expect(Tokens.Rail.thickness < Tokens.Size.toolCell * 2)
        #expect(Tokens.Rail.toolColumns == 1)
    }

    @Test("The rail fits the height of a small laptop window")
    func railFitsAShortWindow() {
        // The side rail runs the length of the window, so its content has to
        // fit a 13-inch display's usable height or the rail starts scrolling —
        // and a toolbar you scroll to reach a tool is a toolbar that hid it.
        let cell = Tokens.Size.toolCell + Tokens.Space.hair
        let tools = ToolKind.groups.reduce(CGFloat.zero) { $0 + CGFloat($1.count) * cell }
        let separators = CGFloat(ToolKind.groups.count) * (1 + Tokens.Rail.sectionSpacing * 2)
        let pair = Tokens.Size.colourWell * 1.42 + Tokens.Space.hair + Tokens.Size.colourSwap
        let swatches = CGFloat(Tokens.Rail.swatchPairs) * (Tokens.Size.swatch + Tokens.Rail.swatchGap)
        let colours = pair + Tokens.Space.tight + swatches + Tokens.Rail.colourInset * 2
        let toggle = Tokens.Rail.sectionSpacing + Tokens.Size.toolCell
        let total = Tokens.Rail.padding * 2 + tools + separators + colours + toggle

        // 800pt of window, less the titlebar reserve and the bottom safe inset.
        let usable: CGFloat = 800 - Tokens.Chrome.titleReserve - Tokens.Space.safeInset
        #expect(total <= usable, "the rail needs \(total)pt but only \(usable)pt is on offer")
    }
}

/// The size-stop row has to have something selected the moment it appears.
///
/// It is a segmented control, so "nothing selected" is indistinguishable from
/// "disabled" — and the stops shipped as 1 / 4 / 12 / 28 while the brush opens at
/// 2, so the very first thing a new user saw was four unselected bars. The two
/// numbers live in different targets, which is exactly why nothing caught it.
@Suite("Size stops")
struct SizeStopTests {

    @Test("The default brush size is one of the stops")
    func defaultSizeIsAStop() {
        let stops = ToolOptions.sizeStops
        let fresh = ToolSettings().brushSize
        #expect(
            stops.contains(fresh),
            "the brush opens at \(fresh), which is not one of \(stops), so the stop row opens with no segment selected"
        )
    }

    @Test("Every stop is reachable and they ascend")
    func stopsAreOrderedAndInRange() {
        let stops = ToolOptions.sizeStops
        #expect(stops == stops.sorted())
        #expect(Set(stops).count == stops.count)
        for stop in stops {
            #expect(ToolSettings.sizeRange.contains(stop), "\(stop) is outside the slider's range")
        }
    }
}
