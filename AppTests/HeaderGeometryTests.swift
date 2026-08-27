import PaintKit
import SwiftUI
import Testing
@testable import ItsPaint

/// **The header must fit the narrowest window this app will make.**
///
/// It did not. `DrawingDocument.minimumContentSize` is 560pt wide and the row
/// needed 647pt to draw itself with no filename in it at all, so the trailing
/// controls simply ran off the right edge — no truncation, no overflow, no way to
/// reach Share or Duplicate or the zoom. Two numbers that had never been compared.
///
/// `HeaderFit` decides what to shed from arithmetic over `Tokens.Header`, so
/// checking the ladder against those tokens would be `docs/CHECKS_THAT_MISS.md`
/// §1 — the constants and everything derived from them agreeing with each other
/// and with nothing on screen. This **renders the real row** and measures the
/// picture instead, then compares it against the width the *window* declares.
@Suite("Header geometry")
@MainActor
struct HeaderGeometryTests {

    /// The real controls, at a given rung, measured as drawn.
    private func drawnWidth(_ fit: HeaderFit) throws -> CGFloat {
        let model = EditorModel(canvas: Bitmap(width: 1000, height: 640, fill: .white))
        let row = HStack(spacing: Tokens.Space.comfortable) {
            WorkingActions(model: model, fit: fit)
            DocumentActions(model: model, fit: fit)
        }
        .fixedSize()
        .environment(TooltipController())

        let renderer = ImageRenderer(content: row)
        renderer.scale = 1
        return try #require(renderer.nsImage, "\(fit) did not render").size.width
    }

    @Test("Every rung draws into the width it claims to need")
    func rungsFitTheirOwnClaim() throws {
        for fit in HeaderFit.allCases where fit != .full {
            let drawn = try drawnWidth(fit)
            let budget = fit.minimumWindow
                - Tokens.Space.comfortable * 2          // the row's own padding
                - Tokens.Chrome.trafficLightClearance
                - Tokens.Space.comfortable * 3          // the gaps around title and spacer
                - Tokens.Space.base                     // Spacer(minLength:)
                - Tokens.Header.titleRoom
            // No slack. At the 560pt window floor the chosen rung leaves exactly
            // 141pt for a 140pt `titleRoom`, so a point of tolerance here is the
            // whole margin — a row that drew 1pt wide would pass this *and* eat it.
            #expect(
                drawn <= budget,
                "\(fit) draws \(drawn)pt of controls into the \(budget)pt it claims to need"
            )
        }
    }

    /// A ladder that is not monotonic is not a ladder: a window that *shrank*
    /// could pick a wider arrangement than the one it just had.
    @Test("The rungs get narrower, in the order they are declared")
    func theLadderDescends() {
        let rungs = HeaderFit.allCases.map(\.minimumWindow)
        #expect(rungs == rungs.sorted(by: >), "\(rungs) is not a ladder")
    }

    /// The assertion that failed before any of this existed.
    @Test("The last resort fits the smallest window the app can be dragged to")
    func theBottomOfTheLadderClearsTheWindowFloor() throws {
        let last = try #require(HeaderFit.allCases.last)
        #expect(
            last.minimumWindow <= DrawingDocument.minimumContentSize.width,
            "the header's last resort needs \(last.minimumWindow)pt and the window can be dragged to \(DrawingDocument.minimumContentSize.width)pt"
        )
    }

    /// The second failure in the same row, and the one the screenshot showed: the
    /// filename had a layout *priority* but no *ceiling*. Centred, the cluster is
    /// not in the title's stack at all, so a long name was handed the whole row
    /// and drawn over the zoom controls — the stack paints the title last.
    @Test("A long filename never reaches the centred cluster")
    func theTitleStopsShortOfTheCluster() {
        let width: CGFloat = 1600
        let ceiling = EditorView.titleCeiling(.full, in: width)
        // Where the cluster's own leading edge is, on a cluster centred on the
        // window rather than between its neighbours.
        let clusterLeading = width / 2 - HeaderFit.full.workingWidth / 2
        let titleLeading = Tokens.Space.comfortable * 2 + Tokens.Chrome.trafficLightClearance

        #expect(
            titleLeading + ceiling + Tokens.Space.base <= clusterLeading,
            "a full-width title reaches \(titleLeading + ceiling)pt and the cluster starts at \(clusterLeading)pt"
        )
    }
}
