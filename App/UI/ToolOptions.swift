import PaintKit
import SwiftUI

/// The active tool's own controls, expanded from its button in the rail.
///
/// This is the classic ribbon's trick and it is the right one: the rail stays a
/// short list of *jobs*, and the variations — fifteen shapes, four brush tips,
/// outline versus fill — appear only for the job you picked. Nothing is behind
/// a menu, but nothing irrelevant is on screen either.
///
/// The panel lays itself out along the rail: a column beside a left rail, a row
/// above a bottom bar, from the same content.
struct ToolOptions: View {
    @Bindable var model: EditorModel

    private var isVertical: Bool { model.chromeEdge.isVertical }

    /// **One column width, one label width, one control width.**
    ///
    /// The panel used to be a `VStack` of rows that each sized themselves, so
    /// the slider row, the segmented rows and the shape gallery all ended at
    /// different places and the panel took its width from whichever was
    /// widest. Nothing lined up with anything, and a control's size carried no
    /// meaning — "Round / Square / Soft" was three times the width of the fill
    /// picker directly under it purely because those words are longer.
    ///
    /// Now the vertical panel is a fixed width, every label occupies the same
    /// column, and every control fills what is left. Along the bottom bar the
    /// same content lays out as a row, where a fixed width would be wrong.
    var body: some View {
        let layout = isVertical
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 3))
            : AnyLayout(HStackLayout(spacing: Tokens.Space.snug))

        layout {
            header
            controls
            // Not while something is floating: the action bar over the canvas is
            // the primary affordance then, and showing Crop in both places at
            // once is two answers to one question.
            if model.hasSelection && !model.hasFloatingContent {
                // **A rule, because these are two different subjects.** Above it
                // is what the tool in your hand will do; below it is what can be
                // done to the region already selected. They arrive together,
                // they are unrelated, and run into each other they read as one
                // list — which is how the panel came to show two rows labelled
                // "Size", one the badge's and one the marquee's, with different
                // units under each and nothing to say why.
                OptionsDivider(isVertical: isVertical)
                selectionActions
            }
        }
        .environment(\.optionsAxisIsVertical, isVertical)
        .font(Tokens.Text.pillLabel)
        .lineLimit(1)
        // The fixed width exists to align controls with each other. A tool with
        // no controls has nothing to align, and holding the full width for it
        // just parks 258pt of empty glass over the artwork.
        .frame(
            width: isVertical && hasAlignedControls ? Tokens.Rail.optionsContentWidth : nil,
            alignment: .leading
        )
        .fixedSize(horizontal: !(isVertical && hasAlignedControls), vertical: false)
        .padding(.horizontal, Tokens.Space.snug)
        .padding(.vertical, Tokens.Space.base - 1)
        .chromeSurface(cornerRadius: Tokens.Radius.panel)
        .animation(Tokens.Motion.pillResize, value: model.tool)
        // The Flow row appears and disappears with the tip, so the panel
        // has to resize for that too, not only for a change of tool.
        .animation(Tokens.Motion.pillResize, value: model.brushShape)
        .animation(Tokens.Motion.pillResize, value: model.hasSelection)
    }

    // MARK: - Header

    /// The tool's name, with its gesture hint on its own line.
    ///
    /// The hint used to sit beside the name, which made the header the widest
    /// row in the panel — the Shape tool's polygon hint alone is 44 characters,
    /// and every other control was then laid out inside a panel sized for a
    /// sentence.
    private var header: some View {
        Group {
            if isVertical {
                VStack(alignment: .leading, spacing: 1) {
                    title
                    if let hint {
                        // One line, not two. The panel's height should be a
                        // function of its controls, not of how long a sentence
                        // about the tool happens to be.
                        Text(hint)
                            .font(.system(size: 10))
                            .foregroundStyle(.primary.opacity(Tokens.Ink.faint))
                            .lineLimit(1)
                    }
                }
                .padding(.bottom, 2)
            } else {
                HStack(spacing: Tokens.Space.tight) {
                    title
                    if let hint {
                        Text(hint)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.primary.opacity(Tokens.Ink.faint))
                    }
                }
            }
        }
    }

    private var title: some View {
        Text(model.tool.displayName)
            .font(.system(size: 11.5, weight: .semibold))
    }

    /// Whether this tool contributes any rows to the label/control grid.
    ///
    /// Kept beside `controls` deliberately: a tool that gains its first control
    /// has to be removed from here in the same edit, and the two being adjacent
    /// is the only thing that makes that likely.
    private var hasAlignedControls: Bool {
        switch model.tool {
        case .pencil, .eyedropper: false
        default: true
        }
    }

    /// The one thing about this tool a pointer will not tell you.
    ///
    /// **A keystroke, a second stage, or nothing.** These used to be little
    /// lists: "Drag its edge to move · corners resize · ⌘↩ places it" is three
    /// clauses in three different grammars, it wrapped onto a second line, and it
    /// made the Text panel a different height from every other panel. Two of its
    /// three clauses also described something the handles and their cursors
    /// already say — permanent instructions for what you learn on first contact.
    ///
    /// So the rule is: hint what is *invisible*. A modifier key and a two-stage
    /// gesture are invisible. Dragging a handle is not.
    private var hint: String? {
        switch model.tool {
        case .pencil: "1 px, fixed"
        case .text: "⌘↩ places it"
        case .eyedropper: "⌥ from any tool"
        case .select where model.selectionKind == .lasso: "Closes itself"
        case .select where model.selectionKind == .instantAlpha: "⇧ add · ⌥ subtract"
        case .select: "⌘A selects all"
        case .clone where model.cloneMode == .clone && !model.hasCloneSource:
            "Click to set the source"
        case .shape where model.shapeKind == .curve:
            model.hasPendingShape ? "Now drag to bend it" : "Drag, then bend it"
        case .shape where model.shapeKind == .polygon:
            model.hasPendingShape ? "↩ to finish" : "Click each corner"
        default: nil
        }
    }

    // MARK: - Per-tool controls

    @ViewBuilder
    private var controls: some View {
        switch model.tool {
        case .pencil:
            EmptyView()

        case .brush:
            widthMark(name: "Size")
            // Four tips, including the one that used to be its own rail button.
            // Icons rather than words: "Round / Square / Soft / Spray" is four
            // labels in a 238pt row, which is where truncation starts, and the
            // footprints are more legible than their names anyway.
            OptionRow("Tip") {
                OptionSegment(selection: $model.brushShape, options: [
                    .init(value: .round, symbol: "circle.fill", help: "Round"),
                    .init(value: .square, symbol: "square.fill", help: "Square"),
                    .init(value: .soft, symbol: "circle.dotted.circle", help: "Soft"),
                    .init(value: .spray, symbol: "sprinkler.and.droplets.fill", help: "Spray"),
                ])
            }
            // Flow only means something while spraying, so it appears with the
            // tip that has it rather than sitting greyed out under three that
            // do not.
            if model.brushShape.isSpray {
                OptionRow("Flow") {
                    OptionSlider(
                        value: $model.sprayDensity,
                        range: 0.02...0.6,
                        readout: "\(Int(model.sprayDensity * 100))%"
                    )
                }
            }

        case .highlighter:
            // Three clusters, three looks. Cover the title and the yellow wash still
            // says highlighter.
            widthMark(name: "Size")
            HighlighterInks(model: model)
            Mark(
                value: $model.highlighterOpacity,
                range: 0.1...0.8,
                style: .wash(ink: Color(cgColor: (model.highlighterColour ?? model.foreground).cgColor)),
                name: "Ink",
                readout: "\(Int(model.highlighterOpacity * 100))%",
                normal: 0.38
            )

        case .eraser:
            widthMark(name: "Size")

        case .clone:
            OptionSegment(selection: $model.cloneMode, options: CloneMode.allCases.map {
                .init(value: $0, symbol: $0.symbolName, help: $0.displayName)
            })
            widthMark(name: "Size")
            if model.cloneMode == .clone {
                Mark(
                    value: $model.cloneOpacity, range: 0.1...1, style: .meter, name: "Opacity",
                    readout: "\(Int((model.cloneOpacity * 100).rounded()))%", normal: 1
                )
            } else {
                Mark(
                    value: $model.softenStrength, range: 0.15...0.85, style: .meter, name: "Strength",
                    readout: "\(Int((model.softenStrength * 100).rounded()))%", normal: 0.4
                )
            }
            OptionSegment(selection: $model.cloneSoftTip, options: [
                .init(value: true, symbol: "circle.dashed.inset.filled", help: "Soft edge"),
                .init(value: false, symbol: "circle.fill", help: "Hard edge"),
            ])

        case .shape:
            ShapeGallery(model: model, columns: isVertical ? 5 : 8)
            // Stroke stays. A filled shape draws no outline, but `PaintEngine` still
            // insets the fill by `brush.size` (`fillRect(rect.insetBy(brush.size))`
            // and the same for ellipse, rounded rect and callout), so the weight is
            // the difference between a box and a smaller box. Only the dash is
            // genuinely dead, and only that row goes.
            widthMark(name: "Stroke")
            let strokes = model.shapeStyle.drawsOutline || !model.shapeKind.isClosed
            if model.shapeKind.isClosed {
                OptionRow("Fill") {
                    OptionSegment(selection: $model.shapeStyle, options: [
                        .init(value: .outline, symbol: "square", help: "Outline"),
                        .init(value: .filled, symbol: "square.fill", help: "Fill"),
                        .init(value: .outlineAndFill, symbol: "square.inset.filled", help: "Outline and fill"),
                    ])
                }
            }
            if strokes {
                OptionRow("Line") {
                    OptionSegment(selection: $model.strokeDash, options: Raster.Dash.allCases.map {
                        .init(value: $0, symbol: $0.symbolName, help: $0.displayName)
                    })
                }
            }
            if strokes {
                OptionRow("Edges") {
                    OptionSegment(selection: $model.smoothEdges, options: [
                        .init(value: true, symbol: "scribble", help: "Smooth"),
                        .init(value: false, symbol: "squareshape.split.2x2", help: "Hard pixels"),
                    ])
                }
            }
            if model.shapeKind == .roundedRectangle || model.shapeKind == .callout {
                OptionRow("Corner") {
                    OptionSlider(
                        value: Binding(
                            get: { Double(model.cornerRadius) },
                            set: { model.cornerRadius = Int($0.rounded()) }
                        ),
                        range: 0...48,
                        readout: "\(model.cornerRadius)"
                    )
                }
            }

        case .text:
            OptionRow("Size") {
                OptionSlider(
                    value: $model.textSize,
                    range: 8...200,
                    readout: "\(Int(model.textSize))",
                    gamma: 2
                )
            }
            OptionRow("Font") {
                OptionMenu(
                    selection: $model.textFont,
                    options: Self.fonts,
                    title: { $0 },
                    previewsItself: true
                )
            }
            OptionRow("Style") {
                SegmentTrack {
                    OptionToggle(symbol: "bold", help: "Bold (⌘B)", isOn: $model.isTextBold)
                    OptionToggle(symbol: "italic", help: "Italic (⌘I)", isOn: $model.isTextItalic)
                    OptionToggle(
                        symbol: "underline", help: "Underline (⌘U)",
                        isOn: $model.isTextUnderlined
                    )
                }
            }
            OptionRow("Align") {
                OptionSegment(selection: $model.textAlignment, options: [
                    .init(value: .left, symbol: "text.alignleft", help: "Align left"),
                    .init(value: .centre, symbol: "text.aligncenter", help: "Align centre"),
                    .init(value: .right, symbol: "text.alignright", help: "Align right"),
                ])
            }

        case .badge:
            // The number is the working object, so it goes first and it goes large.
            // Size recedes underneath. "Drops 1 next" is gone because the 22pt
            // numeral is that sentence.
            BadgeNumber(model: model)
            widthMark(name: "Size")

        case .fill:
            OptionRow("Match") {
                OptionSlider(
                    value: Binding(
                        get: { Double(model.fillTolerance) },
                        set: { model.fillTolerance = Int($0.rounded()) }
                    ),
                    range: 0...Double(ToolSettings.usefulTolerance),
                    readout: "\(model.fillTolerance)"
                )
            }

        case .spotlight:
            // One property, so the panel is that property: a plate whose darkness is
            // the value, dragged anywhere across it. A trough with a caret and the
            // word "Dim" would describe the setting; this one shows it.
            SpotlightDimPlate(dim: $model.spotlightDim)

        case .pixelate:
            OptionRow("Block") {
                OptionSlider(
                    value: Binding(
                        get: { Double(model.pixelateBlockSize) },
                        set: { model.pixelateBlockSize = Int($0.rounded()) }
                    ),
                    range: 4...48,
                    readout: "\(model.pixelateBlockSize)"
                )
            }

        case .select:
            OptionRow("Mode") {
                OptionSegment(selection: $model.selectionKind, options: SelectionKind.allCases.map {
                    .init(value: $0, symbol: $0.symbolName, help: $0.displayName)
                })
            }
            if model.selectionKind == .instantAlpha {
                OptionRow("Match") {
                    OptionSlider(
                        value: Binding(
                            get: { Double(model.selectionTolerance) },
                            set: { model.selectionTolerance = Int($0.rounded()) }
                        ),
                        range: 0...Double(ToolSettings.usefulTolerance),
                        readout: "\(model.selectionTolerance)"
                    )
                }
            }

        case .eyedropper:
            EmptyView()
        }
    }

    /// Faces that ship with every macOS install, so a document opened on
    /// another Mac renders the same text.
    private static let fonts = TextRenderer.Style.availableFonts

    // MARK: - Size

    // MARK: - Size

    /// Size as one object: a wedge that thickens to the right, with the stops as ticks
    /// on it.
    ///
    /// Replaces a 42pt right-aligned label, a stock `Slider` at `.mini`, a trailing
    /// number and a second row of capsules — four pieces all saying "size", in a panel
    /// where that pattern then repeated for every other property until the whole thing
    /// read as one grey surface.
    ///
    /// The range and the ticks are asked of the armed tool, so the highlighter's 4px
    /// chisel floor cannot be offered a 2 it will not draw.
    private func widthMark(name: String) -> some View {
        let allowed = ToolSettings.sizeRange(for: model.tool)
        return Mark(
            value: Binding(
                get: { Double(model.brushSize) },
                set: { model.brushSize = Int($0.rounded()) }
            ),
            range: Double(allowed.lowerBound)...Double(allowed.upperBound),
            style: .wedge(stops: ToolSettings.sizeStops(for: model.tool)),
            name: name,
            gamma: 2,
            readout: "\(model.brushSize)",
            normal: Double(max(allowed.lowerBound, 2))
        )
    }

    // MARK: - Selection

    /// What a selection can do. Crop and Copy are on the rail because they are
    /// the common case; the rest live here, one glance away.
    ///
    /// **Icons only, both orientations.** These used to be labelled buttons, and
    /// in a fixed 258pt panel four of them plus a size read-out truncated to
    /// `In…` and `D…` — a label that is one letter and an ellipsis is worse than
    /// no label, because it looks broken rather than deliberate. Dropping the
    /// words in the side panel fixed that but left the bottom bar keeping them,
    /// so the same four actions read two different ways depending on which edge
    /// the toolbar was on, for four words nobody was reading. One rule instead:
    /// a crop icon, an invert icon and a trash icon, each with its tooltip and
    /// its accessibility label, which is how Preview's markup bar does it too.
    @ViewBuilder
    private var selectionActions: some View {
        if isVertical {
            // "Area", not "Size". Every tool's own row is already labelled Size,
            // so a badge with its size slider open showed the word twice, once
            // for the badge and once for the marquee, with different units under
            // each. "Selection" was the obvious replacement and truncated to
            // "Selec…" in the label column, which this file already knows is
            // worse than no label at all — it looks broken rather than
            // deliberate. Four letters fit.
            OptionRow("Area") { sizeReadout }
            OptionRow(nil) {
                SegmentTrack { selectionActionButtons }
            }
        } else {
            HStack(spacing: Tokens.Space.tight) {
                if model.selectionSize != nil { sizeReadout }
                SegmentTrack { selectionActionButtons }
            }
        }
    }

    private var sizeReadout: some View {
        HStack(spacing: 3) {
            if model.selection?.isRectangular == false {
                Image(systemName: "lasso")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.primary.opacity(Tokens.Ink.faint))
            }
            Text(model.selectionSize.map { "\($0.width) × \($0.height)" } ?? "—")
                .font(Tokens.Text.pillValue)
                .foregroundStyle(.primary.opacity(Tokens.Ink.muted))
                .fixedSize()
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var selectionActionButtons: some View {
        let actions: [(String, String, () -> Void)] = {
            var list: [(String, String, () -> Void)] = [
                ("Crop", "crop", { model.cropToSelection() }),
                ("Invert", "square.righthalf.filled", { model.invertSelection() }),
            ]
            if model.selectionKind == .instantAlpha {
                list.append(
                    ("Make transparent", "eraser.line.dashed", { model.makeSelectionTransparent() })
                )
            }
            list.append(("Delete", "trash", { model.deleteSelection() }))
            return list
        }()

        ForEach(actions, id: \.0) { title, symbol, action in
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary.opacity(Tokens.Ink.regular))
                    // Equal shares along a side rail; intrinsic along the
                    // bottom bar, where the track is not filling a column.
                    .frame(maxWidth: isVertical ? .infinity : nil)
                    .padding(.horizontal, isVertical ? 2 : 7)
                    .frame(height: Tokens.Size.segment)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(title)
            .accessibilityLabel(title)
        }
    }
}

