import SwiftUI

/// The surface grammar for **Direction C — Canvas-first**.
///
/// With nothing selected the artwork owns ~96% of the window. All chrome is a
/// single glass cluster at the bottom, an options pill that trails it, a title
/// chip, and a colour popover on demand. Nothing is permanently docked to an
/// edge, and nothing is ever placed on the artwork itself.
///
/// Three rules govern everything below.
///
/// **Colour is never invented.** Values resolve to system semantic colours or
/// to the material's own label colours, so the app tracks appearance, accent,
/// Increase Contrast and Reduce Transparency for free.
///
/// **Hierarchy comes from surface, space and type — not a stroke on every
/// element.** Inside the cluster, cells are tonal: the accent fills the
/// selected one and nothing else paints an edge.
///
/// **Elevation is the one thing this direction spends.** Exactly two levels:
/// the cluster and the popover sit at the same height, and nothing else lifts.
enum Tokens {

    // MARK: - Spacing

    /// One scale: 2 / 5 / 8 / 10 / 14 / 20.
    enum Space {
        /// Between tool cells — they read as one run, not separate buttons.
        static let hair: CGFloat = 2
        static let tight: CGFloat = 5
        /// Cluster inner padding, and the gap between cluster and pill.
        static let base: CGFloat = 8
        static let snug: CGFloat = 10
        static let comfortable: CGFloat = 14
        /// Window safe inset — nothing sits under the traffic lights.
        static let safeInset: CGFloat = 20
    }

    // MARK: - Control metrics

    enum Size {
        /// Inner element of a segmented control.
        static let segment: CGFloat = 21
        /// The options panel's label column.
        ///
        /// Fixed, so "Size", "Stroke", "Flow" and "Corner" all end at the same
        /// x and every control in the panel starts at the same x. This one
        /// number is the difference between a panel and a stack of unrelated
        /// rows that happen to share a background.
        static let optionLabel: CGFloat = 42
        /// `GeometryReader` offers only 10pt intrinsically, which is not enough
        /// travel for a size mark when the bottom panel measures its own row.
        static let horizontalMarkMinimum: CGFloat = 96
        /// An action button inside the options panel.
        static let pillAction: CGFloat = 26
        /// A tool cell in the rail.
        static let toolCell: CGFloat = 34
        /// One of the two loaded colours. Overlapped with its partner, the pair
        /// is 34.08pt across — fractionally wider than a tool cell, and so the
        /// widest thing in the rail. `Rail.cross` is measured from it.
        static let colourWell: CGFloat = 24
        static let colourSwap: CGFloat = 18
        /// Glyph inside a tool cell — optically sized, not mathematically.
        static let toolGlyph: CGFloat = 19
        /// The same pair restated at full size inside the popover.
        static let colourPairLarge: CGFloat = 28
        /// A swatch in the always-visible palette.
        static let swatch: CGFloat = 16
        /// Every capsule in the top header shares one optical height.
        static let headerControl: CGFloat = 32
        /// One square in the transparency grid behind the artwork.
        static let transparencyTile: CGFloat = 8
    }

    // MARK: - Radii

    /// Concentric by construction. A cell inside the cluster is
    /// `cluster − padding` = 17 − 6 = 11, so the gap around each corner stays
    /// visually constant instead of the inner shape looking pinched.
    enum Radius {
        static let rail: CGFloat = 16
        static let cell: CGFloat = 11
        /// The options panel: tighter than the rail, so it reads as attached to
        /// it rather than as a second window floating nearby.
        static let panel: CGFloat = 12
        /// The well a grid sits in, inside the popover.
        static let well: CGFloat = 10
        static let segmentTrack: CGFloat = 7
        static let segmentInner: CGFloat = 5
        static let chip: CGFloat = 8
        /// A small button living inside a chip: a header cell's hover fill, one
        /// action in the floating bar.
        static let control: CGFloat = 6
        static let swatch: CGFloat = 4
    }

