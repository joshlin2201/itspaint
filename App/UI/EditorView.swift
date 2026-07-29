import PaintKit
import SwiftUI

/// The editor window.
///
/// **Artwork to all four edges, one glass rail over it, and the active tool's
/// own controls expanded beside the button you pressed.** The rail is on the
/// left by default and can move to the bottom; everything that matters —
/// every tool, both loaded colours, the whole palette — is on screen at once,
/// because the app it descends from was learnable precisely because nothing
/// was hidden.
///
/// The trade, stated honestly: the rail costs about 90pt of window. That is the
/// price of never making someone hunt for a swatch, and it buys back the
/// discoverability a floating cluster spends.
struct EditorView: View {
    @Bindable var model: EditorModel

    /// One tooltip for the whole chrome, so moving along the rail slides a
    /// single chip rather than popping thirteen.
    @State private var tooltips = TooltipController()
    /// Which cell the options panel should point at, in rail order.
    @State private var anchoredIndex: Int = 0

    var body: some View {
        ZStack {
            // The artwork owns everything the rail does not.
            //
            // Inset rather than underlapped: a permanent rail that covers the
            // left of the picture makes you drag the canvas around to see what
            // is behind it, which is the opposite of having the tools to hand.
            CanvasScrollView(model: model)
                .padding(.leading, model.chromeEdge.isVertical
                    ? Tokens.Chrome.railFootprint(for: model.chromeEdge)
                    : Tokens.Chrome.frameGap)
                .padding(.trailing, Tokens.Chrome.frameGap)
                .padding(.top, Tokens.Chrome.titleReserve)
                .padding(.bottom, model.chromeEdge.isVertical
                    ? Tokens.Chrome.frameGap
                    : Tokens.Chrome.railFootprint(for: model.chromeEdge))
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
            ? size.height - Tokens.Chrome.titleReserve - Tokens.Chrome.railInset
            : size.width - Tokens.Chrome.railInset * 2

        Group {
            if isVertical {
                HStack(alignment: .top, spacing: Tokens.Space.tight) {
                    scrollingRail(maxLength: available, isVertical: true)
                    if model.isOptionsExpanded {
                        ToolOptions(model: model)
                            .fixedSize()
                            .padding(.top, min(panelOffset, max(0, available - 120)))
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
                        ToolOptions(model: model)
                            .fixedSize()
                            .padding(.leading, min(panelOffset, max(0, available - 220)))
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
                        x: isVertical ? Tokens.Rail.verticalThickness + Tokens.Space.snug : 0,
                        y: isVertical ? Tokens.Chrome.titleReserve : -Tokens.Rail.horizontalThickness
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

    /// The rail, scrolling only when the window is too small to hold it.
    @ViewBuilder
    private func scrollingRail(maxLength: CGFloat, isVertical: Bool) -> some View {
        ScrollView(isVertical ? .vertical : .horizontal, showsIndicators: false) {
            ToolRail(model: model) { model.selectTool($0) }
                .fixedSize()
        }
        .frame(
            maxWidth: isVertical ? Tokens.Rail.verticalThickness : maxLength,
            maxHeight: isVertical ? maxLength : Tokens.Rail.horizontalThickness + 2
        )
        .fixedSize(horizontal: isVertical, vertical: !isVertical)
    }

    /// Distance from the rail's leading edge to the selected cell, so the panel
    /// starts level with the button it came from.
    private var panelOffset: CGFloat {
        let cell = Tokens.Size.toolCell + Tokens.Space.hair
        if model.chromeEdge.isVertical {
            // Two cells per row, plus a separator between each group above.
            let index = anchoredIndex
            let row = CGFloat(index / 2)
            let groupsAbove = CGFloat(Self.groupIndex(of: model.tool))
            return Tokens.Rail.padding + row * cell
                + groupsAbove * (1 + Tokens.Rail.sectionSpacing * 2)
        }
        return Tokens.Rail.padding + CGFloat(anchoredIndex) * cell
            + CGFloat(Self.groupIndex(of: model.tool))
                * (1 + Tokens.Rail.sectionSpacing * 2)
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

    // MARK: - Rows

    private var titleRow: some View {
        HStack(spacing: Tokens.Space.base) {
            // Clear the traffic lights.
            Color.clear.frame(width: Tokens.Chrome.trafficLightClearance, height: 1)

            TitleChip(name: model.documentName, isEdited: model.isEdited)

            Spacer(minLength: Tokens.Space.comfortable)

            WindowActions(model: model)
                .fixedSize()
        }
        .padding(.horizontal, Tokens.Space.comfortable)
        .frame(height: Tokens.Chrome.titleReserve, alignment: .center)
    }

    private var readOutRow: some View {
        StatusStrip(model: model)
            .padding(.trailing, Tokens.Space.safeInset)
            .padding(.bottom, model.chromeEdge.isVertical
                ? Tokens.Space.safeInset
                : Tokens.Space.safeInset + Tokens.Rail.horizontalThickness + Tokens.Space.base)
    }
}