// MARK: - The shape gallery

/// Every shape, laid out like the ribbon's shape gallery.
///
/// Picking one also arms the shape tool, so the gallery is a way *in* rather
/// than a setting you can only reach once you are already there.
/// The highlighter's own inks, so picking one does not disturb the pen.
///
/// The last cell is the colour pair. Before this the highlighter *only* had that
/// behaviour, which made a fresh document's highlighter translucent black.
/// The one rule in the panel, separating the tool's own options from what can be
/// done to a selection.
///
/// Inset from both ends rather than running edge to edge: a full-bleed line cuts
/// the surface into two panels, and this is one panel with two parts. It also
/// fades rather than being a flat separator, so it does not compete with the
/// hairline that describes the panel's own edge.
private struct OptionsDivider: View {
    let isVertical: Bool

    var body: some View {
        let gradient = LinearGradient(
            colors: [
                .primary.opacity(0),
                .primary.opacity(Tokens.Ink.disabled),
                .primary.opacity(0),
            ],
            startPoint: isVertical ? .leading : .top,
            endPoint: isVertical ? .trailing : .bottom
        )

        Group {
            if isVertical {
                gradient.frame(height: 1).padding(.vertical, Tokens.Space.hair)
            } else {
                gradient.frame(width: 1).padding(.horizontal, Tokens.Space.hair)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct HighlighterInks: View {
    @Bindable var model: EditorModel

    var body: some View {
        HStack(spacing: 3) {
            ForEach(ToolSettings.highlighterInks, id: \.name) { ink in
                swatch(
                    fill: Color(ink.colour.cgColor),
                    isSelected: model.highlighterColour == ink.colour,
                    label: ink.name
                ) { model.highlighterColour = ink.colour }
            }
            // A pencil over the pair's colour. Without the glyph this cell is a
            // plain black square on a dark panel — indistinguishable from a
            // disabled control, when what it means is "use whatever the pen has".
            swatch(
                fill: Color(model.foreground.cgColor),
                isSelected: model.highlighterColour == nil,
                label: "Follow the current colour"
            ) { model.highlighterColour = nil }
            .overlay {
                Image(systemName: "pencil")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(model.foreground.prefersDarkContrast ? .black : .white)
                    .allowsHitTesting(false)
            }
        }
    }

    private func swatch(
        fill: Color, isSelected: Bool, label: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: Tokens.Radius.segmentInner, style: .continuous)
                .fill(fill)
                .frame(height: 22)
                .overlay {
                    // The chip's own contrast colour, never the accent. A blue ring on
                    // the blue ink disappears into it, and a blue ring on the yellow
                    // fights the thing it is pointing at. Same rule the rail palette
                    // already follows.
                    RoundedRectangle(cornerRadius: Tokens.Radius.segmentInner, style: .continuous)
                        .strokeBorder(
                            isSelected ? ring(on: fill) : Color.primary.opacity(0.18),
                            lineWidth: isSelected ? 2 : 1
                        )
                }
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// Black on a light ink, white on a dark one, judged on relative luminance.
    private func ring(on fill: Color) -> Color {
        let c = NSColor(fill).usingColorSpace(.sRGB) ?? .white
        let luma = 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
        return luma > 0.55 ? .black.opacity(0.7) : .white.opacity(0.9)
    }
}

private struct ShapeGallery: View {
    @Bindable var model: EditorModel
    let columns: Int

    @Environment(\.optionsAxisIsVertical) private var isVertical

    var body: some View {
        // Fifteen shapes over five columns is three exact rows — no orphan
        // cell, and the grid ends on the same edge as every control below it.
        FixedGrid(ShapeKind.allCases, columns: columns, spacing: 2) { kind in
            let isSelected = model.shapeKind == kind
            Button {
                model.selectShape(kind)
            } label: {
                Image(systemName: kind.symbolName)
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(Tokens.Ink.regular))
                    .frame(maxWidth: isVertical ? .infinity : 26)
                    .frame(height: 26)
                    .background {
                        RoundedRectangle(cornerRadius: Tokens.Radius.segmentInner, style: .continuous)
                            .fill(.clear)
                            .overlay { if isSelected { SelectedSegmentFill(cornerRadius: Tokens.Radius.segmentInner) } }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(kind.displayName)
            .accessibilityLabel(kind.displayName)
            .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        }
        .padding(2)
        .frame(maxWidth: isVertical ? .infinity : nil)
        .background {
            RoundedRectangle(cornerRadius: Tokens.Radius.segmentTrack, style: .continuous)
                .fill(.primary.opacity(Tokens.Fill.track))
        }
    }
}

// MARK: - Controls

/// Which way the panel is laid out, so a control can fill the column in the
/// side panel and size to its content along the bottom bar without every one
/// of them taking a parameter for it.
private struct OptionsAxisKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var optionsAxisIsVertical: Bool {
        get { self[OptionsAxisKey.self] }
        set { self[OptionsAxisKey.self] = newValue }
    }
}

/// One row of the panel: a label in the shared column, then its control.
///
/// Pass `nil` for a row that continues the one above it — the label column is
/// still reserved, so the control stays aligned with the one it belongs to
/// rather than sliding back to the panel's edge.
/// The next badge number, as the number.
///
/// A stepper wrapped in a pill, under a right-aligned "Next", was the same grey slab
/// as every other row in the panel. The numeral is the thing being set, so it is the
/// thing shown, at a size that reads before the title does.
///
/// Restart appears only when it would do something. A control that is present and
/// inert at the moment you look at it teaches you to stop reading the panel.
private struct BadgeNumber: View {
    let model: EditorModel

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: Tokens.Space.base) {
                end("minus", enabled: model.nextBadgeNumber > 1) {
                    model.setNextBadgeNumber(model.nextBadgeNumber - 1)
                }
                Text("\(model.nextBadgeNumber)")
                    .font(.system(size: 22, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.primary.opacity(Tokens.Ink.strong))
                    .frame(minWidth: 28)
                end("plus", enabled: model.nextBadgeNumber < 99) {
                    model.setNextBadgeNumber(model.nextBadgeNumber + 1)
                }
            }
            if model.nextBadgeNumber != 1 {
                Button("Restart at 1") { model.resetBadgeNumbering() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary.opacity(Tokens.Ink.muted))
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func end(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .foregroundStyle(.primary.opacity(enabled ? Tokens.Ink.regular : Tokens.Ink.disabled))
        .accessibilityLabel(symbol == "plus" ? "Increase" : "Decrease")
    }
}

struct OptionRow<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    @Environment(\.optionsAxisIsVertical) private var isVertical

    init(_ title: String?, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(spacing: Tokens.Space.tight) {
            if isVertical {
                Text(title ?? "")
                    .foregroundStyle(.primary.opacity(Tokens.Ink.muted))
                    .frame(width: Tokens.Size.optionLabel, alignment: .leading)
            } else if let title {
                Text(title)
                    .foregroundStyle(.primary.opacity(Tokens.Ink.muted))
                    .fixedSize()
            }
            content
        }
        .frame(maxWidth: isVertical ? .infinity : nil, alignment: .leading)
    }
}

/// The recessed track a segmented control sits in.
struct SegmentTrack<Content: View>: View {
    @ViewBuilder let content: Content

    @Environment(\.optionsAxisIsVertical) private var isVertical

    var body: some View {
        HStack(spacing: 1) {
            content
        }
        .padding(2)
        .frame(maxWidth: isVertical ? .infinity : nil)
        .background {
            RoundedRectangle(cornerRadius: Tokens.Radius.segmentTrack, style: .continuous)
                .fill(.primary.opacity(Tokens.Fill.track))
        }
    }
}

/// A one-of-many choice too long for a segmented track, wearing the panel's own
/// material rather than the system's.
///
/// This replaces a plain `Picker`. A stock `NSPopUpButton` in this panel was a
/// bezel, a fill and a corner radius none of the controls above or below it use,
/// plus the only accent-blue chrome on screen that was not a selection — so a
/// four-row panel was carrying three different control materials, and the odd one
/// out was the row in the middle.
///
/// The menu itself is still a real `Menu`, so it keeps native keyboard
/// navigation and the checkmark on the current item. Only the button is ours.
struct OptionMenu<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String
    /// Renders each row of the menu in the thing it selects, where that helps.
    /// A list of typeface names is the case that wants it.
    var previewsItself: Bool = false

    @Environment(\.optionsAxisIsVertical) private var isVertical
    @State private var isHovering = false

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    if previewsItself {
                        Text(title(option)).font(.custom(title(option), size: 13))
                    } else {
                        Text(title(option))
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(title(selection))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 2)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.primary.opacity(Tokens.Ink.muted))
            }
            .foregroundStyle(.primary.opacity(Tokens.Ink.regular))
            .padding(.horizontal, 6)
            .frame(maxWidth: isVertical ? .infinity : 124)
            .frame(height: Tokens.Size.segment)
            .background {
                RoundedRectangle(cornerRadius: Tokens.Radius.segmentInner, style: .continuous)
                    .fill(.primary.opacity(isHovering ? Tokens.Fill.hover : Tokens.Fill.cell))
            }
            .padding(2)
            .background {
                RoundedRectangle(cornerRadius: Tokens.Radius.segmentTrack, style: .continuous)
                    .fill(.primary.opacity(Tokens.Fill.track))
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .onHover { isHovering = $0 }
        .animation(Tokens.Motion.micro, value: isHovering)
    }
}

/// A slider with a live read-out, filling whatever column it is given.
///
/// `gamma` bends the travel: 2 squares the input, which is what turns a 1–96
/// range from "everything useful in the first centimetre" into a control you
/// can actually land 6px with.
struct OptionSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let readout: String
    var gamma: Double = 1

