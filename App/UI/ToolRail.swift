import PaintKit
import SwiftUI

/// **What a rail of a given length can carry, and what it gives up first.**
///
/// One ladder for both edges. The palette drops columns first, because every
/// swatch it drops is one press away in the system picker. Then, if the tool run
/// *still* does not fit, the tools alone scroll — while the loaded pair, the two
/// colour actions and the edge toggle keep their place. Nothing else is ever cut.
///
/// The bottom bar had none of this. It was handed all fourteen palette columns
/// whatever the window was and never bounded its tools, so at the 560pt window
/// floor the colour block simply ran off the right-hand end.
///
/// Plain arithmetic rather than methods on a `View`, for two reasons: the answer
/// feeds a layout pass that is already running, so it cannot wait for one — and
/// `View` is main-actor isolated, which took the whole test process down the first
/// time a geometry check asked it a question.
enum RailFit {

    /// A rule between two runs, with the stack's own spacing either side of it.
    private static var rule: CGFloat { 1 + Tokens.Rail.sectionSpacing * 2 }

    /// Everything in the rail that is not a tool cell, along the rail's own axis.
    ///
    /// Mirrors the layout term by term rather than approximating it. The first
    /// version counted **three** rules when only one is outside the tool run — the
    /// other two are between the tool groups, and so belong to `toolRunLength` —
    /// and it charged a trailing gap for a palette row that has none. The two
    /// errors pulled in opposite directions and left the ladder shedding about
    /// 6pt early, which is invisible until it is a whole tool.
    static func tail(pairs: Int, isVertical: Bool) -> CGFloat {
        let chips = Tokens.Size.colourWell * 1.42
        // Swap and More colours sit *under* the chips in a side rail and *beside*
        // them along a bottom bar, so they cost one cell of length on one edge and
        // two on the other.
        let actions = isVertical
            ? Tokens.Space.hair + Tokens.Size.colourSwap
            : Tokens.Space.tight + Tokens.Size.colourSwap * 2
        // No palette, no gap before it: the grid is not rendered at all at zero.
        let swatches = pairs > 0
            ? Tokens.Space.tight
                + CGFloat(pairs) * Tokens.Size.swatch
                + CGFloat(pairs - 1) * Tokens.Rail.swatchGap
            : 0
        let colourBlock = Tokens.Rail.colourInset * 2 + chips + actions + swatches
        let toggle = Tokens.Rail.sectionSpacing + Tokens.Size.toolCell
        return Tokens.Rail.padding * 2 + rule + colourBlock + toggle
    }

    /// Where each tool cell **ends** along the run.
    ///
    /// Walked rather than divided, because the pitch is not constant: cells inside
    /// a group are `hair` apart and the groups themselves are a `rule` apart. An
    /// average pitch is right until the fold crosses a group boundary, and then it
    /// is 9pt wrong — which is most of a glyph.
    static var toolCellEnds: [CGFloat] {
        var ends: [CGFloat] = []
        var offset: CGFloat = 0
        for (index, group) in ToolKind.groups.enumerated() {
            if index > 0 { offset += rule }
            for cell in 0..<group.count {
                if cell > 0 { offset += Tokens.Space.hair }
                offset += Tokens.Size.toolCell
                ends.append(offset)
            }
        }
        return ends
    }

    /// The whole tool run, laid out end to end.
    static var toolRunLength: CGFloat { toolCellEnds.last ?? 0 }

    /// How much room the tools get, or `nil` when they need no bound at all.
    ///
    /// Cut at a **real cell boundary**. A scroller cut to whatever happened to be
    /// left over slices the last glyph through the middle, and a half-drawn button
    /// reads as a rendering fault rather than as "there is more below" — which is
    /// the one thing the scroller is there to say.
    static func toolRoom(in length: CGFloat, pairs: Int, isVertical: Bool) -> CGFloat? {
        let room = length - tail(pairs: pairs, isVertical: isVertical)
        guard room < toolRunLength else { return nil }
        return toolCellEnds.last { $0 <= room } ?? Tokens.Size.toolCell
    }

    /// How many columns of the palette the rail can show in `length`.
    ///
    /// A side rail spends its length on tools and keeps the leading six columns;
    /// the bottom bar has a whole window width and can carry all fourteen.
    static func swatchPairs(fitting length: CGFloat, isVertical: Bool) -> Int {
        let most = isVertical ? Tokens.Rail.swatchPairs : Palette.columns
        let spare = length - tail(pairs: 0, isVertical: isVertical) - toolRunLength
        let step = Tokens.Size.swatch + Tokens.Rail.swatchGap
        return max(0, min(most, Int(spare / step)))
    }
}

