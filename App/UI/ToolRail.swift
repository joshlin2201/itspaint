import PaintKit
import SwiftUI

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
/// width and carries all fourteen columns, and the side rail has the window's
/// height and carries the leading seven. Both are two swatches across. The rest
/// is one click away in the colour popover.
struct ToolRail: View {
    @Bindable var model: EditorModel
    /// Columns of the palette this rail has room for. The side rail hands down
    /// what the window's height allows; the bottom bar always has all fourteen.
    var swatchPairs: Int = Tokens.Rail.swatchPairs
    /// Fires when a tool cell is clicked, so the options panel can point at it.
    var onSelect: (ToolKind) -> Void = { _ in }

    @Environment(TooltipController.self) private var tooltips

    private var isVertical: Bool { model.chromeEdge.isVertical }

    var body: some View {
        Group {
            if isVertical {
                VStack(alignment: .center, spacing: Tokens.Rail.sectionSpacing) {
                    toolGroups
                    separator
                    colourBlock
                    edgeToggle
                }
                .padding(Tokens.Rail.padding)
            } else {
                HStack(alignment: .center, spacing: Tokens.Rail.sectionSpacing) {
                    toolGroups
                    separator
                    colourBlock
                    edgeToggle
                }
                .padding(Tokens.Rail.padding)
            }
        }
        .fixedSize()
        .chromeSurface(cornerRadius: Tokens.Radius.rail)
        .animation(Tokens.Motion.micro, value: model.chromeEdge)
    }

    // MARK: - Tools

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
        .onHover { hovering in
            hovering
                ? tooltips.hover(
                    key: "edge",
                    title: "Move toolbar \(model.chromeEdge.toggled.displayName.lowercased())",
                    shortcut: "⌥⌘T"
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
        .onHover { hovering in
            isHovering = hovering
            hovering
                ? tooltips.hover(key: key, title: title, shortcut: shortcut)
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
    @State private var isPopoverPresented = false

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
            Button {
                model.swapColours()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10, weight: .medium))
                    .frame(
                        width: isVertical ? Tokens.Rail.run : Tokens.Size.colourSwap,
                        height: isVertical ? Tokens.Size.colourSwap : Tokens.Size.colourWell
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary.opacity(Tokens.Ink.muted))
            .onHover { hovering in
                hovering
                    ? tooltips.hover(key: "swap", title: "Swap colours", shortcut: "X")
                    : tooltips.endHover(key: "swap")
            }
            .accessibilityLabel("Swap the front and back colours")
        }
        .frame(width: isVertical ? Tokens.Rail.cross : nil, alignment: .center)
        .popover(isPresented: $isPopoverPresented, arrowEdge: isVertical ? .trailing : .top) {
            ColourPopover(model: model)
        }
        .onChange(of: model.isColourPopoverRequested) { _, requested in
            guard requested else { return }
            isPopoverPresented = true
            model.isColourPopoverRequested = false
        }
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
        RoundedRectangle(cornerRadius: Tokens.Radius.swatch, style: .continuous)
            .fill(Color(cgColor: colour.cgColor))
            .frame(width: Tokens.Size.colourWell, height: Tokens.Size.colourWell)
            .overlay {
                RoundedRectangle(cornerRadius: Tokens.Radius.swatch, style: .continuous)
                    .strokeBorder(.black.opacity(0.35), lineWidth: 0.5)
            }
            .overlay(alignment: .bottomTrailing) {
                Text(label)
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(colour.prefersDarkContrast ? .black.opacity(0.55) : .white.opacity(0.75))
                    .padding(1.5)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { model.presentSystemColourPicker(for: role) }
            .onTapGesture { model.applySwatch(colour, to: .foreground) }
            .contextMenu {
                Button("Set as Colour 1") { model.applySwatch(colour, to: .foreground) }
                Button("Set as Colour 2") { model.applySwatch(colour, to: .background) }
                Divider()
                Button("Other colour…") { model.presentSystemColourPicker(for: role) }
            }
            .onHover { hovering in
                hovering
                    ? tooltips.hover(
                        key: "colour\(label)",
                        // One separator, not two. These read left to right as
                        // "what it is, what it is set to, what you can do",
                        // which a dash and a middle dot in the same nine words
                        // actively worked against.
                        title: role == .foreground
                            ? "Colour 1 · \(colour.hexString) · double-click to change"
                            : "Colour 2 · \(colour.hexString) · click to use as Colour 1",
                        shortcut: nil
                    )
                    : tooltips.endHover(key: "colour\(label)")
            }
            .accessibilityElement()
            .accessibilityLabel(
                role == .foreground
                    ? "Colour 1, front, \(colour.hexString)"
                    : "Colour 2, back, \(colour.hexString)"
            )
            .accessibilityHint("Click to load as Colour 1. Double-click to choose another colour.")
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
/// Recent custom colours moved to the popover for the same reason: they arrive
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
        RoundedRectangle(cornerRadius: Tokens.Radius.swatch, style: .continuous)
            .fill(Color(cgColor: colour.cgColor))
            .frame(width: Tokens.Size.swatch, height: Tokens.Size.swatch)
            .overlay {
                RoundedRectangle(cornerRadius: Tokens.Radius.swatch, style: .continuous)
                    .strokeBorder(.black.opacity(0.28), lineWidth: 0.5)
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
            .onTapGesture { model.applySwatch(colour, to: .foreground) }
            .contextMenu {
                Button("Set as Colour 1") { model.applySwatch(colour, to: .foreground) }
                Button("Set as Colour 2") { model.applySwatch(colour, to: .background) }
            }
            .help("\(colour.hexString) · click for Colour 1, right-click for Colour 2")
            .accessibilityLabel("Swatch \(colour.hexString)")
    }
}

// MARK: - Drawn glyphs

/// Glyphs SF Symbols does not ship.
///
/// Exactly one so far. A tipped bucket with a drip is the icon everyone already
/// knows means "flood fill" — the droplet the system offers reads as the
/// eyedropper's cousin, which is the one tool it must not be confused with.
enum DrawnGlyph {
    case bucket

    @ViewBuilder
    func shape(in colour: Color) -> some View {
        switch self {
        case .bucket: BucketGlyph(colour: colour)
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