    @Environment(\.optionsAxisIsVertical) private var isVertical

    var body: some View {
        HStack(spacing: Tokens.Space.tight) {
            Slider(value: curved, in: 0...1)
                .controlSize(.mini)
                .frame(maxWidth: isVertical ? .infinity : 68)
                .labelsHidden()
            Text(readout)
                .font(Tokens.Text.pillValue)
                .foregroundStyle(.primary.opacity(Tokens.Ink.regular))
                .frame(minWidth: 26, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(readout)
    }

    /// The slider works in 0...1 and the curve maps it onto the real range, so
    /// the control keeps a linear feel while the values do not.
    private var curved: Binding<Double> {
        Binding(
            get: {
                let span = range.upperBound - range.lowerBound
                guard span > 0 else { return 0 }
                let t = (value - range.lowerBound) / span
                return pow(max(0, min(1, t)), 1 / gamma)
            },
            set: { t in
                let span = range.upperBound - range.lowerBound
                value = range.lowerBound + pow(max(0, min(1, t)), gamma) * span
            }
        )
    }
}

/// A segmented control on the chrome's own scale.
///
/// Built rather than `.pickerStyle(.segmented)` because the system control
/// brings its own height, material and corner radius, none of which match a
/// glass panel — it would read as a control borrowed from another window.
struct OptionSegment<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        var label: String?
        var symbol: String?
        var help: String?
        var id: Value { value }

        init(value: Value, label: String? = nil, symbol: String? = nil, help: String? = nil) {
            self.value = value
            self.label = label
            self.symbol = symbol
            self.help = help
        }
    }