/// The permanent chrome: every tool, both colours, the palette.
///
/// **Nothing here is hidden.** The classic app put its tools, its two loaded
/// colours and its swatches on screen at once, and that is the single reason
/// people who had never read a manual could use it. A popover you have to know
/// about is a worse control than a swatch you can already see.
///
/// **The rail is one cell thick, on either edge.** A side rail is width taken
/// away from the artwork permanently, on the axis a picture usually needs most,
/// so it has to stay as thin as the bottom bar is short — a single file of
/// buttons, not a panel. Everything in it is built to `Rail.cross`, so the
/// column has one edge rather than five.
///
/// The rail is vertical on the left by default — the layout every paint tool
/// has used since 1985 — and flips to a bottom bar on request. Both
/// orientations render the same pieces from the same code, transposed, so
/// neither can drift into being the second-class one.
///
/// The one place they differ is palette breadth: the bottom bar has the window's
/// width to spend and the side rail has its height, so a wide window carries all
/// fourteen columns along the bottom and a tall one carries the leading six down
/// the side. Both are two swatches across, and both give columns up before
/// anything else is cut — see `RailFit`. The rest is one press away in the system
/// colour panel, behind the More colours button that sits in the block itself.
struct ToolRail: View {
    @Bindable var model: EditorModel
    /// Columns of the palette this rail has room for, from `RailFit`. Both edges
    /// shed them: fourteen is the most a bottom bar carries and six the most a
    /// side rail does, and a small window gets fewer of either.
    var swatchPairs: Int = Tokens.Rail.swatchPairs
    /// Room the *tools* have along the rail, once the colour block and the edge
    /// toggle have taken theirs. `nil` when the window has room for all of it.
    ///
    /// **Only the tools scroll.** The whole rail used to sit in one scroll view,
    /// so a short window put the colour block and the edge toggle below the fold
    /// of an indicator-less scroller — gone, with nothing to say they were gone.
    /// This file has claimed since it was written that the loaded colours are the
    /// part that must never be cut; that was a comment, not a behaviour.
    var toolsLength: CGFloat?
    /// Fires when a tool cell is clicked, so the options panel can point at it.
    var onSelect: (ToolKind) -> Void = { _ in }

    @Environment(TooltipController.self) private var tooltips
    @State private var edgeFrame: CGRect = .zero

    private var isVertical: Bool { model.chromeEdge.isVertical }

    var body: some View {
        Group {
            if isVertical {
                VStack(alignment: .center, spacing: Tokens.Rail.sectionSpacing) {
                    scrollingTools
                    separator
                    colourBlock
                    edgeToggle
                }
                .padding(Tokens.Rail.padding)
            } else {
                HStack(alignment: .center, spacing: Tokens.Rail.sectionSpacing) {
                    scrollingTools
                    separator
                    colourBlock
                    edgeToggle
                }
                .padding(Tokens.Rail.padding)
            }
        }
        .fixedSize(horizontal: isVertical, vertical: !isVertical)
        .chromeSurface(cornerRadius: Tokens.Radius.rail)
        .animation(Tokens.Motion.micro, value: model.chromeEdge)
    }

    // MARK: - Tools

    /// The tool run, scrolling only when the window genuinely cannot hold it —
    /// and with a real scroller when it does, because a rail that is quietly
    /// shorter than its contents is a rail that has hidden a tool from you.
    @ViewBuilder
    private var scrollingTools: some View {
        if let toolsLength {
            // **No scroll-to-selection here, deliberately.** The obvious polish is
            // a `ScrollViewReader` bringing the armed tool into view, and it does
            // not work: the cells sit inside `FixedGrid`, a custom `Layout`, and
            // `scrollTo` cannot resolve an id through one — it landed on the right
            // cell once and one cell from the top every other time. A control that
            // works by luck is worse than one that does not exist, because the time
            // it fails is the time somebody is depending on it.
            //
            // What covers it instead: the options panel beside the rail is titled
            // with the tool you are holding, so the answer to "which one is armed"
            // is on screen either way. Worth revisiting if `FixedGrid` ever becomes
            // a plain stack.
            ScrollView(isVertical ? .vertical : .horizontal, showsIndicators: true) {
                toolGroups.fixedSize()
            }
                // **The cross axis is pinned, not left to the scroll view.**
                //
                // `Rail.thickness` is not decoration: the canvas inset and the
                // tooltip column are both computed from it before any layout pass
                // runs. With *Show scroll bars: Always* macOS uses legacy scrollers
                // that take real space, and a `fixedSize` rail would have taken
                // its width from them — quietly making the rail wider than the
                // number the rest of the app is working from. The scroller overlaps
                // the cells in that setting instead, which is the right trade for
                // a fallback that only appears on a window shorter than any laptop.
                .frame(
                    width: isVertical ? Tokens.Rail.cross : toolsLength,
                    height: isVertical ? toolsLength : Tokens.Rail.cross
                )
        } else {
            toolGroups
        }
    }

