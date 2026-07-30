import PaintKit
import SwiftUI

/// The active tool's own controls, expanded from its button in the rail.
///
/// This is the classic ribbon's trick and it is the right one: the rail stays a
/// short list of *jobs*, and the variations — fifteen shapes, three brush tips,
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
            if model.hasSelection && !model.hasFloatingContent { selectionActions }
        }
        .environment(\.optionsAxisIsVertical, isVertical)
        .font(Tokens.Text.pillLabel)
        .lineLimit(1)
        .frame(width: isVertical ? Tokens.Rail.optionsContentWidth : nil, alignment: .leading)
        .fixedSize(horizontal: !isVertical, vertical: false)
        .padding(.horizontal, Tokens.Space.snug)
        .padding(.vertical, Tokens.Space.base - 1)
        .chromeSurface(cornerRadius: Tokens.Radius.panel)
        .animation(Tokens.Motion.pillResize, value: model.tool)
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
                        Text(hint)
                            .font(.system(size: 10))
                            .foregroundStyle(.primary.opacity(0.42))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.bottom, 2)
            } else {
                HStack(spacing: Tokens.Space.tight) {
                    title
                    if let hint {
                        Text(hint)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.primary.opacity(0.45))
                    }
                }
            }
        }
    }

    private var title: some View {
        Text(model.tool.displayName)
            .font(.system(size: 11.5, weight: .semibold))
    }

    /// One line saying how the tool is driven, for the tools whose gesture is
    /// not obvious from the glyph.
    private var hint: String? {
        switch model.tool {
        case .pencil: "1 px, fixed"
        case .text: "Drag its edge to move · corners resize · ⌘↩ places it"
        case .eyedropper: "Click to load Colour 1 · ⌥ from any tool"
        case .select where model.selectionKind == .lasso: "Trace any shape · it closes itself"
        case .select where model.selectionKind == .instantAlpha:
            "Click · ⇧ add · ⌥ subtract"
        case .select: "Drag it out · ⌘A selects all"
        case .badge: "Click to drop \(model.nextBadgeNumber)"
        case .shape where model.shapeKind == .curve:
            model.hasPendingShape ? "Now drag to bend it" : "Drag the line, then bend it"
        case .shape where model.shapeKind == .polygon:
            model.hasPendingShape ? "Click the first corner to close · ↩ to finish" : "Click each corner"
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
            sizeControl
            OptionRow("Tip") {
                OptionSegment(selection: $model.brushShape, options: [
                    .init(value: .round, label: "Round"),
                    .init(value: .square, label: "Square"),
                    .init(value: .soft, label: "Soft"),
                ])
            }

        case .airbrush:
            sizeControl
            OptionRow("Flow") {
                OptionSlider(
                    value: $model.sprayDensity,
                    range: 0.02...0.6,
                    readout: "\(Int(model.sprayDensity * 100))%"
                )
            }

        case .highlighter:
            sizeControl
            OptionRow("Ink") {
                OptionSlider(
                    value: $model.highlighterOpacity,
                    range: 0.1...0.8,
                    readout: "\(Int(model.highlighterOpacity * 100))%"
                )
            }

        case .eraser:
            sizeControl

        case .shape:
            ShapeGallery(model: model, columns: isVertical ? 5 : 8)
            sizeControl(title: "Stroke")
            if model.shapeKind.isClosed {
                OptionRow("Fill") {
                    OptionSegment(selection: $model.shapeStyle, options: [
                        .init(value: .outline, symbol: "square", help: "Outline"),
                        .init(value: .filled, symbol: "square.fill", help: "Fill"),
                        .init(value: .outlineAndFill, symbol: "square.inset.filled", help: "Outline and fill"),
                    ])
                }
            }
            OptionRow("Line") {
                OptionSegment(selection: $model.strokeDash, options: Raster.Dash.allCases.map {
                    .init(value: $0, symbol: $0.symbolName, help: $0.displayName)
                })
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
                Picker("", selection: $model.textFont) {
                    ForEach(Self.fonts, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: isVertical ? .infinity : 124)
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
            sizeControl
            OptionRow(nil) {
                OptionButton("Restart at 1", symbol: "arrow.counterclockwise") {
                    model.resetBadgeNumbering()
                }
            }

        case .fill:
            OptionRow("Match") {
                OptionSlider(
                    value: Binding(
                        get: { Double(model.fillTolerance) },
                        set: { model.fillTolerance = Int($0.rounded()) }
                    ),
                    range: 0...128,
                    readout: "\(model.fillTolerance)"
                )
            }

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
                        range: 0...128,
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

    private var sizeControl: some View { sizeControl(title: "Size") }

    /// Size, with the useful end of the range stretched out.
    ///
    /// A linear 1–96 slider spends four fifths of its travel on sizes nobody
    /// picks and makes 2px versus 5px a subpixel decision. Squaring the input
    /// puts ~24px at the halfway point, and the stops cover the four weights
    /// the classic Size dropdown offered.
    ///
    /// The stops now sit on their own line, inside a real segmented track. As
    /// four bare capsules trailing a slider they read as decoration — four
    /// dashes of different lengths with no container, no baseline and no
    /// indication they were clickable at all.
    @ViewBuilder
    private func sizeControl(title: String) -> some View {
        OptionRow(title) {
            OptionSlider(
                value: Binding(
                    get: { Double(model.brushSize) },
                    set: { model.brushSize = Int($0.rounded()) }
                ),
                range: Double(ToolSettings.sizeRange.lowerBound)...Double(ToolSettings.sizeRange.upperBound),
                readout: "\(model.brushSize)",
                gamma: 2
            )
        }
        OptionRow(nil) {
            SegmentTrack {
                ForEach(Self.sizeStops, id: \.self) { stop in
                    let isSelected = model.brushSize == stop
                    Button {
                        model.brushSize = stop
                    } label: {
                        Capsule()
                            .fill(isSelected ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary.opacity(0.55)))
                            .frame(height: max(1.5, min(7, CGFloat(stop) / 4)))
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 6)
                            .frame(height: Tokens.Size.segment)
                            .background {
                                RoundedRectangle(cornerRadius: Tokens.Radius.segmentInner, style: .continuous)
                                    .fill(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.clear))
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("\(stop) px")
                    .accessibilityLabel("\(stop) pixel \(title.lowercased())")
                    .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
                }
            }
        }
    }

    private static let sizeStops = [1, 4, 12, 28]

    // MARK: - Selection

    /// What a selection can do. Crop and Copy are on the rail because they are
    /// the common case; the rest live here, one glance away.
    ///
    /// **Icons only in the side panel.** Four labelled buttons plus a size
    /// read-out do not fit 258pt, and the panel is a fixed width, so they
    /// truncated to `In…` and `D…` — a button whose label is one letter and an
    /// ellipsis is worse than one with no label, because it looks broken rather
    /// than deliberate. Each still carries its tooltip and accessibility label.
    /// The bottom bar has the window's width and keeps the words.
    @ViewBuilder
    private var selectionActions: some View {
        if isVertical {
            OptionRow("Size") {
                HStack(spacing: 3) {
                    if model.selection?.isRectangular == false {
                        Image(systemName: "lasso")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.primary.opacity(0.5))
                    }
                    Text(model.selectionSize.map { "\($0.width) × \($0.height)" } ?? "—")
                        .font(Tokens.Text.pillValue)
                        .foregroundStyle(.primary.opacity(0.7))
                    Spacer(minLength: 0)
                }
            }
            OptionRow(nil) {
                SegmentTrack {
                    selectionActionButtons(labelled: false)
                }
            }
        } else {
            HStack(spacing: Tokens.Space.tight) {
                if let size = model.selectionSize {
                    HStack(spacing: 3) {
                        if model.selection?.isRectangular == false {
                            Image(systemName: "lasso")
                                .font(.system(size: 9.5))
                                .foregroundStyle(.primary.opacity(0.5))
                        }
                        Text("\(size.width) × \(size.height)")
                            .font(Tokens.Text.pillValue)
                            .foregroundStyle(.primary.opacity(0.6))
                    }
                }
                selectionActionButtons(labelled: true)
            }
        }
    }

    @ViewBuilder
    private func selectionActionButtons(labelled: Bool) -> some View {
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
            if labelled {
                OptionButton(title, symbol: symbol, action: action)
            } else {
                Button(action: action) {
                    Image(systemName: symbol)
                        .font(.system(size: 11))
                        .foregroundStyle(.primary.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .frame(height: Tokens.Size.segment)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(title)
                .accessibilityLabel(title)
            }
        }
    }
}

// MARK: - The shape gallery

/// Every shape, laid out like the ribbon's shape gallery.
///
/// Picking one also arms the shape tool, so the gallery is a way *in* rather
/// than a setting you can only reach once you are already there.
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
                    .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.8))
                    .frame(maxWidth: isVertical ? .infinity : 26)
                    .frame(height: 26)
                    .background {
                        RoundedRectangle(cornerRadius: Tokens.Radius.segmentInner, style: .continuous)
                            .fill(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.clear))
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
                .fill(.primary.opacity(0.12))
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
                    .foregroundStyle(.primary.opacity(0.6))
                    .frame(width: Tokens.Size.optionLabel, alignment: .leading)
            } else if let title {
                Text(title)
                    .foregroundStyle(.primary.opacity(0.6))
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
                .fill(.primary.opacity(0.12))
        }
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
                .foregroundStyle(.primary.opacity(0.85))
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
                    .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.8))
                    // Equal shares of the row in the side panel, intrinsic
                    // width along the bottom bar. Padding-driven widths were
                    // why "Round / Square / Soft" was three times the size of
                    // the icon picker directly beneath it.
                    .frame(maxWidth: isVertical ? .infinity : nil)
                    .padding(.horizontal, isVertical ? 2 : (option.symbol == nil ? 8 : 7))
                    .frame(height: Tokens.Size.segment)
                    .background {
                        RoundedRectangle(cornerRadius: Tokens.Radius.segmentInner, style: .continuous)
                            .fill(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.clear))
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
struct OptionToggle: View {
    let symbol: String
    let help: String
    @Binding var isOn: Bool

    @Environment(\.optionsAxisIsVertical) private var isVertical

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(isOn ? Color.white : Color.primary.opacity(0.8))
                .frame(maxWidth: isVertical ? .infinity : nil)
                .padding(.horizontal, isVertical ? 2 : 7)
                .frame(height: Tokens.Size.segment)
                .background {
                    RoundedRectangle(cornerRadius: Tokens.Radius.segmentInner, style: .continuous)
                        .fill(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.clear))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
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