    @Binding var selection: Value
    let options: [Option]

    @Environment(\.optionsAxisIsVertical) private var isVertical

    var body: some View {
        SegmentTrack {
            ForEach(options) { option in
                let isSelected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Group {
                        if let symbol = option.symbol {
                            Image(systemName: symbol).font(.system(size: 11))
                        } else {
                            Text(option.label ?? "")
                        }
                    }
                    .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(Tokens.Ink.regular))
                    // Equal shares of the row in the side panel, intrinsic
                    // width along the bottom bar. Padding-driven widths were
                    // why "Round / Square / Soft" was three times the size of
                    // the icon picker directly beneath it.
                    .frame(maxWidth: isVertical ? .infinity : nil)
                    .padding(.horizontal, isVertical ? 2 : (option.symbol == nil ? 8 : 7))
                    .frame(height: Tokens.Size.segment)
                    .background {
                        RoundedRectangle(cornerRadius: Tokens.Radius.segmentInner, style: .continuous)
                            .fill(.clear)
                            .overlay { if isSelected { SelectedSegmentFill(cornerRadius: Tokens.Radius.segmentInner) } }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(option.help ?? option.label ?? "")
                .accessibilityLabel(option.help ?? option.label ?? "")
                .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            }
        }
    }
}

/// An independently on/off cell inside a segment track.
///
/// Distinct from `OptionSegment`, which picks exactly one of a set: bold,
/// italic and underline combine, so they are three toggles that happen to share
/// a track rather than three states of one control.
///
/// **An unselected toggle still draws its cell.** `OptionSegment` can leave the
/// off cells empty because one of them is always filled, so the track always
/// says "these are the states of a control". Toggles can all be off at once,
/// and three bare glyphs in an empty trough — directly above an Align row where
/// one cell *is* filled — read as a control that is switched off rather than
/// three you can press. The faint cell is what distinguishes off from disabled.
struct OptionToggle: View {
    let symbol: String
    let help: String
    @Binding var isOn: Bool