    // MARK: - Ink and fill

    /// **The opacity scale.** Five steps for text, four for fills.
    ///
    /// Every label in this app is a system colour at some opacity, which is what
    /// lets one set of views track light, dark, accent and Increase Contrast. The
    /// risk in that is drift: two labels meant to read as equals end up at 0.82
    /// and 0.85, a hover lands on 0.10 in one control and 0.14 in the next, and
    /// nothing looks *wrong* anywhere while the whole surface reads as
    /// accidental. Naming the steps by the job they do is what stops that,
    /// because "the value beside a label" has one answer instead of a range.
    enum Ink {
        /// A document title, or a live value the eye should land on first.
        static let strong: Double = 0.92
        /// A control's own glyph or label — the default for anything pressable.
        static let regular: Double = 0.82
        /// A value or read-out beside a label.
        static let muted: Double = 0.6
        /// A hint, a caption, a unit.
        static let faint: Double = 0.42
        /// A control that cannot be used. Still legible, clearly not available.
        static let disabled: Double = 0.28
    }

    /// Tonal fills, in the same spirit: a track, the cell inside it, the answer
    /// to a pointer, and a hairline.
    enum Fill {
        /// The trough a segmented control or a grid sits in.
        static let track: Double = 0.12
        /// The faintest step: an unselected cell *inside* a track, or the well a
        /// grid sits in. Present, so an all-off toggle group still reads as
        /// three keys rather than three loose glyphs.
        ///
        /// One value for both because they are the same job — recessing
        /// something a little without drawing an edge — and they were 0.06,
        /// 0.07 and 0.08 in three different files before this.
        static let cell: Double = 0.07
        /// The pointer is over this.
        static let hover: Double = 0.12
        static let separator: Double = 0.14
    }

    // MARK: - Elevation

    /// The two-level elevation this direction spends its budget on.
    ///
    /// A 0.5pt luminous hairline plus one ambient shadow. The hairline is what
    /// separates the glass from artwork of any brightness; the shadow is what
    /// says "this floats above the picture" without a border.
    enum Elevation {
        static let hairline: CGFloat = 0.5
        static let hairlineOpacity: Double = 0.20
        static let shadowRadius: CGFloat = 18
        static let shadowY: CGFloat = 7
        static let shadowOpacity: Double = 0.45
    }

    // MARK: - Type

    /// Mapped to the macOS text styles so the app honours accessibility text
    /// sizing. Nothing informational goes below `.footnote` — the platform's
    /// equivalent of a 12px floor, in the system's own units.
    enum Text {
        static let pillLabel = Font.system(size: 11.5)
        static let pillValue = Font.system(size: 11.5).monospacedDigit()
        static let chip = Font.system(size: 12)
        static let readout = Font.system(size: 11).monospacedDigit()
        static let popoverTitle = Font.system(size: 12, weight: .medium)
        static let popoverHint = Font.system(size: 11)
    }

    // MARK: - Motion

    /// Motion explains a state change, never decorates. The pill's width
    /// animates on tool change because its *content* changes; nothing else
    /// moves.
    enum Motion {
        /// The options panel resizing as its content genuinely changes.
        static let pillResize = Animation.smooth(duration: 0.22, extraBounce: 0.05)
        static let micro = Animation.easeOut(duration: 0.12)
        /// A press answering under the pointer. Short enough to read as
        /// contact rather than animation.
        static let press = Animation.easeOut(duration: 0.07)
    }

    // MARK: - The rail

    enum Rail {
        /// **One cell across, whichever edge it is on.**
        ///
        /// The bottom bar is a single row of tools; the side rail is the same
        /// bar stood on its end, and it has to stay as *thin* as the bottom one
        /// is *short*. A multi-column side rail turns a toolbar into a panel —
        /// it is width taken away from the artwork, permanently, on the axis a
        /// picture usually needs most.
        static let run: CGFloat = Size.toolCell
        static let toolColumns = 1

