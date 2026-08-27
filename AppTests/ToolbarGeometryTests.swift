import Foundation
import SwiftUI
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
    /// long after the tool cell shrank to 34, and thirteen tools when there have
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
        #expect(ToolKind.allCases.count == 13)
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
            "Thirteen rail buttons",
            "Fifteen shapes in all",
            "fifteen shapes behind Shape",
            "**Thirteen tools**",
        ] {
            #expect(prose.contains(phrase), "README no longer says \"\(phrase)\"")
        }
    }

    @Test("The rail fits the height of a small laptop window")
    func railFitsAShortWindow() {
        // The side rail runs the length of the window, so its content has to fit a
        // 13-inch display's usable height or the rail starts scrolling — and a
        // toolbar you scroll to reach a tool is a toolbar that hid it.
        //
        // Asked of the shipping arithmetic rather than of a copy of it. This test
        // used to re-derive the whole sum locally, which is `CHECKS_THAT_MISS.md`
        // §1: it could only ever agree with itself, and it would have gone on
        // passing while the rail on screen grew a row.
        let total = RailFit.tail(pairs: Tokens.Rail.swatchPairs, isVertical: true)
            + RailFit.toolRunLength

        // 800pt of window, less the titlebar reserve and the bottom safe inset.
        let usable: CGFloat = 800 - Tokens.Chrome.titleReserve - Tokens.Space.safeInset
        #expect(total <= usable, "the rail needs \(total)pt but only \(usable)pt is on offer")
    }

    /// **Neither edge may cut its own colour block — measured, not asserted.**
    ///
    /// `RailFit` decides what to shed from arithmetic, so checking `RailFit`
    /// against `Tokens` would be `docs/CHECKS_THAT_MISS.md` §1: it could only ever
    /// agree with itself, and it would go on passing while the rail on screen grew
    /// a row. That is exactly how this file's previous height check went wrong — it
    /// kept a private copy of the same sum.
    ///
    /// So this renders the real `ToolRail` at the smallest window the app can be
    /// dragged to and measures the picture. Both things it asserts had a real
    /// failure to catch: the bottom bar was handed all fourteen palette columns
    /// whatever the window was and ran off the right-hand end, and `RailFit`'s model
    /// of the tool run disagreed with the layout by 16pt because it charged a flat
    /// pitch for cells that are separated by a rule.
    ///
    /// `DrawingDocument` is an `NSDocument`, so reading its window floor means
    /// touching AppKit — and AppKit class realisation off the main thread takes the
    /// whole test process down rather than failing one check.
    @MainActor
    @Test("Both edges shed their palette rather than cutting the colours")
    func neitherEdgeClipsTheColourBlock() throws {
        let floor = DrawingDocument.minimumContentSize

        for edge in [EditorModel.ChromeEdge.left, .bottom] {
            let isVertical = edge.isVertical
            let length = isVertical
                ? floor.height - Tokens.Chrome.titleReserve - Tokens.Space.safeInset
                : floor.width - Tokens.Chrome.railInset * 2

            let pairs = RailFit.swatchPairs(fitting: length, isVertical: isVertical)
            let room = RailFit.toolRoom(in: length, pairs: pairs, isVertical: isVertical)

            let model = EditorModel(canvas: Bitmap(width: 400, height: 300, fill: .white))
            model.chromeEdge = edge
            let renderer = ImageRenderer(
                content: ToolRail(model: model, swatchPairs: pairs, toolsLength: room)
                    .environment(TooltipController())
            )
            renderer.scale = 1
            let drawn = try #require(renderer.nsImage, "the \(edge) rail did not render").size
            let along = isVertical ? drawn.height : drawn.width
            let across = isVertical ? drawn.width : drawn.height

            #expect(
                along <= length,
                "the \(edge) rail draws \(along)pt into the \(length)pt a smallest window offers"
            )
            // The tools may be shortened, never the colours: the rail has to still
            // be its declared thickness, which is the number the canvas inset and
            // the tooltip column are both computed from.
            #expect(
                abs(across - Tokens.Rail.thickness) <= 1,
                "the \(edge) rail is \(across)pt thick against a declared \(Tokens.Rail.thickness)pt"
            )
            #expect(
                (room ?? .infinity) >= Tokens.Size.toolCell,
                "the tool run is down to \(room ?? 0)pt on the \(edge) edge"
            )
        }
    }

    /// The fold in a shortened tool run lands **between** cells.
    ///
    /// `toolRoom` used to divide by an average pitch, which is right only while the
    /// fold stays inside one group: the groups are separated by a rule, so past the
    /// fifth cell the answer drifts and slices a glyph down the middle. A
    /// half-drawn button reads as a rendering fault, not as "there is more below".
    @Test("A shortened tool run is never cut through a glyph")
    func theFoldLandsBetweenCells() {
        let ends = Set(RailFit.toolCellEnds)
        for height in stride(from: 200.0, through: 900.0, by: 1) {
            let pairs = RailFit.swatchPairs(fitting: height, isVertical: true)
            guard let room = RailFit.toolRoom(in: height, pairs: pairs, isVertical: true) else { continue }
            #expect(
                ends.contains(room) || room == Tokens.Size.toolCell,
                "at \(height)pt the run is cut at \(room)pt, which is not a cell boundary"
            )
        }
    }
}