    /// Tool cells in their three runs, one abreast — a single file of buttons
    /// along the rail, whichever edge it is on.
    @ViewBuilder
    private var toolGroups: some View {
        let layout = isVertical
            ? AnyLayout(VStackLayout(spacing: Tokens.Rail.sectionSpacing))
            : AnyLayout(HStackLayout(spacing: Tokens.Rail.sectionSpacing))

        layout {
            ForEach(Array(ToolKind.groups.enumerated()), id: \.offset) { index, group in
                if index > 0 { separator }
                FixedGrid(
                    group,
                    columns: isVertical ? Tokens.Rail.toolColumns : group.count,
                    spacing: Tokens.Space.hair
                ) {
                    cell(for: $0)
                }
            }
        }
    }

    /// The glyph a cell shows, which for the step badge is not a constant.
    ///
    /// **The badge cell used to read `1` forever.** It is a counter — the panel
    /// beside it says "Drops 4 next" — and the rail was stating a different
    /// number than the tool was about to stamp. `1.circle.fill` was also the
    /// only *filled* glyph in a rail of outline strokes, so the least-used tool
    /// was the loudest thing in the column. Both problems have the same fix:
    /// draw the number it will actually drop, in the weight everything else
    /// uses.
    private func symbol(for kind: ToolKind) -> String {
        guard kind == .badge else { return kind.symbolName }
        // SF Symbols ships `N.circle` up to 50; past that, fall back rather
        // than render a blank cell.
        let next = model.nextBadgeNumber
        return (1...50).contains(next) ? "\(next).circle" : "number.circle"
    }

    private func cell(for kind: ToolKind) -> some View {
        ToolCell(
            symbol: symbol(for: kind),
            drawnGlyph: kind == .fill ? .bucket : nil,
            title: kind.displayName,
            detail: kind.tip,
            shortcut: String(kind.shortcut).uppercased(),
            key: kind.rawValue,
            isSelected: model.tool == kind,
            // The selected tool carries a chevron towards its options, so the
            // panel that appears reads as belonging to the button you pressed.
            // It points *back* while the panel is open: a disclosure that shows
            // the same direction in both states is decoration, and this one is
            // also the control that closes the panel again.
            hasOptions: model.tool == kind,
            isOptionsOpen: model.isOptionsExpanded,
            optionsEdge: model.chromeEdge
        ) {
            onSelect(kind)
        }
    }

    /// The two loaded colours and the palette they come from, in one well.
    ///
    /// Grouped because they are one idea: *these* are loaded, *those* are what
    /// you can load. Separated, the pair reads as a preview and the grid as
    /// decoration.
    ///
    /// The grid runs *along* the rail and is two swatches across it, so the
    /// block is the same thickness as a tool cell on either edge.
    @ViewBuilder
    private var colourBlock: some View {
        let layout = isVertical
            ? AnyLayout(VStackLayout(spacing: Tokens.Space.tight))
            : AnyLayout(HStackLayout(spacing: Tokens.Space.tight))

        layout {
            ColourControls(model: model, isVertical: isVertical)
            if swatchPairs > 0 {
                PaletteGrid(model: model, isVertical: isVertical, pairs: swatchPairs)
            }
        }
        .padding(Tokens.Rail.colourInset)
        .background {
            RoundedRectangle(cornerRadius: Tokens.Radius.well, style: .continuous)
                .fill(.primary.opacity(Tokens.Fill.cell))
        }
    }

    /// A hairline between runs. Sized to the run it divides rather than to the
    /// panel, so the rail reads as grouped rather than sliced.
    private var separator: some View {
        Rectangle()
            .fill(.primary.opacity(Tokens.Fill.track))
            .frame(
                width: isVertical ? Tokens.Rail.cross : 1,
                height: isVertical ? 1 : Tokens.Size.toolCell - Tokens.Space.base
            )
    }

    private var edgeToggle: some View {
        Button {
            model.chromeEdge = model.chromeEdge.toggled
        } label: {
            Image(systemName: model.chromeEdge.toggled.symbolName)
                .font(.system(size: 12, weight: .medium))
                .frame(width: Tokens.Size.toolCell, height: Tokens.Size.toolCell)
                .foregroundStyle(.primary.opacity(Tokens.Ink.muted))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .trackedForTooltip($edgeFrame)
        .onHover { hovering in
            hovering
                ? tooltips.hover(
                    key: "edge",
                    title: "Move toolbar \(model.chromeEdge.toggled.displayName.lowercased())",
                    shortcut: "⌥⌘T",
                    anchor: edgeFrame
                )
                : tooltips.endHover(key: "edge")
        }
        .accessibilityLabel("Move the toolbar to the \(model.chromeEdge.toggled.displayName.lowercased())")
    }
}

// MARK: - Cells

/// One cell in the rail.
///
/// A real `Button`, not a tappable stack: it inherits keyboard activation, the
/// focus ring and the accessibility role, which is exactly what hand-rolled
/// controls silently lose.
struct ToolCell: View {
    let symbol: String
    /// A glyph the system does not ship. `nil` uses `symbol`.
    var drawnGlyph: DrawnGlyph?
    let title: String
    /// One line under the title, for a tool whose first drag is not obvious.
    var detail: String?
    var shortcut: String?
    let key: String
    let isSelected: Bool
    var hasOptions: Bool = false
    var isOptionsOpen: Bool = false
    var optionsEdge: EditorModel.ChromeEdge = .left
    var isProminent: Bool = false
    let action: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false
    /// Where this cell is, so the one shared chip can sit beside *it* rather
    /// than beside the top of the rail.
    @State private var frame: CGRect = .zero
    @Environment(TooltipController.self) private var tooltips
    @Environment(\.colorSchemeContrast) private var contrast