        /// The palette is two swatches across a side rail and two swatches deep
        /// along the bottom bar: the same grid, transposed with the rail.
        static let swatchColumns = 2
        static let swatchGap: CGFloat = 2

        /// Columns of the classic grid a side rail carries.
        ///
        /// A thin rail spends its length on tools, and the full fourteen pairs
        /// would run past the bottom of the window on a laptop screen. The rest
        /// are one click away in the colour popover, and the pairs kept are the
        /// leading ones, so a swatch is where it always was.
        ///
        /// Six rather than seven since Clone joined the Draw run. A thirteenth
        /// tool cell put the rail 3pt over the height a 800pt window can give it,
        /// and the two answers were to take the space from the palette or to
        /// relax the test that measures it. The palette in the rail is already an
        /// explicitly truncated view of a full set that `⇧⌘C` opens; the height
        /// budget is a real constraint on a real screen. Loosening a geometry
        /// check so a new button fits is the move `docs/A_GUARD_TUNED_TO_ITS_TEST.md`
        /// exists to warn about.
        static let swatchPairs = 6

        /// Chrome hugs its controls: the old 90pt thickness read as a dock
        /// rather than a toolbar. What replaced it is `thickness` below, which
        /// is derived from `cross` — the widest control the rail carries.
        static let padding: CGFloat = 5
        static let sectionSpacing: CGFloat = Space.tight
        static let colourInset: CGFloat = Space.hair

        /// The widest thing the rail carries across its short axis. The loaded
        /// colour pair, overlapped, is fractionally wider than a tool cell —
        /// which is why the rail is 34.08pt and not 34. `ToolbarGeometryTests`
        /// pins that number, because the README quotes it and had gone on
        /// claiming 48pt long after the cell shrank.
        static let cross: CGFloat = max(
            run,
            Size.colourWell * 1.42,
            Size.swatch * CGFloat(swatchColumns) + swatchGap * CGFloat(swatchColumns - 1)
        )

        /// **One thickness, both orientations.**
        ///
        /// Not two constants that happen to agree: the side rail and the bottom
        /// bar carry the same controls across their short axis, so a single
        /// number is the only version of this that cannot drift apart when one
        /// of them gains a row.
        static let thickness: CGFloat = cross + colourInset * 2 + padding * 2

        /// The options panel beside it. Fixed, so the chrome never resizes with
        /// the window: a toolbar that grows with the frame is a toolbar you
        /// have to re-learn at every size.
        ///
        /// It is also what lets the panel's rows share a grid. A panel that
        /// sizes to its widest row cannot align anything, because every tool
        /// gives it a different width to align to.
        static let optionsWidth: CGFloat = 258
        /// Inside the panel's own padding.
        static let optionsContentWidth: CGFloat = optionsWidth - Space.snug * 2
    }

    // MARK: - Chrome geometry

    /// Fixed dimensions of the floating chrome, so a canvas fit can be derived
    /// from a window size without waiting for a layout pass.
    enum Chrome {
        /// The barely-perceptible gap between the artwork and the window edge.
        ///
        /// Deliberately tiny: the chrome floats over the canvas, so it reserves
        /// no space, and anything larger reads as a border the artwork is
        /// sitting inside rather than a window it fills.
        static let frameGap: CGFloat = 6

        /// Room the transparent titlebar scrim occupies, so the rail starts
        /// below the traffic lights rather than under them.
        static let titleReserve: CGFloat = 44

        /// Leading room reserved for the native macOS traffic lights.
        static let trafficLightClearance: CGFloat = 68

        /// How far the rail sits from the window edge. Matched to `frameGap`
        /// so the rail and the artwork share one margin instead of the rail
        /// sitting on a wider inset than everything around it.
        static let railInset: CGFloat = frameGap

        /// Space the rail actually takes away from the artwork. The same on
        /// either edge, because the rail is.
        static let railFootprint: CGFloat = Rail.thickness + railInset + Space.tight

