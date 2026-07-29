import PaintKit
import SwiftUI

/// The editor window.
///
/// **Artwork to all four edges, one glass rail over it, and the active tool's
/// own controls expanded beside the button you pressed.** The rail is on the
/// left by default and can move to the bottom; everything that matters —
/// every tool, both loaded colours, a palette — is on screen at once, because
/// the app it descends from was learnable precisely because nothing was hidden.
///
/// The trade, stated honestly: the rail costs 48pt of window on whichever edge
/// it is on. That is the price of never making someone hunt for a tool, and it
/// buys back the discoverability a floating cluster spends. It used to cost
/// nearly twice that, on a rail that ran the full height of the window; the
/// difference was two extra columns of cells nothing needed.
struct EditorView: View {
    @Bindable var model: EditorModel

    /// One tooltip for the whole chrome, so moving along the rail slides a
    /// single chip rather than popping thirteen.
    @State private var tooltips = TooltipController()
    /// Which cell the options panel should point at, in rail order.
    @State private var anchoredIndex: Int = 0
    /// The panel's measured length along the rail's axis, so it can be kept
    /// inside the window without guessing how tall its content is.
    @State private var panelSpan: CGFloat = 0

    var body: some View {
        ZStack {
            // The artwork owns everything the rail does not.
            //
            // Inset rather than underlapped: a permanent rail that covers the
            // left of the picture makes you drag the canvas around to see what
            // is behind it, which is the opposite of having the tools to hand.
            CanvasScrollView(model: model)
                .padding(.leading, model.chromeEdge.isVertical
                    ? Tokens.Chrome.railFootprint
                    : Tokens.Chrome.frameGap)
                .padding(.trailing, Tokens.Chrome.frameGap)
                .padding(.top, Tokens.Chrome.titleReserve)
                .padding(.bottom, model.chromeEdge.isVertical
                    ? Tokens.Chrome.frameGap
                    : Tokens.Chrome.railFootprint)
                .animation(Tokens.Motion.pillResize, value: model.chromeEdge)

            TitlebarScrim()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            titleRow
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            readOutRow
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)

            chrome
        }
        // The whole layout spans the window, titlebar included.
        //
        // `.fullSizeContentView` lets the content view extend under the
        // titlebar, but SwiftUI's safe area still excludes it — so a
        // GeometryReader reports ~28pt less than the window really has, the
        // canvas ends up taller than its own viewport, and a scrollbar appears
        // on a window that was sized to fit exactly.
        .ignoresSafeArea()
        .background {
            // The well the artwork sits in. A slow vertical gradient rather
            // than a flat fill: it gives the window depth at no cost in
            // attention, and it is what stops a white canvas on a flat grey
            // reading like an unfinished view.
            LinearGradient(
                colors: [Color(nsColor: .underPageBackgroundColor).opacity(0.92),
                         Color(nsColor: .underPageBackgroundColor)],
                startPoint: .top,
                endPoint: .bottom
            )
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [.white.opacity(0.05), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 220)
            }
            .ignoresSafeArea()
        }
        .environment(tooltips)
        .onChange(of: model.tool) { _, tool in
            anchoredIndex = Self.railIndex(of: tool)
        }
        .onAppear { anchoredIndex = Self.railIndex(of: model.tool) }
        .sheet(isPresented: $model.isSizeSheetPresented) {
            SizeSheet(model: model)
        }
        .sheet(isPresented: $model.isRotateSheetPresented) {
            RotateSheet(model: model)
        }
        .alert(item: $model.presentedError) { error in
            Alert(
                title: Text(error.message),
                message: error.recovery.map(Text.init),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    // MARK: - Chrome

    /// The rail and the panel that expands from it.
    ///
    /// The panel is offset to line up with the selected cell rather than
    /// measured into place: cells are a fixed size, so the geometry is known
    /// without a layout pass and the panel cannot lag a frame behind the
    /// button it belongs to.
    @ViewBuilder
    private var chrome: some View {
        let isVertical = model.chromeEdge.isVertical

        GeometryReader { proxy in
            chromeStack(isVertical: isVertical, in: proxy.size)
        }
    }

    /// The rail and its panel, both clamped to the window.
    ///
    /// A toolbar that runs off the bottom of a short window is worse than one
    /// that scrolls, and a panel that runs off the right of a narrow one is a
    /// control you cannot reach — so both are bounded by what the window
    /// actually has.
    @ViewBuilder
    private func chromeStack(isVertical: Bool, in size: CGSize) -> some View {
        let available = isVertical
            ? size.height - Tokens.Chrome.titleReserve - Tokens.Space.safeInset
            : size.width - Tokens.Chrome.railInset * 2

        Group {
            if isVertical {
                HStack(alignment: .top, spacing: Tokens.Space.tight) {
                    scrollingRail(maxLength: available, isVertical: true)
                    if model.isOptionsExpanded {
                        optionsPanel(isVertical: true)
                            .padding(.top, clampedPanelOffset(within: available))
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                    }
                }
                .padding(.leading, Tokens.Chrome.railInset)
                .padding(.top, Tokens.Chrome.titleReserve)
                .padding(.bottom, Tokens.Space.safeInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                VStack(alignment: .leading, spacing: Tokens.Space.tight) {
                    if model.isOptionsExpanded {
                        optionsPanel(isVertical: false)
                            .padding(.leading, clampedPanelOffset(within: available))
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    scrollingRail(maxLength: available, isVertical: false)
                }
                .padding(.horizontal, Tokens.Chrome.railInset)
                .padding(.bottom, Tokens.Chrome.railInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
        .overlay(alignment: isVertical ? .topLeading : .bottomLeading) {
            if tooltips.isVisible {
                Tooltip(title: tooltips.title, shortcut: tooltips.shortcut)
                    .offset(
                        x: isVertical ? Tokens.Rail.thickness + Tokens.Space.snug : 0,
                        y: isVertical ? Tokens.Chrome.titleReserve : -Tokens.Rail.thickness
                    )
                    .allowsHitTesting(false)
            }
        }
        .animation(Tokens.Motion.pillResize, value: anchoredIndex)
        .animation(Tokens.Motion.pillResize, value: model.isOptionsExpanded)
        .animation(Tokens.Motion.micro, value: tooltips.visibleKey)
        // The chrome steps back while a drag is in flight so the marching ants
        // are never competing with it for attention.
        .opacity(model.isDragging ? 0.55 : 1)
        .animation(Tokens.Motion.micro, value: model.isDragging)
        .onChange(of: model.isDragging) { _, dragging in
            if dragging { tooltips.dismiss() }
        }
    }

    /// The options panel, reporting how long it is along the rail's axis.
    ///
    /// Measured rather than assumed. The panel's height is entirely content —
    /// the shape tool alone carries a fifteen-cell gallery, three segmented
    /// controls and a slider — so the fixed 120pt guess the clamp used to make
    /// let exactly the tallest panels hang off the bottom of a short window.
    @ViewBuilder
    private func optionsPanel(isVertical: Bool) -> some View {
        ToolOptions(model: model)
            .fixedSize()
            .background {
                GeometryReader { proxy in
                    let span = isVertical ? proxy.size.height : proxy.size.width
                    Color.clear
                        .onAppear { panelSpan = span }
                        .onChange(of: span) { _, new in panelSpan = new }
                }
            }
    }

    /// Where the panel may start, so its far end still lands inside the window.
    private func clampedPanelOffset(within available: CGFloat) -> CGFloat {
        max(0, min(panelOffset, available - panelSpan))
    }

    /// The rail, shedding swatches before it ever scrolls.
    ///
    /// A short window used to clip the rail: the colour block was cut in half
    /// and the edge toggle was simply gone, below the fold of a scroll view
    /// with hidden indicators — so there was no way to tell that anything was
    /// missing, let alone reach it. **The tools and the loaded colours are the
    /// part that must never be cut**, and the palette is the part that can give
    /// ground, because every swatch it drops is still in the popover.
    ///
    /// Only once the palette is gone entirely and the window is still too short
    /// does it fall back to scrolling.
    @ViewBuilder
    private func scrollingRail(maxLength: CGFloat, isVertical: Bool) -> some View {
        ScrollView(isVertical ? .vertical : .horizontal, showsIndicators: false) {
            ToolRail(
                model: model,
                swatchPairs: isVertical ? Self.swatchPairs(fitting: maxLength) : Palette.columns
            ) { model.selectTool($0) }
                .fixedSize()
        }
        .frame(
            maxWidth: isVertical ? Tokens.Rail.thickness : maxLength,
            maxHeight: isVertical ? maxLength : Tokens.Rail.thickness + 2
        )
        .fixedSize(horizontal: isVertical, vertical: !isVertical)
    }

    /// How many columns of the palette the side rail can show in `height`.
    ///
    /// Everything above the palette is fixed, so this is one subtraction rather
    /// than a layout pass — which matters, because the answer feeds a view that
    /// is being laid out.
    private static func swatchPairs(fitting height: CGFloat) -> Int {
        let cell = Tokens.Size.toolCell + Tokens.Space.hair
        let tools = ToolKind.groups.reduce(CGFloat.zero) { $0 + CGFloat($1.count) * cell }
        let separators = CGFloat(ToolKind.groups.count) * (1 + Tokens.Rail.sectionSpacing * 2)
        let pair = Tokens.Size.colourWell * 1.42 + Tokens.Space.hair + Tokens.Size.colourSwap
        let toggle = Tokens.Rail.sectionSpacing + Tokens.Size.toolCell
        let fixed = Tokens.Rail.padding * 2 + tools + separators
            + pair + Tokens.Space.tight + Tokens.Rail.colourInset * 2 + toggle

        let forSwatches = height - fixed
        let row = Tokens.Size.swatch + Tokens.Rail.swatchGap
        return max(0, min(Tokens.Rail.swatchPairs, Int(forSwatches / row)))
    }

    /// Distance from the rail's leading edge to the selected cell, so the panel
    /// starts level with the button it came from.
    ///
    /// Counted per group rather than by dividing the rail-wide index: each
    /// group starts its own grid, so a group whose cell count is not a multiple
    /// of the column count leaves a short final row. The old arithmetic
    /// (`index / 2`) silently assumed groups packed continuously and drifted a
    /// full row low by the time it reached the eyedropper.
    private var panelOffset: CGFloat {
        let cell = Tokens.Size.toolCell + Tokens.Space.hair
        let group = Self.groupIndex(of: model.tool)
        let separators = CGFloat(group) * (1 + Tokens.Rail.sectionSpacing * 2)

        guard model.chromeEdge.isVertical else {
            return Tokens.Rail.padding + CGFloat(anchoredIndex) * cell + separators
        }

        let columns = Tokens.Rail.toolColumns
        let rowsAbove = ToolKind.groups.prefix(group)
            .reduce(0) { $0 + ($1.count + columns - 1) / columns }
        let row = rowsAbove + Self.indexWithinGroup(of: model.tool) / columns
        return Tokens.Rail.padding + CGFloat(row) * cell + separators
    }

    /// Position of a tool within the rail's own ordering.
    private static func railIndex(of tool: ToolKind) -> Int {
        var index = 0
        for group in ToolKind.groups {
            if let found = group.firstIndex(of: tool) { return index + found }
            index += group.count
        }
        return 0
    }

    private static func groupIndex(of tool: ToolKind) -> Int {
        ToolKind.groups.firstIndex { $0.contains(tool) } ?? 0
    }

    private static func indexWithinGroup(of tool: ToolKind) -> Int {
        ToolKind.groups.compactMap { $0.firstIndex(of: tool) }.first ?? 0
    }

    // MARK: - Rows

    private var titleRow: some View {
        HStack(spacing: Tokens.Space.comfortable) {
            // Clear the traffic lights.
            Color.clear.frame(width: Tokens.Chrome.trafficLightClearance, height: 1)

            DocumentTitle(
                name: model.documentName,
                isEdited: model.isEdited,
                size: model.canvasSize
            )
            // The title yields before the controls do. A long filename should
            // truncate in the middle, not push Undo off the window.
            .layoutPriority(-1)

            Spacer(minLength: Tokens.Space.base)

            WindowActions(model: model)
                .fixedSize()
        }
        .padding(.horizontal, Tokens.Space.comfortable)
        .frame(height: Tokens.Chrome.titleReserve, alignment: .center)
    }

    private var readOutRow: some View {
        PointerReadout(model: model)
            .padding(.trailing, Tokens.Space.comfortable)
            .padding(.bottom, model.chromeEdge.isVertical
                ? Tokens.Space.snug
                : Tokens.Space.snug + Tokens.Rail.thickness + Tokens.Space.base)
    }
}