    /// Towards the panel when it is closed, back towards the cell when it is
    /// open — so the notch is the state of the disclosure, not a decoration.
    private var chevron: String {
        switch (optionsEdge.isVertical, isOptionsOpen) {
        case (true, false): "chevron.right"
        case (true, true): "chevron.left"
        case (false, false): "chevron.down"
        case (false, true): "chevron.up"
        }
    }

    var body: some View {
        Button {
            tooltips.dismiss()
            action()
        } label: {
            glyph
                .frame(width: Tokens.Size.toolCell, height: Tokens.Size.toolCell)
                .foregroundStyle(isSelected || isProminent ? Color.white : Color.primary.opacity(Tokens.Ink.regular))
                .background {
                    RoundedRectangle(cornerRadius: Tokens.Radius.cell, style: .continuous)
                        .fill(fill)
                }
                .overlay {
                    // Increase Contrast outlines every cell, so selection is
                    // never carried by fill alone.
                    if contrast == .increased {
                        RoundedRectangle(cornerRadius: Tokens.Radius.cell, style: .continuous)
                            .strokeBorder(.primary.opacity(0.35), lineWidth: 1)
                    }
                }
                .overlay(alignment: optionsEdge.isVertical ? .trailing : .bottom) {
                    if hasOptions {
                        // A notch towards the panel: the options are this
                        // button's, expanded, not a separate control that
                        // happens to be nearby.
                        Image(systemName: chevron)
                            .font(.system(size: 7, weight: .black))
                            .foregroundStyle(.white.opacity(Tokens.Ink.regular))
                            .padding(optionsEdge.isVertical ? .trailing : .bottom, 1.5)
                            .animation(Tokens.Motion.micro, value: isOptionsOpen)
                    }
                }
                .scaleEffect(isPressed ? 0.90 : 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .trackedForTooltip($frame)
        .onHover { hovering in
            isHovering = hovering
            hovering
                ? tooltips.hover(
                    key: key, title: title, shortcut: shortcut,
                    detail: detail, anchor: frame
                )
                : tooltips.endHover(key: key)
        }
        // A pressed state the finger can feel. `.plain` gives none, and a
        // control that does not answer the press is the first thing that makes
        // an app feel cheap.
        .onLongPressGesture(minimumDuration: 0, pressing: { isPressed = $0 }, perform: {})
        .animation(Tokens.Motion.micro, value: isSelected)
        .animation(Tokens.Motion.micro, value: isHovering)
        .animation(Tokens.Motion.press, value: isPressed)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    @ViewBuilder
    private var glyph: some View {
        if let drawnGlyph {
            // Painted in the cell's own foreground, so it tracks selection the
            // way an SF Symbol would.
            drawnGlyph.shape(in: isSelected || isProminent ? Color.white : Color.primary.opacity(Tokens.Ink.regular))
                .frame(width: Tokens.Size.toolGlyph, height: Tokens.Size.toolGlyph)
        } else {
            Image(systemName: symbol)
                .font(.system(size: Tokens.Size.toolGlyph * 0.74, weight: .regular))
                .symbolVariant(isSelected ? .fill : .none)
        }
    }

    private var fill: AnyShapeStyle {
        if isSelected || isProminent { return AnyShapeStyle(Color.accentColor) }
        if isHovering { return AnyShapeStyle(Color.primary.opacity(Tokens.Fill.track)) }
        return AnyShapeStyle(Color.clear)
    }
}

// MARK: - Colours

/// Colour 1 and Colour 2, side by side and labelled — the control the classic
/// app kept in the corner of every screenshot ever taken of it.
///
/// Click either to load it from the system picker; the palette below sets the
/// front colour on a click and the back colour on a right-click, which is the
/// same mapping the canvas itself uses.
private struct ColourControls: View {
    @Bindable var model: EditorModel
    let isVertical: Bool

    @Environment(TooltipController.self) private var tooltips
    @Environment(\.colorScheme) private var colorScheme
    @State private var swapFrame: CGRect = .zero
    @State private var moreFrame: CGRect = .zero
    @State private var chipFrames: [EditorModel.ColourRole: CGRect] = [:]

    var body: some View {
        // Swap sits beside the pair along the bottom bar and beneath it in the
        // side rail: it follows the rail's long axis, so neither orientation
        // has to widen for it.
        let layout = isVertical
            ? AnyLayout(VStackLayout(spacing: Tokens.Space.hair))
            : AnyLayout(HStackLayout(spacing: Tokens.Space.tight))

        layout {
            // Overlapped, front over back — the arrangement the original used,
            // and the one that says "one is in front of the other" without a
            // word of explanation.
            ZStack(alignment: .topLeading) {
                chip(model.background, role: .background, label: "2")
                    .offset(x: Tokens.Size.colourWell * 0.42, y: Tokens.Size.colourWell * 0.42)
                chip(model.foreground, role: .foreground, label: "1")
            }
            .frame(
                width: Tokens.Size.colourWell * 1.42,
                height: Tokens.Size.colourWell * 1.42,
                alignment: .topLeading
            )
            colourActions
        }
        .frame(width: isVertical ? Tokens.Rail.cross : nil, alignment: .center)
    }

    /// Swap, and the way to every colour there is — two cells in the run the swap
    /// button used to hold alone.
    ///
    /// **The second cell is the door the app never had.** The full palette, custom
    /// colours and *opacity* were behind ⇧⌘C and a menu item three levels down, so
    /// the app's most interesting capability — a colour that is partly or entirely
    /// see-through, which a transparent one now erases with — was a thing you had
    /// to already know about. `PHILOSOPHY.md` has the sentence for this: a popover
    /// you have to know about is a worse control than a swatch you can already
    /// see. That argument does not end in "build a nicer popover"; it ends in a
    /// button in the permanent chrome. The panel it opens is Apple's, which has an
    /// opacity slider, an eyedropper, saved swatches and a recents row that
    /// survives quitting — all things a bespoke popover was a weaker copy of.
    ///
    /// Two cells of `Rail.cross / 2` rather than a second run, so `Rail.cross`
    /// does not move — and therefore neither do `Rail.thickness`,
    /// `ToolbarGeometryTests` or `RailFit.swatchPairs(fitting:)`. A second 18pt
    /// run would have cost exactly one palette column on a laptop-height window.
    @ViewBuilder
    private var colourActions: some View {
        let cellWidth = isVertical ? Tokens.Rail.cross / 2 : Tokens.Size.colourSwap
        let cellHeight = isVertical ? Tokens.Size.colourSwap : Tokens.Size.colourWell

        HStack(spacing: 0) {
            Button {
                model.swapColours()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: cellWidth, height: cellHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .trackedForTooltip($swapFrame)
            .onHover { hovering in
                hovering
                    ? tooltips.hover(
                        key: "swap", title: "Swap colours", shortcut: "X", anchor: swapFrame
                    )
                    : tooltips.endHover(key: "swap")
            }
            .accessibilityLabel("Swap the front and back colours")

            Button {
                model.presentSystemColourPicker(for: .foreground)
            } label: {
                DrawnGlyph.colourWell.shape(in: .primary.opacity(Tokens.Ink.muted))
                    .frame(width: 13, height: 13)
                    .frame(width: cellWidth, height: cellHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .trackedForTooltip($moreFrame)
            .onHover { hovering in
                hovering
                    ? tooltips.hover(
                        key: "morecolours",
                        title: "More colours",
                        shortcut: "⇧⌘C",
                        // The second clause is the whole reason this button
                        // exists. Transparency was reachable and unmentioned.
                        detail: "Any colour, at any opacity. A fully clear one rubs paint out.",
                        anchor: moreFrame
                    )
                    : tooltips.endHover(key: "morecolours")
            }
            .accessibilityLabel("More colours, including transparency")
        }
        .foregroundStyle(.primary.opacity(Tokens.Ink.muted))
    }

    private func chip(_ colour: PaintColour, role: EditorModel.ColourRole, label: String) -> some View {
        // **One click rule everywhere: left loads Colour 1, right loads Colour 2.**
        //
        // That is already how the palette and the canvas behave, and the two
        // loaded chips were the one place it did not hold — clicking the "2"
        // chip opened a picker for slot 2, so the same gesture meant "set the
        // front colour" over a swatch and "edit the back colour" two
        // millimetres above it.
        //
        // Left-clicking the back chip now promotes its colour to the front,
        // which is the common move: you had it a moment ago and you want it
        // again. Double-click still opens the system picker for that slot.
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.swatch, style: .continuous)

        return shape
            .fill(Color(cgColor: colour.cgColor))
            .frame(width: Tokens.Size.colourWell, height: Tokens.Size.colourWell)
            .background { TransparencyChecker(under: colour).clipShape(shape) }
            .overlay {
                shape.strokeBorder(.black.opacity(0.35), lineWidth: 0.5)
            }
            .overlay(alignment: .bottomTrailing) {
                Text(label)
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(prefersDarkInk(colour) ? .black.opacity(0.55) : .white.opacity(0.75))
                    .padding(1.5)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { model.presentSystemColourPicker(for: role) }
            .onTapGesture { model.applySwatch(colour, to: .foreground) }
            .contextMenu {
                Button("Set as Colour 1") { model.applySwatch(colour, to: .foreground) }
                Button("Set as Colour 2") { model.applySwatch(colour, to: .background) }
                Divider()
                // The one-click way to the thing the More colours button teaches.
                // Loaded as Colour 2 it also gives the eraser a real hole to rub,
                // which is the move people were reaching for when they found the
                // eraser doing nothing at all.
                Button("Transparent") { model.applySwatch(.clear, to: role) }
                Button("Other colour…") { model.presentSystemColourPicker(for: role) }
            }
            .trackedForTooltip(Binding(
                get: { chipFrames[role] ?? .zero },
                set: { chipFrames[role] = $0 }
            ))
            .onHover { hovering in
                hovering
                    // **The name goes in the title, everything else in the line
                    // under it.** All three clauses used to be one heading, which
                    // has no width cap — and once the opacity was added to it, a
                    // translucent colour produced a heading about 380pt wide.
                    // A title is a name; what the thing is set to and what you can
                    // do with it are a sentence, and the chip already has a place
                    // for a sentence.
                    ? tooltips.hover(
                        key: "colour\(label)",
                        title: role == .foreground
                            ? "Colour 1 · \(colour.hexString)"
                            : "Colour 2 · \(colour.hexString)",
                        shortcut: nil,
                        detail: chipDetail(colour, role: role),
                        anchor: chipFrames[role] ?? .zero
                    )
                    : tooltips.endHover(key: "colour\(label)")
            }
            .accessibilityElement()
            .accessibilityLabel(
                role == .foreground
                    ? "Colour 1, front, \(describe(colour))"
                    : "Colour 2, back, \(describe(colour))"
            )
            .accessibilityHint("Click to load as Colour 1. Double-click to choose another colour.")
    }

    /// What this chip is set to, and what pressing it will do.
    private func chipDetail(_ colour: PaintColour, role: EditorModel.ColourRole) -> String {
        let gesture = role == .foreground
            ? "Double-click for another colour"
            : "Click to use it as Colour 1"
        guard colour.alpha < 1 else { return gesture }
        let state = colour.alpha == 0
            ? "Fully transparent, so it rubs paint out"
            : "\(Int((colour.alpha * 100).rounded()))% opaque"
        return "\(state). \(gesture)"
    }

    /// A colour in words, with its opacity when it has one worth saying.
    ///
    /// `hexString` already appends the alpha byte, and `FF000080` is not "50%" to
    /// anybody. The checkerboard behind the chip says *that* it is see-through and
    /// roughly how much; this is where the exact number goes, at no cost in
    /// pixels, and it is what VoiceOver reads.
    private func describe(_ colour: PaintColour) -> String {
        guard colour.alpha < 1 else { return colour.hexString }
        guard colour.alpha > 0 else { return "transparent" }
        return "\(colour.hexString) · \(Int((colour.alpha * 100).rounded()))% opaque"
    }

    /// Which ink reads on this chip, allowing for what is *behind* it.
    ///
    /// `prefersDarkContrast` is computed from relative luminance and knows nothing
    /// about alpha, so a 10%-opacity black chip — visually almost entirely the
    /// checkerboard — asked for white text and vanished. Below half opacity the
    /// chip is mostly the system-coloured checkerboard, which is light in light
    /// appearance and dark in dark.
    private func prefersDarkInk(_ colour: PaintColour) -> Bool {
        colour.alpha < 0.5 ? colorScheme == .light : colour.prefersDarkContrast
    }
}

/// The same checkerboard the canvas draws under transparent pixels, at chip scale.
///
/// **Only under a colour that is actually see-through.** A checkerboard behind
/// every chip is a texture people learn to skip, and they skip it on the day it
/// matters. Its *arrival* is the signal that this colour is not solid, and how
/// strongly it shows through is the reading of how much alpha there is — a legend
/// nobody has to be given, which is the only kind this app allows.
///
/// The two colours are `CanvasNSView`'s, deliberately: a chip has to read as the
/// same kind of nothing the artwork does, and two greys for one meaning is exactly
/// the drift `Tokens.Ink` exists to stop.
struct TransparencyChecker: View {
    var tile: CGFloat = Tokens.Size.transparencyTileChip
    /// Draws nothing at all for an opaque colour.
    var opacity: Double = 1

    init(under colour: PaintColour, tile: CGFloat = Tokens.Size.transparencyTileChip) {
        self.tile = tile
        self.opacity = colour.alpha < 1 ? 1 : 0
    }

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(Color(nsColor: .controlBackgroundColor))
            )
            let dark = Color(nsColor: .separatorColor).opacity(0.22)
            for row in 0..<Int(ceil(size.height / tile)) {
                for column in 0..<Int(ceil(size.width / tile))
                where (row + column).isMultiple(of: 2) {
                    context.fill(
                        Path(CGRect(
                            x: CGFloat(column) * tile, y: CGFloat(row) * tile,
                            width: tile, height: tile
                        )),
                        with: .color(dark)
                    )
                }
            }
        }
        .opacity(opacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The palette, always exactly two rows.
///
/// Two rows is the whole formatting rule for this block. The grid used to take
/// as many rows as it needed — seven of them beside a narrow rail, and an extra
/// one the moment a custom colour was used — which made the rail as tall as the
/// window and left `Rail.horizontalThickness` describing a bar 18pt shorter
/// than the one actually on screen. Now the *columns* flex with the rail and
/// the row count never does, so the declared thickness is the real thickness.
///
/// Recent custom colours are the system panel's for the same reason: they arrive
/// unpredictably, and a toolbar that changes height while you work is a toolbar
/// that moves the button you were reaching for.
///
/// Click loads the front colour, right-click loads the back one — the same
/// button mapping as the canvas, so the palette teaches the canvas.
private struct PaletteGrid: View {
    @Bindable var model: EditorModel
    let isVertical: Bool
    let pairs: Int

    var body: some View {
        if isVertical {
            // Column-first, two across: each row is one classic column, so the
            // muted swatch and its saturated partner sit side by side instead
            // of fourteen rows apart.
            FixedGrid(
                model.palette.leadingColumnPairs(pairs),
                columns: Tokens.Rail.swatchColumns,
                spacing: Tokens.Rail.swatchGap
            ) { swatch($0) }
        } else {
            FixedGrid(
                model.palette.leadingColumns(pairs),
                columns: Palette.columns,
                spacing: Tokens.Rail.swatchGap
            ) { swatch($0) }
        }
    }

    private func swatch(_ colour: PaintColour) -> some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.swatch, style: .continuous)

        return shape
            .fill(Color(cgColor: colour.cgColor))
            .frame(width: Tokens.Size.swatch, height: Tokens.Size.swatch)
            // Same rule as the loaded pair, so the two grids cannot disagree
            // about what transparency looks like. The fixed 28 are all opaque
            // today; a document that arrives carrying a custom palette need not be.
            .background { TransparencyChecker(under: colour).clipShape(shape) }
            .overlay {
                shape.strokeBorder(.black.opacity(0.28), lineWidth: 0.5)
            }
            .overlay {
                // A ring on whichever swatches are loaded, so the palette says
                // where the current colours came from.
                if colour == model.foreground || colour == model.background {
                    // Inset by its own padding, so the ring stays concentric
                    // with the chip instead of looking pinched at the corners.
                    RoundedRectangle(cornerRadius: Tokens.Radius.swatch - 1.5, style: .continuous)
                        .strokeBorder(
                            colour.prefersDarkContrast ? .black.opacity(0.85) : .white.opacity(0.95),
                            lineWidth: 1.5
                        )
                        .padding(1.5)
                }
            }
            .contentShape(Rectangle())
            .overlay {
                MouseButtons(
                    tooltip: "\(colour.hexString) · click for Colour 1, right-click for Colour 2",
                    primary: { model.applySwatch(colour, to: .foreground) },
                    secondary: { model.applySwatch(colour, to: .background) }
                )
            }
            .accessibilityElement()
            .accessibilityLabel("Swatch \(colour.hexString)")
            .accessibilityValue(
                colour == model.foreground ? "Colour 1"
                    : colour == model.background ? "Colour 2" : ""
            )
            .accessibilityAddTraits(
                colour == model.foreground || colour == model.background ? [.isButton, .isSelected] : .isButton
            )
            // `MouseButtons` takes the click, so the tap gesture VoiceOver used to
            // activate is gone. Both slots need naming here, because a keyboard user
            // has no second mouse button to press.
            .accessibilityAction { model.applySwatch(colour, to: .foreground) }
            .accessibilityAction(named: "Set as Colour 2") { model.applySwatch(colour, to: .background) }
    }
}

/// A real right-click.
///
/// `.contextMenu` claims the secondary button and opens a menu with it, so every
/// swatch in the palette advertised "right-click for Colour 2" behind a gesture that
/// could only ever show a menu. The canvas has painted with Colour 2 on the right
/// button since the first build, which is precisely the muscle memory the help text
/// was appealing to, and the one place it did not hold was the control that taught it.
///
/// Both buttons run through here rather than leaving the left one on `onTapGesture`,
/// because an overlaid `NSView` takes the whole hit area or none of it, and a chip
/// where one button works is worse than one where neither does.
struct MouseButtons: NSViewRepresentable {
    let tooltip: String
    let primary: () -> Void
    let secondary: () -> Void

    final class Catcher: NSView {
        var primary: () -> Void = {}
        var secondary: () -> Void = {}
        override func mouseDown(with event: NSEvent) { primary() }
        override func rightMouseDown(with event: NSEvent) { secondary() }
        // The middle button, which no palette gesture is documented for. Sent to
        // Colour 2 because that is the only other thing a swatch does, and because
        // a button that silently does nothing is the failure this whole type exists
        // to fix. Control-click is not this method: macOS delivers that as
        // `rightMouseDown`, which is already handled above.
        override func otherMouseDown(with event: NSEvent) { secondary() }
    }

    func makeNSView(context: Context) -> Catcher { Catcher() }

    func updateNSView(_ view: Catcher, context: Context) {
        view.primary = primary
        view.secondary = secondary
        view.toolTip = tooltip
    }
}

// MARK: - Drawn glyphs

/// Glyphs SF Symbols does not ship.
///
/// A tipped bucket with a drip is the icon everyone already knows means "flood
/// fill" — the droplet the system offers reads as the eyedropper's cousin, which
/// is the one tool it must not be confused with.
///
/// The colour well is the same kind of gap. `paintpalette` and
/// `circle.hexagongrid.fill` both say "more colours" and neither says the second
/// half — that a colour here can be see-through, which is the half the rail has
/// never said anywhere. A chip sitting on a checkerboard says both in one mark,
/// and it is the mark every image editor already uses for alpha.
enum DrawnGlyph {
    case bucket
    case colourWell

    @ViewBuilder
    func shape(in colour: Color) -> some View {
        switch self {
        case .bucket: BucketGlyph(colour: colour)
        case .colourWell: ColourWellGlyph(colour: colour)
        }
    }
}

/// A swatch cut in half on the diagonal: solid on one side, nothing on the other.
///
/// **The mark macOS itself uses for alpha** — it is the well at the foot of the
/// system Colors panel, so anybody who has met a colour picker on this platform
/// has already been taught it. That matters more than inventing something here.
///
/// A checkerboard was the first attempt and it does not survive the size. Four
/// tiles across a 13pt glyph is 3.25pt a square, which resolves as grey mush and
/// says nothing at all; the diagonal reads down to about 10pt because it is one
/// edge rather than sixteen.
private struct ColourWellGlyph: View {
    let colour: Color

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let field = RoundedRectangle(cornerRadius: side * 0.24, style: .continuous)

            field
                .strokeBorder(colour.opacity(0.75), lineWidth: max(1, side * 0.09))
                .background {
                    // The solid half. Clipped by the same rounded shape, so the
                    // corner it fills is the swatch's corner and not a square one
                    // poking out of it.
                    Path { path in
                        path.move(to: .zero)
                        path.addLine(to: CGPoint(x: side, y: 0))
                        path.addLine(to: CGPoint(x: 0, y: side))
                        path.closeSubpath()
                    }
                    .fill(colour)
                    .clipShape(field)
                }
                .frame(width: side, height: side)
        }
    }
}

private struct BucketGlyph: View {
    let colour: Color

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let bucket = Path { path in
                // A tipped pail: wide mouth top-left, narrow base bottom-right.
                path.move(to: CGPoint(x: side * 0.10, y: side * 0.30))
                path.addLine(to: CGPoint(x: side * 0.62, y: side * 0.06))
                path.addLine(to: CGPoint(x: side * 0.88, y: side * 0.62))
                path.addLine(to: CGPoint(x: side * 0.46, y: side * 0.86))
                path.closeSubpath()
            }
            let drip = Path { path in
                path.move(to: CGPoint(x: side * 0.24, y: side * 0.62))
                path.addQuadCurve(
                    to: CGPoint(x: side * 0.10, y: side * 0.86),
                    control: CGPoint(x: side * 0.10, y: side * 0.68)
                )
                path.addQuadCurve(
                    to: CGPoint(x: side * 0.24, y: side * 0.62),
                    control: CGPoint(x: side * 0.24, y: side * 0.78)
                )
            }
            ZStack {
                bucket.fill(colour)
                // The rim, so the pail reads as open rather than as a slab.
                Path { path in
                    path.move(to: CGPoint(x: side * 0.10, y: side * 0.30))
                    path.addLine(to: CGPoint(x: side * 0.62, y: side * 0.06))
                }
                .stroke(colour, style: StrokeStyle(lineWidth: side * 0.10, lineCap: .round))
                drip.fill(colour)
            }
            .frame(width: side, height: side)
        }
    }
}