    @Environment(\.optionsAxisIsVertical) private var isVertical
    @State private var isHovering = false

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(isOn ? Color.white : Color.primary.opacity(Tokens.Ink.regular))
                .frame(maxWidth: isVertical ? .infinity : nil)
                .padding(.horizontal, isVertical ? 2 : 7)
                .frame(height: Tokens.Size.segment)
                .background {
                    RoundedRectangle(cornerRadius: Tokens.Radius.segmentInner, style: .continuous)
                        .fill(
                            isOn
                                ? AnyShapeStyle(Color.accentColor)
                                : AnyShapeStyle(.primary.opacity(
                                    isHovering ? Tokens.Fill.hover : Tokens.Fill.cell
                                ))
                        )
                }
                .contentShape(Rectangle())
        }
        .onHover { isHovering = $0 }
        .animation(Tokens.Motion.micro, value: isHovering)
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
    }
}

/// A number you nudge, in the panel's own idiom.
///
/// A native `Stepper` brings its own label layout and its own control height, both
/// of which fight `OptionRow`; this is the same pill the rest of the panel uses,
/// with the readout between the two ends so the value sits where the eye already
/// looks for it.
struct OptionStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 2) {
            end("minus", enabled: value > range.lowerBound) { value = max(range.lowerBound, value - 1) }
            Text("\(value)")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .frame(minWidth: 22)
                .accessibilityHidden(true)
            end("plus", enabled: value < range.upperBound) { value = min(range.upperBound, value + 1) }
        }
        .padding(.horizontal, 4)
        .frame(height: Tokens.Size.pillAction)
        .background {
            RoundedRectangle(cornerRadius: Tokens.Radius.segmentTrack, style: .continuous)
                .fill(.primary.opacity(0.10))
        }
        .accessibilityElement()
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(range.upperBound, value + 1)
            case .decrement: value = max(range.lowerBound, value - 1)
            @unknown default: break
            }
        }
    }

    private func end(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 16, height: Tokens.Size.pillAction)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : Tokens.Ink.muted)
        .accessibilityLabel(symbol == "plus" ? "Increase" : "Decrease")
    }
}

/// A small labelled action inside the panel.
struct OptionButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    @State private var isHovering = false

    init(_ title: String, symbol: String, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 10.5))
                Text(title)
            }
            .padding(.horizontal, Tokens.Space.snug)
            .frame(height: Tokens.Size.pillAction)
            .background {
                RoundedRectangle(cornerRadius: Tokens.Radius.segmentTrack, style: .continuous)
                    .fill(.primary.opacity(isHovering ? 0.18 : 0.10))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(Tokens.Motion.micro, value: isHovering)
        .accessibilityLabel(title)
    }
}
