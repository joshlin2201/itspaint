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
    /// The tooltip chip's measured size, so it can be kept inside the window on
    /// both axes.
    @State private var tooltipSize: CGSize = .zero

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

            tooltipLayer
                // **Above the tool chrome, which is drawn after it.** Share is
                // the one control in this row that is an NSViewRepresentable
                // rather than a SwiftUI Button — it hosts a real NSButton so its
                // popover can anchor to itself — and a hosted AppKit view can be
                // occluded for hit-testing by SwiftUI siblings that come later in
                // the stack, even where they draw nothing. That matches the
                // report exactly: cut, copy and paste kept working while Share
                // alone stopped responding. The header band belongs to the
                // header.
                .zIndex(1)

            readOutRow
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)

            // Which page of the PDF is on the canvas, in the same bottom-centre
            // slot the paste bar uses.
            //
            // **Not in the header.** A letter page opens a window about 650pt
            // wide, and at that width a fourth capsule in the title row pushed
            // the filename out of it entirely — a document with no visible name
            // is a worse trade than a page control that is not in the titlebar.
            // Down here it has room, it is where Books and Preview put page
            // navigation, and it is only ever on screen for documents that have
            // pages at all. The paste bar wins the slot while something is
            // floating, because turning the page is not what anyone is doing
            // mid-paste.
            if model.pdfPage != nil, !model.hasFloatingContent {
                PageControl(model: model)
                    .fixedSize()
                    .padding(.bottom, model.chromeEdge.isVertical
                        ? Tokens.Space.safeInset
                        : Tokens.Space.safeInset + Tokens.Rail.thickness + Tokens.Space.base)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    // Out of the way of the stroke being drawn, exactly like the
                    // paste bar: a signature often lands right where this sits.
                    .opacity(model.isDragging ? 0 : 1)
                    .animation(Tokens.Motion.micro, value: model.isDragging)
            }

            // Bottom-centre, clear of the rail on either edge and of the
            // pointer read-out in the corner.
            //
            // **One bar owns this slot.** A floating paste is itself a selection,
            // so both bars are eligible at once and showing both would be two
            // answers to one question. The paste bar wins because placing or
            // discarding is the decision actually in front of you.
            if !model.hasFloatingContent, model.hasSelection {
                SelectionActions(model: model)
                    .fixedSize()
                    .padding(.bottom, model.chromeEdge.isVertical
                        ? Tokens.Space.safeInset
                        : Tokens.Space.safeInset + Tokens.Rail.thickness + Tokens.Space.base)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    // Out of the way while the marquee is being dragged: the bar
                    // is about the selection you have finished making, and its
                    // own size read-out is the one thing that would flicker.
                    .opacity(model.isDragging ? 0 : 1)
                    .animation(Tokens.Motion.micro, value: model.isDragging)
            }

            if model.hasFloatingContent {
                FloatingActions(model: model)
                    .fixedSize()
                    .padding(.bottom, model.chromeEdge.isVertical
                        ? Tokens.Space.safeInset
                        : Tokens.Space.safeInset + Tokens.Rail.thickness + Tokens.Space.base)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    // Out of the way while the content is actually being dragged.
                    .opacity(model.isDragging ? 0 : 1)
                    .animation(Tokens.Motion.micro, value: model.isDragging)
            }

            chrome
        }
        // The bars appear and disappear with the thing they act on.
        .animation(Tokens.Motion.pillResize, value: model.hasFloatingContent)
        .animation(Tokens.Motion.pillResize, value: model.hasSelection)
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
        .sheet(isPresented: $model.isSignatureSheetPresented) {
            SignatureSheet(model: model)
        }
        .sheet(isPresented: $model.isRotateSheetPresented) {
            RotateSheet(model: model)
        }
        .confirmationDialog(
            "Duplicate this drawing?",
            isPresented: $model.isDuplicateConfirmationPresented
        ) {
            Button("Duplicate") { model.duplicateDocument() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A copy opens in a new window. This one is left exactly as it is.")
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

    /// The rail, shedding swatches before it ever scrolls — and scrolling only
    /// the part that can afford to be scrolled.
    ///
    /// A short window used to clip the rail: the colour block was cut in half and
    /// the edge toggle was simply gone, below the fold of a scroll view with
    /// hidden indicators — so there was no way to tell anything was missing, let
    /// alone reach it. **The tools and the loaded colours are the part that must
    /// never be cut**, and the palette is the part that can give ground.
    ///
    /// So there are two answers here, in order. The palette drops columns first,
    /// because every swatch it drops is one press away in the system picker. Then,
    /// if the tools *still* do not fit, the tool run alone scrolls — inside the
    /// rail, with a real scroller — while the colour block and the edge toggle
    /// keep their place at the end of it. Wrapping the whole rail was what put the
    /// colours below the fold in the first place.
    /// **Both edges, one rule.** The bottom bar used to be told it always had all
    /// fourteen palette columns and never needed to scroll, which is true of a
    /// 1400pt window and nonsense at 560 — the colour block ran straight off the
    /// right-hand end. The side rail's shedding was already written; the bottom
    /// bar simply never called it.
    @ViewBuilder
    private func scrollingRail(maxLength: CGFloat, isVertical: Bool) -> some View {
        let pairs = RailFit.swatchPairs(fitting: maxLength, isVertical: isVertical)
        let room = RailFit.toolRoom(in: maxLength, pairs: pairs, isVertical: isVertical)

        ToolRail(
            model: model,
            swatchPairs: pairs,
            toolsLength: room
        ) { model.selectTool($0) }
            .frame(
                maxWidth: isVertical ? Tokens.Rail.thickness : maxLength,
                maxHeight: isVertical ? maxLength : Tokens.Rail.thickness + 2,
                alignment: isVertical ? .top : .leading
            )
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

    /// **Three zones: what this is, what you are doing, what you do with it.**
    ///
    /// The working cluster is centred on the *window*, not spaced between its
    /// neighbours. Two flexible spacers would put it at the midpoint of whatever
    /// is left over, which means it slides every time the filename changes length
    /// — a control you have to re-find is a control you stop reaching for. Centred
    /// on the window it is in the same place in every document.
    ///
    /// Below `centredClusterMinimum` there is not room for three zones without
    /// the cluster colliding with the title, so the row falls back to the layout
    /// it had before: everything trailing, title truncating. Shedding a layout is
    /// the same trick the rail uses when it drops palette columns.
    private var titleRow: some View {
        GeometryReader { proxy in
            let fit = HeaderFit.fitting(proxy.size.width)

            ZStack {
                if fit == .full {
                    WorkingActions(model: model, fit: fit)
                        .fixedSize()
                }

                HStack(spacing: Tokens.Space.comfortable) {
                    // Clear the traffic lights.
                    Color.clear.frame(width: Tokens.Chrome.trafficLightClearance, height: 1)

                    DocumentTitle(
                        name: model.documentName,
                        isEdited: model.isEdited,
                        size: model.canvasSize
                    )
                    // The title yields before the controls do. A long filename
                    // should truncate in the middle, not push Undo off the window.
                    .layoutPriority(-1)
                    // **A ceiling, not just a priority.** Centred, the cluster is
                    // not in this stack at all — so nothing stopped a long
                    // filename being handed the whole row and drawn straight over
                    // the zoom controls, since the `HStack` is painted after the
                    // cluster. Priority decides who yields when the row is short;
                    // this is what stops the title crossing the midline when it is
                    // long.
                    .frame(maxWidth: Self.titleCeiling(fit, in: proxy.size.width), alignment: .leading)

                    Spacer(minLength: Tokens.Space.base)

                    if fit != .full {
                        WorkingActions(model: model, fit: fit).fixedSize()
                    }
                    DocumentActions(model: model, fit: fit).fixedSize()
                }
            }
            .padding(.horizontal, Tokens.Space.comfortable)
            .frame(height: Tokens.Chrome.titleReserve, alignment: .center)
        }
        .frame(height: Tokens.Chrome.titleReserve)
    }

    /// How wide the filename may be before it reaches the centred cluster.
    static func titleCeiling(_ fit: HeaderFit, in width: CGFloat) -> CGFloat {
        guard fit == .full else { return .infinity }
        return max(
            Tokens.Header.titleRoom,
            width / 2 - fit.workingWidth / 2
                - Tokens.Chrome.trafficLightClearance
                - Tokens.Space.comfortable * 3
                - Tokens.Space.base
        )
    }

    /// **One chip, for every control in the window.**
    ///
    /// Nothing draws its own. A header button's group clips to its own capsule,
    /// so a chip inside one is a chip with its bottom half cut off; a rail cell
    /// sits inside a `ScrollView`, which is worse. Every control reports where it
    /// is and the single chip is drawn out here, over everything, clipped by
    /// nothing.
    ///
    /// It used to be two layers with two rules, and the rail's was not really a
    /// rule: it offset the chip by a constant, so hovering the eyedropper — nine
    /// cells down — put the answer up beside the pencil. A tooltip that does not
    /// point at what it names is a tooltip you have to work out.
    @ViewBuilder
    private var tooltipLayer: some View {
        GeometryReader { proxy in
            if tooltips.isVisible {
                let anchor = tooltips.anchor
                let container = proxy.frame(in: .global)
                let origin = Self.tooltipOrigin(
                    beside: anchor, in: container,
                    chip: tooltipSize, rail: model.chromeEdge
                )
                Tooltip(
                    title: tooltips.title,
                    shortcut: tooltips.shortcut,
                    detail: tooltips.detail
                )
                .fixedSize()
                .background {
                    GeometryReader { chip in
                        Color.clear
                            .onAppear { tooltipSize = chip.size }
                            .onChange(of: chip.size) { _, new in tooltipSize = new }
                    }
                }
                // `.topLeading`, not `.position`: `position` centres on a point,
                // so a two-line chip and a one-line chip pinned to the same y
                // still start at different heights. Pinning a corner is what
                // "one fixed line" actually means.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .offset(x: origin.x, y: origin.y)
                // **Measured before it is seen.** `tooltipSize` starts at zero and
                // now feeds the *y* axis too: above a bottom bar the origin is
                // `height − chip.height`, so an unmeasured chip pinned its top-left
                // to the top edge of the bar and then jumped its own height — about
                // 60pt — the instant the measurement landed. It has to be laid out
                // to be measured, so it is laid out invisibly for that one frame
                // rather than skipped, which would measure nothing forever.
                .opacity(tooltipSize == .zero ? 0 : 1)
                .allowsHitTesting(false)
            }
        }
    }

    /// The one line every header chip hangs from: clear of the header row, with
    /// the same gap the header itself keeps from the top of the window.
    static let tooltipTop: CGFloat = Tokens.Chrome.titleReserve - Tokens.Space.tight

    /// The chip's top-left corner, given where the control is.
    ///
    /// **Two placements, one rule.** The chip's near edge sits on a fixed line
    /// beside the chrome it explains — one line under the header, one column
    /// clear of the rail — and it slides *along* that line to follow the control.
    /// Reading across the header moves the answer sideways only; reading down the
    /// rail moves it up and down only. The text is never somewhere new.
    ///
    /// Which line it hangs from is read off the anchor rather than passed in by
    /// every call site: the header band is the only chrome above the artwork, so
    /// a control inside it is a header control and everything else is the rail's.
    static func tooltipOrigin(
        beside anchor: CGRect, in container: CGRect,
        chip: CGSize, rail edge: EditorModel.ChromeEdge
    ) -> CGPoint {
        let alongTop = tooltipLeading(under: anchor, in: container, chipWidth: chip.width)

        guard anchor.midY - container.minY >= Tokens.Chrome.titleReserve else {
            return CGPoint(x: alongTop, y: tooltipTop)
        }

        guard edge.isVertical else {
            return CGPoint(
                x: alongTop,
                y: container.height - Tokens.Chrome.railInset
                    - Tokens.Rail.thickness - Tokens.Space.snug - chip.height
            )
        }

        return CGPoint(
            x: Tokens.Chrome.railInset + Tokens.Rail.thickness + Tokens.Space.snug,
            y: slid(
                toward: anchor.midY - container.minY,
                extent: chip.height,
                within: container.height,
                // Clear of the header at one end and of the window at the other:
                // the two things a chip beside a tall rail can run into.
                leading: Tokens.Chrome.titleReserve,
                trailing: Tokens.Space.safeInset
            )
        )
    }

    /// Where the header's chip starts: centred under the control, unless that
    /// would hang it off an edge of the window.
    ///
    /// The trailing group is three glyphs from the right edge and its chips carry
    /// a line of explanation, so centring on the glyph alone puts half the
    /// sentence outside the window — a tooltip you cannot read is worse than no
    /// tooltip, because it also covers the artwork.
    ///
    /// Returns a leading edge rather than a centre because the chip is pinned by
    /// its top-left corner, so that its top edge can stay on one line whatever
    /// height it happens to be.
    static func tooltipLeading(under anchor: CGRect, in container: CGRect, chipWidth: CGFloat) -> CGFloat {
        slid(
            toward: anchor.midX - container.minX,
            extent: chipWidth,
            within: container.width,
            leading: Tokens.Space.base,
            trailing: Tokens.Space.base
        )
    }

    /// Centre `extent` on `wanted`, then pull it back inside the window.
    ///
    /// One function for both axes, because "point at the control, but stay on
    /// screen" is one idea and it had drifted into being two — the rail's version
    /// simply did not clamp, which is how a chip beside the last tool in a short
    /// window ended up below the bottom of it.
    private static func slid(
        toward wanted: CGFloat, extent: CGFloat, within: CGFloat,
        leading: CGFloat, trailing: CGFloat
    ) -> CGFloat {
        let low = leading
        let high = within - trailing - extent
        // Something larger than the room it has cannot be kept inside it; centre
        // it and let both ends run out rather than pinning one edge and cutting
        // the whole sentence off the other.
        guard high > low else { return (within - extent) / 2 }
        return min(max(wanted - extent / 2, low), high)
    }

    private var readOutRow: some View {
        PointerReadout(model: model)
            .padding(.trailing, Tokens.Space.comfortable)
            .padding(.bottom, model.chromeEdge.isVertical
                ? Tokens.Space.snug
                : Tokens.Space.snug + Tokens.Rail.thickness + Tokens.Space.base)
    }
}