        /// Canvas area available inside a window of `contentSize`.
        ///
        /// Canvas-first: the artwork runs to all four edges, so the chrome does
        /// not take space away from it. Only the fit calculation pretends the
        /// cluster is opaque, so a freshly opened image is not hidden under it.
        static func canvasArea(in contentSize: CGSize, rail edge: EditorModel.ChromeEdge) -> CGSize {
            // The rail is opaque and permanent, so it genuinely takes its
            // space; only the options panel floats.
            CGSize(
                width: max(0, contentSize.width - frameGap * 2 - (edge.isVertical ? railFootprint : 0)),
                height: max(0, contentSize.height - frameGap * 2 - (edge.isVertical ? 0 : railFootprint))
            )
        }
    }
}

/// The fill under a chosen segment.
///
/// **A flat `Color.accentColor` was the one default-looking thing left in the
/// panel.** Everything around it is a considered surface — a blurred material
/// under a tint floor, with a luminous hairline describing its edge — and then
/// the selection indicator was a plain brand-blue rectangle sitting on top,
/// which is what stock SwiftUI produces without being asked.
///
/// A gentle vertical fall gives it the same made quality as the surface it sits
/// on: brighter at the top where a light would catch it, and rimmed with a
/// brighter line of itself so it reads as raised rather than as painted on. It
/// stays unmistakably the accent colour, because that is its job.
struct SelectedSegmentFill: View {
    var cornerRadius: CGFloat = Tokens.Radius.segmentInner

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(1),
                        Color.accentColor.opacity(0.88),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                shape.strokeBorder(.white.opacity(0.22), lineWidth: Tokens.Elevation.hairline)
            }
    }
}

// MARK: - The chrome material

/// The one surface treatment shared by the cluster, the pill, the title chip
/// and the popover.
///
/// **The glass never relies on the artwork behind it.** A fixed tint floor sits
/// over the blur, so label contrast is constant whether the chrome straddles
/// white artwork, black artwork, or the boundary between them — the case that
/// breaks a pure vibrancy panel. The blur contributes only a hint of the colour
/// underneath.
///
/// Under Reduce Transparency the material becomes fully opaque rather than a
/// slightly-less-tinted version of itself: the fallback is a real surface, not
/// a weaker illusion of one.
struct ChromeSurface: ViewModifier {
    var cornerRadius: CGFloat
    var elevated: Bool = true

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        return content
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay { shape.fill(tintFloor) }
            }
            .overlay {
                // The luminous hairline. Brighter than a separator on purpose:
                // it is the only thing guaranteeing an edge against artwork of
                // unknown brightness.
                shape.strokeBorder(
                    hairlineColour,
                    lineWidth: Tokens.Elevation.hairline
                )
            }
            .clipShape(shape)
            .shadow(
                color: .black.opacity(elevated && !reduceTransparency ? Tokens.Elevation.shadowOpacity : 0),
                radius: Tokens.Elevation.shadowRadius,
                y: Tokens.Elevation.shadowY
            )
    }

    /// 62% of a near-black in dark appearance; the same rule inverted in light.
    private var tintFloor: Color {
        if reduceTransparency {
            return colorScheme == .dark
                ? Color(white: 0.12)
                : Color(white: 0.97)
        }
        return colorScheme == .dark
            ? Color(red: 0.118, green: 0.118, blue: 0.125).opacity(0.62)
            : Color.white.opacity(0.72)
    }

    private var hairlineColour: Color {
        colorScheme == .dark
            ? .white.opacity(Tokens.Elevation.hairlineOpacity)
            : .black.opacity(0.12)
    }
}

extension View {
    /// Apply the shared chrome material at a given corner radius.
    func chromeSurface(cornerRadius: CGFloat, elevated: Bool = true) -> some View {
        modifier(ChromeSurface(cornerRadius: cornerRadius, elevated: elevated))
    }
}
