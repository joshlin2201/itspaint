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

    var body: some View {
        let layout = isVertical
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tokens.Space.tight + 1))
            : AnyLayout(HStackLayout(spacing: Tokens.Space.snug))

        layout {
            header
            controls
            if model.hasSelection { selectionActions }
        }
        .font(Tokens.Text.pillLabel)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, Tokens.Space.snug)
        .padding(.vertical, Tokens.Space.tight + 1)
        .chromeSurface(cornerRadius: Tokens.Radius.panel)
        .animation(Tokens.Motion.pillResize, value: model.tool)
        .animation(Tokens.Motion.pillResize, value: model.hasSelection)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Tokens.Space.tight) {
            Text(model.tool.displayName)
                .font(.system(size: 11.5, weight: .semibold))
            if let hint {
                Text(hint)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.primary.opacity(0.45))
            }
        }
    }

    /// One line saying how the tool is driven, for the tools whose gesture is
    /// not obvious from the glyph.
    private var hint: String? {
        switch model.tool {
        case .pencil: "1 px, fixed"
        case .text: "Drag a box · ⌘-drag moves it · ⌘↩ places it"
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
            OptionSegment(selection: $model.brushShape, options: [
                .init(value: .round, label: "Round"),
                .init(value: .square, label: "Square"),
                .init(value: .soft, label: "Soft"),
            ])

        case .airbrush:
            sizeControl
            OptionSlider(
                title: "Flow",
                value: $model.sprayDensity,
                range: 0.02...0.6,
                readout: "\(Int(model.sprayDensity * 100))%"
            )

        case .highlighter:
            sizeControl
            OptionSlider(
                title: "Ink",
                value: $model.highlighterOpacity,
                range: 0.1...0.8,
                readout: "\(Int(model.highlighterOpacity * 100))%"
            )

        case .eraser:
            sizeControl

        case .shape:
            ShapeGallery(model: model, columns: isVertical ? 5 : 8)
            sizeControl(title: "Stroke")
            if model.shapeKind.isClosed {
                OptionSegment(selection: $model.shapeStyle, options: [
                    .init(value: .outline, symbol: "square", help: "Outline"),
                    .init(value: .filled, symbol: "square.fill", help: "Fill"),
                    .init(value: .outlineAndFill, symbol: "square.inset.filled", help: "Outline and fill"),
                ])
            }
            OptionSegment(selection: $model.strokeDash, options: Raster.Dash.allCases.map {
                .init(value: $0, symbol: $0.symbolName, help: $0.displayName)
            })
            if model.shapeKind == .roundedRectangle || model.shapeKind == .callout {
                OptionSlider(
                    title: "Corner",
                    value: Binding(
                        get: { Double(model.cornerRadius) },
                        set: { model.cornerRadius = Int($0.rounded()) }
                    ),
                    range: 0...48,
                    readout: "\(model.cornerRadius)"
                )
            }

        case .text:
            OptionSlider(
                title: "Size",
                value: $model.textSize,
                range: 8...200,
                readout: "\(Int(model.textSize))",
                gamma: 2
            )
            Picker("", selection: $model.textFont) {
                ForEach(Self.fonts, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 124)
            OptionSegment(selection: $model.textAlignment, options: [
                .init(value: .left, symbol: "text.alignleft", help: "Align left"),
                .init(value: .centre, symbol: "text.aligncenter", help: "Align centre"),
                .init(value: .right, symbol: "text.alignright", help: "Align right"),
            ])

        case .badge:
            sizeControl
            OptionButton("Restart at 1", symbol: "arrow.counterclockwise") {
                model.resetBadgeNumbering()
            }

        case .fill:
            OptionSlider(
                title: "Tolerance",
                value: Binding(
                    get: { Double(model.fillTolerance) },
                    set: { model.fillTolerance = Int($0.rounded()) }
                ),
                range: 0...128,
                readout: "\(model.fillTolerance)"
            )

        case .pixelate:
            OptionSlider(
                title: "Block",
                value: Binding(
                    get: { Double(model.pixelateBlockSize) },
                    set: { model.pixelateBlockSize = Int($0.rounded()) }
                ),
                range: 4...48,
                readout: "\(model.pixelateBlockSize)"
            )

        case .select:
            OptionSegment(selection: $model.selectionKind, options: SelectionKind.allCases.map {
                .init(value: $0, symbol: $0.symbolName, help: $0.displayName)
            })
            if model.selectionKind == .instantAlpha {
                OptionSlider(
                    title: "Tolerance",
                    value: Binding(
                        get: { Double(model.selectionTolerance) },
                        set: { model.selectionTolerance = Int($0.rounded()) }
                    ),
                    range: 0...128,
                    readout: "\(model.selectionTolerance)"
                )
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
    private func sizeControl(title: String) -> some View {
        HStack(spacing: Tokens.Space.tight) {
            OptionSlider(
                title: title,
                value: Binding(
                    get: { Double(model.brushSize) },
                    set: { model.brushSize = Int($0.rounded()) }
                ),
                range: Double(ToolSettings.sizeRange.lowerBound)...Double(ToolSettings.sizeRange.upperBound),
                readout: "\(model.brushSize)",
                gamma: 2
            )
            ForEach(Self.sizeStops, id: \.self) { stop in
                Button {
                    model.brushSize = stop
                } label: {
                    Capsule()
                        .fill(model.brushSize == stop ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary.opacity(0.45)))
                        .frame(width: 16, height: max(1, min(7, CGFloat(stop) / 4)))
                        .frame(width: 20, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(stop) px")
                .accessibilityLabel("\(stop) pixel \(title.lowercased())")
            }
        }
    }

    private static let sizeStops = [1, 4, 12, 28]

    // MARK: - Selection

    /// What a selection can do. Crop and Copy are on the rail because they are
    /// the common case; the rest live here, one glance away.
    private var selectionActions: some View {
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
            OptionButton("Crop", symbol: "crop") { model.cropToSelection() }
            OptionButton("Invert", symbol: "square.righthalf.filled") { model.invertSelection() }
            if model.selectionKind == .instantAlpha {
                OptionButton("Make transparent", symbol: "eraser.line.dashed") {
                    model.makeSelectionTransparent()
                }
            }
            OptionButton("Delete", symbol: "trash") { model.deleteSelection() }
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

    var body: some View {
        FixedGrid(ShapeKind.allCases, columns: columns, spacing: 2) { kind in
            let isSelected = model.shapeKind == kind
            Button {
                    model.selectShape(kind)
                } label: {
                    Image(systemName: kind.symbolName)
                        .font(.system(size: 11))
                        .frame(width: 24, height: 22)
                        .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.8))
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
    }
}

// MARK: - Controls

/// A labelled slider with a live read-out.
///
/// `gamma` bends the travel: 2 squares the input, which is what turns a 1–96
/// range from "everything useful in the first centimetre" into a control you
/// can actually land 6px with.
struct OptionSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let readout: String
    var width: CGFloat = 68
    var gamma: Double = 1

    var body: some View {
        HStack(spacing: Tokens.Space.tight) {
            Text(title)
                .foregroundStyle(.primary.opacity(0.6))
                .fixedSize()
            Slider(value: curved, in: 0...1)
                .controlSize(.mini)
                .frame(width: width)
                .labelsHidden()
            Text(readout)
                .font(Tokens.Text.pillValue)
                .frame(minWidth: 24, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
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

    var body: some View {
        HStack(spacing: 1) {
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
                    .frame(height: Tokens.Size.segment)
                    .padding(.horizontal, option.symbol == nil ? Tokens.Space.snug : 7)
                    .background {
                        RoundedRectangle(cornerRadius: Tokens.Radius.segmentInner, style: .continuous)
                            .fill(isSelected ? AnyShapeStyle(.primary.opacity(0.20)) : AnyShapeStyle(.clear))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(option.help ?? option.label ?? "")
                .accessibilityLabel(option.help ?? option.label ?? "")
                .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(2)
        .background {
            RoundedRectangle(cornerRadius: Tokens.Radius.segmentTrack, style: .continuous)
                .fill(.primary.opacity(0.12))
        }
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
