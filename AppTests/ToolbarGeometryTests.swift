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

    /// The README quotes these, and they had rotted: it advertised a 48pt rail
    /// long after the tool cell shrank to 34, and twelve tools when there have
    /// been eleven. A number in prose cannot fail a build, so pin it to one
    /// that can.
    ///
    /// Pinning the token alone is only half the guard — the code and the prose
    /// can drift apart in either direction, and a test that restates the
    /// number in a comment still passes when only the README moves. So this
    /// reads the file. If a count changes, the assertion names the words to go
    /// and rewrite.
    @Test("The numbers the README quotes are still the numbers")
    func documentedGeometryMatchesTheTokens() throws {
        #expect(Tokens.Rail.toolColumns == 1)
        #expect(ToolKind.allCases.count == 11)
        #expect(ShapeKind.allCases.count == 15)

        let readme = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // AppTests/
            .deletingLastPathComponent()      // repository root
            .appendingPathComponent("README.md")
        // Whitespace-collapsed, so a phrase that happens to straddle a line wrap
        // still matches. Pinning the wrap as well as the words makes the test fail
        // on reflowing a paragraph, which teaches people to delete it.
        let prose = try String(contentsOf: readme, encoding: .utf8)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        // Every place the README spends one of these numbers as a word.
        // The exact words, because the point is to catch the *prose* moving. When
        // the page is rewritten these have to be updated deliberately, which is
        // the moment someone re-checks that the number is still right — and that
        // is the whole mechanism. This test failing during a rewrite is it
        // working, not it being in the way.
        for phrase in [
            "Eleven rail buttons",
            "**Fifteen shapes**",
            "fifteen shapes behind Shape",
        ] {
            #expect(prose.contains(phrase), "README no longer says \"\(phrase)\"")
        }
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
