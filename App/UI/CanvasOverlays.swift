import PaintKit
import SwiftUI
import UniformTypeIdentifiers

/// The filename, and beneath it what the file currently is.
///
/// **No card around it.** A bordered chip made the title look like a control
/// you could press, competed with the actual controls at the other end of the
/// header, and drew a box around the emptiest part of the window. Preview,
/// Pages and Keynote all set a document title as plain text with a quiet
/// subtitle under it, and that is right: the title is a label, and a label
/// with a border is a button that does nothing.
///
/// The scrim behind the titlebar is what keeps it legible over artwork, so the
/// chip was never carrying that job anyway.
struct DocumentTitle: View {
    let name: String
    let isEdited: Bool
    let size: (width: Int, height: Int)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary.opacity(Tokens.Ink.strong))
                .lineLimit(1)
                .truncationMode(.middle)

            // The subtitle carries what the document *is*, which is the thing
            // that used to sit in a floating strip over the bottom-right of
            // the artwork.
            // `muted`, which the token file defines as "a value or read-out
            // beside a label" — and this is the document's dimensions beside its
            // name. It was `faint`, the hint step, and at 10.5pt over the light
            // appearance's grey that measured about 2.4:1; `muted` measures about
            // 4:1 light and 6:1 dark. `HeaderContrastTests` keeps it above the
            // 3:1 floor in both appearances.
            Text(subtitle)
                .font(.system(size: 10.5))
                .foregroundStyle(.primary.opacity(Tokens.Ink.muted))
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(subtitle)")
    }

    private var subtitle: String {
        let dimensions = "\(size.width.formatted()) × \(size.height.formatted())"
        return isEdited ? "\(dimensions) · Edited" : dimensions
    }
}

/// A run of related controls sharing one capsule.
///
/// Grouping is the header's whole information architecture: six loose buttons
/// in a row is six decisions, three groups of two is three. The material is the
/// same one the rail uses, so a header cluster and a toolbar read as the same
/// kind of surface.
struct HeaderGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 1) {
            content
        }
        .padding(.horizontal, 3)
        .frame(height: Tokens.Size.headerControl)
        .chromeSurface(cornerRadius: Tokens.Radius.chip, elevated: false)
    }
}

/// One button inside a header group.
///
/// **The tooltip is the app's own chip, not the system's.** The header is nine
/// unlabelled glyphs, and `.help` waits about a second before naming any of
/// them — long enough that people click one to find out what it does. Two of
/// them, the paste clipboard and the drag-out handle, were reported as
/// unidentifiable for exactly that reason. The rail already had the fast chip;
/// this is the header joining it.
struct HeaderButton: View {
    let symbol: String
    let title: String
    var shortcut: String?
    /// One line under the title, for the buttons whose glyph cannot carry the
    /// whole idea on its own.
    var detail: String?
    var isEnabled: Bool = true
    let action: () -> Void

    @Environment(TooltipController.self) private var tooltips
    @State private var isHovering = false
    @State private var frame: CGRect = .zero

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 26)
                .foregroundStyle(.primary.opacity(isEnabled ? Tokens.Ink.regular : Tokens.Ink.disabled))
                .background {
                    RoundedRectangle(cornerRadius: Tokens.Radius.control, style: .continuous)
                        .fill(.primary.opacity(isHovering && isEnabled ? Tokens.Fill.hover : 0))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .trackedForTooltip($frame)
        .onHover { hovering in
            isHovering = hovering
            // Named even while disabled. "Nothing to paste" is the most useful
            // thing the button can say, and it is dim exactly when it needs to
            // say it.
            hovering
                ? tooltips.hover(
                    key: "header-\(title)", title: title,
                    shortcut: shortcut, detail: detail, anchor: frame
                )
                : tooltips.endHover(key: "header-\(title)")
        }
        .animation(Tokens.Motion.micro, value: isHovering)
        .accessibilityLabel(title)
    }
}

/// Report a control's position on screen, so the one shared tooltip chip can sit
/// under the control that asked for it.
///
/// Screen coordinates rather than a named space: the header lives in an overlay
/// inside a `ZStack` that also holds the canvas, and the chip is drawn by a
/// different branch of that stack.
extension View {
    func trackedForTooltip(_ frame: Binding<CGRect>) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { frame.wrappedValue = proxy.frame(in: .global) }
                    .onChange(of: proxy.frame(in: .global)) { _, new in
                        frame.wrappedValue = new
                    }
            }
        }
    }
}

/// **Drag this into Slack, Mail or the Finder.** No save panel, no file left on
/// the Desktop.
///
/// It sits with cut, copy and paste because it is the same job — getting the
/// image out — and it is *in the header* rather than tucked beside the canvas
/// deliberately. Every app that has this hides it: Shottr's is a bare file icon
/// between two toolbar buttons and people who wanted the feature looked straight
/// past it, then asked for it in the same thread. The demand is not for the
/// capability, it is for an affordance you can find.
///
/// Not a `Button`. A draggable button reads as broken — press, nothing happens,
/// because the gesture it wants is a drag. The grabber glyph and the cursor are
/// the whole instruction.
struct DragOutHandle: View {
    @Bindable var model: EditorModel

    @Environment(TooltipController.self) private var tooltips
    @State private var isHovering = false
    @State private var frame: CGRect = .zero

    var body: some View {
        // `photo.on.rectangle.angled`, not an up-arrow. The first version used
        // `square.and.arrow.up.on.square`, which is a share glyph with a box
        // behind it — three cells from the real Share button and nearly
        // indistinguishable from it at 12pt. This reads as *the image, as an
        // object you can pick up*, which is what a drag proxy should look like.
        // Not `hand.draw` either: a hand holding a pen means "draw" in a paint
        // app.
        Image(systemName: "photo.on.rectangle.angled")
            .font(.system(size: 12, weight: .medium))
            .frame(width: 26, height: 26)
            .foregroundStyle(.primary.opacity(Tokens.Ink.regular))
            .background {
                RoundedRectangle(cornerRadius: Tokens.Radius.control, style: .continuous)
                    .fill(.primary.opacity(isHovering ? Tokens.Fill.hover : 0))
            }
            .contentShape(Rectangle())
            .trackedForTooltip($frame)
            .onHover { hovering in
                isHovering = hovering
                // The chip names it in 300ms rather than the system's second,
                // because this is the glyph people reported not recognising.
                hovering
                    ? tooltips.hover(
                        key: "header-drag", title: "Drag image out",
                        shortcut: nil,
                        detail: "Pick the picture up and drop it into Slack, Mail or the Finder",
                        anchor: frame
                    )
                    : tooltips.endHover(key: "header-drag")
                // A grab cursor is the other half of the instruction: it says
                // "drag me" before anyone has waited for any tooltip at all.
                if hovering { NSCursor.openHand.push() } else { NSCursor.pop() }
            }
            .animation(Tokens.Motion.micro, value: isHovering)
            // The PNG is encoded when a drag actually begins, not on every render
            // of the header: the header follows `revision`, and a full-canvas
            // encode per hover or per resize frame was the cost of having the
            // bytes ready for a drag that mostly never came.
            .overlay { DragOutSurface(model: model) }
            .accessibilityLabel("Drag image out")
    }
}

/// The mouse half of the drag handle, in AppKit, so the window stops coming
/// with the picture.
///
/// **The bug this fixes.** The header sits inside the titlebar band of a
/// `.fullSizeContentView` window, and AppKit lets a drag that begins on any view
/// whose `mouseDownCanMoveWindow` is true move the whole window. SwiftUI's
/// hosting view says true, so dragging the handle did both things at once: the
/// image came out *and* the window slid across the desk under it. The window was
/// already `isMovableByWindowBackground = false`; that flag governs the
/// background, not the titlebar band, which is why it looked like it should
/// already be handled.
///
/// `mouseDownCanMoveWindow` is asked of the view that the click actually lands
/// on, and SwiftUI's drawn content is not a view — so saying no requires a real
/// `NSView` at that spot, which then has to be the thing that starts the drag as
/// well. That is this. The glyph, the hover fill and the cursor stay in SwiftUI
/// underneath; this is a pane of glass over them that owns the mouse.
///
/// **And the second half of it (issue #28).** That answer shipped in 0.19.0 and
/// a report against 0.19.0 on macOS 26.5 said the window still came along. The
/// flag is a request the titlebar honours *when the press reaches this view*: a
/// press on a window that is not key does not reach any view unless the view
/// accepts first mouse, and a picture is dragged out of a window that is behind
/// Slack more often than out of the front one. So the surface accepts the first
/// click — and, belt to those braces, tells the window at its own level that it
/// cannot be moved at all for as long as the pointer is over the handle. A lock
/// the frame checks before hit-testing anything does not depend on which view
/// a given macOS decides the press landed on.
struct DragOutSurface: NSViewRepresentable {
    let model: EditorModel

    func makeNSView(context: Context) -> DragSurfaceView { DragSurfaceView() }

    func updateNSView(_ view: DragSurfaceView, context: Context) {
        view.model = model
    }

    final class DragSurfaceView: NSView, NSDraggingSource {
        /// Asked for the picture when a drag begins, so the encode happens once
        /// per drag instead of once per render.
        weak var model: EditorModel?
        /// Shared: one promise is written at a time and the work is a single
        /// `Data.write`.
        ///
        /// `nonisolated`, along with the two keys below, because they are read
        /// from the promise delegate — which runs on that queue, not on the main
        /// actor. A `static let` inside a `@MainActor` type is main-actor
        /// isolated by inheritance, and constants are exactly the case where that
        /// buys nothing: there is no mutation to protect.
        fileprivate nonisolated static let promiseQueue = OperationQueue()

        /// The whole point of the file.
        override var mouseDownCanMoveWindow: Bool { false }

        /// A drag proxy takes the first click. Without this, a press on the handle
        /// of a window that is not key only activates the window, and the press
        /// belongs to the titlebar — which moves the window with it.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        /// The window-level lock. `activeAlways`, because the case it exists for is
        /// a window that is not the active one.
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas { removeTrackingArea(area) }
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            ))
        }

        override func mouseEntered(with event: NSEvent) { window?.isMovable = false }
        override func mouseExited(with event: NSEvent) { window?.isMovable = true }

        /// Restored whenever the gesture that needed the lock is over, and
        /// re-armed if the pointer is still on the handle — a press without a
        /// drag, or a drop back onto the handle itself, must not leave the window
        /// stuck either way.
        func releaseLock(pointerInWindow point: NSPoint?) {
            guard let window else { return }
            let inside = point.map { bounds.contains(convert($0, from: nil)) } ?? false
            window.isMovable = !inside
        }

        override func mouseUp(with event: NSEvent) {
            releaseLock(pointerInWindow: event.locationInWindow)
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            // Leaving a window must leave it movable.
            window?.isMovable = true
            super.viewWillMove(toWindow: newWindow)
        }

        override func mouseDown(with event: NSEvent) {
            // Swallowed deliberately. AppKit only offers `mouseDragged` to a
            // view that accepted the `mouseDown`, and passing this one on is
            // what let the titlebar claim the gesture in the first place.
        }

        override func mouseDragged(with event: NSEvent) {
            guard let payload = model?.draggableImage() else { return }
            guard let image = NSImage(data: payload.data) else { return }

            // A **file promise**, which is what carries the name across a
            // sandbox boundary. Writing a temp file and dragging its URL is
            // shorter and lands the receiver a path it has no permission to
            // read; putting raw PNG bytes on the pasteboard loses the name and
            // arrives in Mail as "Image". A promise lets the receiver nominate
            // the destination and asks us to write into it.
            let provider = NSFilePromiseProvider(fileType: UTType.png.identifier, delegate: self)
            // **The bytes travel on the provider, not on this view.** The promise
            // is fulfilled whenever the receiver gets round to it, on a background
            // queue, and the delegate methods are nonisolated — reading a property
            // of a `@MainActor` view from them does not compile under Swift 6
            // strict concurrency, and would be the wrong answer anyway: by then
            // the canvas may have moved on, and what lands in Mail should be the
            // picture that was picked up.
            provider.userInfo = [Self.nameKey: payload.name, Self.dataKey: payload.data] as [String: any Sendable]
            let dragItem = NSDraggingItem(pasteboardWriter: provider)
            // The drag image is the picture, at a size that reads as a proxy
            // rather than as a second window: big enough to recognise, small
            // enough to see the drop target under it.
            let side: CGFloat = 128
            let scale = min(side / max(image.size.width, 1), side / max(image.size.height, 1), 1)
            let dragged = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            let origin = NSPoint(
                x: bounds.midX - dragged.width / 2,
                y: bounds.midY - dragged.height / 2
            )
            dragItem.setDraggingFrame(NSRect(origin: origin, size: dragged), contents: image)

            beginDraggingSession(with: [dragItem], event: event, source: self)
        }

        func draggingSession(
            _ session: NSDraggingSession,
            sourceOperationMaskFor context: NSDraggingContext
        ) -> NSDragOperation {
            .copy
        }

        func draggingSession(
            _ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation
        ) {
            releaseLock(pointerInWindow: window?.convertPoint(fromScreen: screenPoint))
        }

        fileprivate nonisolated static let nameKey = "itspaint.name"
        fileprivate nonisolated static let dataKey = "itspaint.data"
    }
}

/// Writing the promised file, off the main thread, from the bytes the drag was
/// started with.
///
/// Everything these methods need is on the provider's `userInfo`, put there when
/// the drag began. They are nonisolated and run on a background queue, so they
/// cannot read the view's own state — and should not: the promise is fulfilled
/// whenever the receiver gets round to it, and what lands in Mail should be the
/// picture that was picked up rather than whatever the canvas holds by then.
extension DragOutSurface.DragSurfaceView: NSFilePromiseProviderDelegate {
    // Read inline, not through a shared helper. A helper returning
    // `[String: Any]` is a non-Sendable value crossing an isolation boundary,
    // which Swift 6 refuses — and it is refusing something real: the dictionary
    // would be reachable from both queues at once. Pulling the one Sendable
    // value out on the spot leaves nothing to share.
    nonisolated func filePromiseProvider(
        _ provider: NSFilePromiseProvider, fileNameForType fileType: String
    ) -> String {
        let info = provider.userInfo as? [String: any Sendable]
        return info?[Self.nameKey] as? String ?? "Image.png"
    }

    nonisolated func filePromiseProvider(
        _ provider: NSFilePromiseProvider,
        writePromiseTo url: URL,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let info = provider.userInfo as? [String: any Sendable]
        guard let data = info?[Self.dataKey] as? Data else {
            completionHandler(CocoaError(.fileNoSuchFile)); return
        }
        do {
            try data.write(to: url)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }

    nonisolated func operationQueue(for provider: NSFilePromiseProvider) -> OperationQueue {
        Self.promiseQueue
    }
}

/// Share, routed through the responder chain to the document.
///
/// An `NSViewRepresentable` rather than a SwiftUI `ShareLink` because the sheet
/// has to be anchored to *this* button — `ShareLink` anchors to whatever SwiftUI
/// decides, and a share popover that opens at the far corner of the window
/// looks like it belongs to something else.
struct ShareButton: NSViewRepresentable {
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.image = NSImage(
            systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Share"
        )
        button.contentTintColor = .labelColor
        button.toolTip = "Share…"
        button.setAccessibilityLabel("Share")
        // nil target: the document supplies `shareImage(_:)`, exactly like the
        // File menu item, so the two can never diverge.
        button.target = nil
        button.action = #selector(AppCommands.shareImage(_:))
        button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
        CGSize(width: 26, height: 26)
    }
}

/// The zoom percentage, which is also the way back to 100%.
///
/// A bare `Text` with a tap gesture was an invisible affordance: nobody clicks a
/// label. This hovers and presses like the buttons on either side of it, and goes
/// quiet at 100% because at that point pressing it does nothing.
struct ZoomReadout: View {
    let label: String
    let isActualSize: Bool
    let action: () -> Void

    @Environment(TooltipController.self) private var tooltips
    @State private var isHovering = false
    @State private var frame: CGRect = .zero

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.primary.opacity(isActualSize ? Tokens.Ink.muted : Tokens.Ink.regular))
                .frame(minWidth: 40)
                .frame(height: 26)
                .background {
                    RoundedRectangle(cornerRadius: Tokens.Radius.control, style: .continuous)
                        .fill(.primary.opacity(isHovering && !isActualSize ? Tokens.Fill.hover : 0))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isActualSize)
        .trackedForTooltip($frame)
        .onHover { hovering in
            isHovering = hovering
            // The same chip its neighbours use. Two glyphs with the fast tooltip
            // and the control between them on the system's slow one is the kind
            // of seam you notice without being able to name.
            hovering
                ? tooltips.hover(
                    key: "header-zoom",
                    title: isActualSize ? "Actual size" : "Back to actual size",
                    shortcut: "⌘0",
                    detail: isActualSize ? "Already at 100%" : nil,
                    anchor: frame
                )
                : tooltips.endHover(key: "header-zoom")
        }
        .animation(Tokens.Motion.micro, value: isHovering)
        .accessibilityLabel("Zoom \(label), press for actual size")
    }
}

/// Which page of a PDF is on the canvas, and the way to another one.
///
/// **Only for documents that have pages.** A screenshot does not, and telling
/// someone they are on page one of one is noise in the one place the window is
/// supposed to say what they are looking at.
///
/// Turning a page saves the current one back into the file first, so a signature
/// is never lost by looking at the page after it. Undo does not follow — the
/// canvas becomes a genuinely different image — and the chip below the title
/// keeps saying "Edited" until the document is saved, which is the honest state.
struct PageControl: View {
    @Bindable var model: EditorModel

    var body: some View {
        if let page = model.pdfPage {
            HeaderGroup {
                HeaderButton(
                    symbol: "chevron.left", title: "Previous page",
                    isEnabled: page.index > 0
                ) { model.turnToPage(page.index - 1) }

                Text("Page \(page.index + 1) of \(page.count)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.primary.opacity(Tokens.Ink.regular))
                    .padding(.horizontal, Tokens.Space.tight)
                    .fixedSize()

                HeaderButton(
                    symbol: "chevron.right", title: "Next page",
                    isEnabled: page.index + 1 < page.count
                ) { model.turnToPage(page.index + 1) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Page \(page.index + 1) of \(page.count)")
        }
    }
}

/// A hairline between two runs inside one group.
struct HeaderDivider: View {
    var body: some View {
        Rectangle()
            .fill(.primary.opacity(Tokens.Fill.separator))
            .frame(width: 1, height: 14)
            .padding(.horizontal, 2)
    }
}

/// A scrim behind the traffic lights.
///
/// The titlebar is transparent so artwork reaches the top edge; without this,
/// white artwork would swallow the window controls. It fades out rather than
/// ending on a hard line, so it reads as light falling off rather than a bar.
struct TitlebarScrim: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // Black falling off in dark appearance; the same rule inverted in light.
        // One black scrim for both was issue #29: over the light appearance's
        // pale grey it painted the top 64pt of every window a muddy mid-grey, and
        // sat the title's black ink on the darkest band in the window.
        let ink: Color = colorScheme == .dark ? .black : .white
        LinearGradient(
            colors: [ink.opacity(0.34), ink.opacity(0)],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 64)
        .allowsHitTesting(false)
    }
}

/// The header's control clusters: history, zoom, and the document actions.
///
/// Three groups rather than one row of six buttons, because the groups are the
/// hierarchy — undo and redo belong together, the zoom controls belong
/// together, and neither belongs with Duplicate.
///
/// **The zoom controls live here, not over the artwork.** They used to float in
/// a strip at the bottom-right, which is exactly where the interesting part of
/// a screenshot usually is: you would be marking something up and the readout
/// would be sitting on top of it. The header had unused space and these have a
/// natural home in it.
/// What you do *to* the document: the clipboard, history, and zoom.
///
/// **This is what the middle of the header is for.** The title sat on the left,
/// every control sat on the right, and between them ran about 1,100pt of nothing
/// on a normal window — the emptiest band in the app, directly above the
/// artwork. Preview, Keynote and Xcode all put the controls you actually work
/// with in the *centre* of the titlebar; the ones you reach for at the end of a
/// session go to the far edge.
///
/// Cut, copy and paste live here rather than in the tool rail because they are
/// not tools. The rail is a list of things that make marks; the clipboard acts on
/// the document, like undo and zoom, and grouping it with them is what keeps the
/// rail a short list you can scan.
/// **What a window of a given width can carry, and what it drops first.**
///
/// The rail sheds palette columns before it scrolls, for the reason it states: a
/// control below the fold of an indicator-less scroll view is a control nobody
/// can tell is missing. The header had no ladder at all — it simply ran off the
/// right edge — and `DrawingDocument.minimumContentSize` is 560pt against a row
/// that needs 647pt with *no filename in it*. The app shipped a window its own
/// header could not fit.
///
/// Every rung sheds a run whose commands have another door: a chord, a menu-bar
/// item, or a bar this app already puts on screen. Nothing that is the *only* way
/// to do something is ever shed — which inverts the obvious answer. Cut, copy and
/// paste go before the drag-out handle, because ⌘X/⌘C/⌘V are three chords every
/// Mac already has and `SelectionActions` restates two of them on screen the
/// moment there is a selection, while the drag-out handle has no chord and no menu
/// item anywhere. Undo and redo, the zoom read-out, Share and the filename are
/// never shed.
///
/// Declaration order is the ladder, widest first, so a window that has grown
/// climbs back to the rung it fell from.
enum HeaderFit: CaseIterable {
    /// `noMenus` is the rung *below* the window floor, and that is its whole job:
    /// `dragOutOnly` fits 560pt with one point to spare, which is not a margin. It
    /// is what the ladder falls to if the window floor ever drops or a group ever
    /// gains a cell, so the failure mode is a shed control rather than a clipped
    /// one.
    case full, trailing, zoomReadoutOnly, shareOnly, dragOutOnly, noMenus

    var showsZoomSteppers: Bool { self == .full || self == .trailing }
    var showsLastActions: Bool { showsZoomSteppers || self == .zoomReadoutOnly }
    var showsClipboardRun: Bool { self != .dragOutOnly && self != .noMenus }
    var showsMenus: Bool { self != .noMenus }

    var workingWidth: CGFloat {
        let groups = [
            showsClipboardRun ? Tokens.Header.clipboard : Tokens.Header.dragOnly,
            Tokens.Header.history,
            showsMenus ? Tokens.Header.menus : nil,
            showsZoomSteppers ? Tokens.Header.zoom : Tokens.Header.zoomOnly,
        ].compactMap { $0 }
        return groups.reduce(0, +) + CGFloat(groups.count - 1) * Tokens.Space.tight
    }

    var documentWidth: CGFloat {
        showsLastActions ? Tokens.Header.document : Tokens.Header.shareOnly
    }

    /// The narrowest window this arrangement fits, with the filename still
    /// getting `Tokens.Header.titleRoom` of it.
    var minimumWindow: CGFloat {
        guard self == .full else {
            return Tokens.Header.surround + workingWidth + documentWidth + Tokens.Header.titleRoom
        }
        // Measured about the window's midline, because the centred cluster is
        // centred on the *window* rather than between its neighbours: everything
        // the title needs on its side of the midline is doubled.
        return (Tokens.Space.comfortable * 3 + Tokens.Chrome.trafficLightClearance
            + Tokens.Header.titleRoom + Tokens.Space.base + workingWidth / 2) * 2
    }

    /// The widest arrangement a window of `width` can carry.
    ///
    /// The last rung is returned whether it fits or not: there is nothing below
    /// it, and clipping is the one outcome this ladder exists to prevent.
    static func fitting(_ width: CGFloat) -> HeaderFit {
        allCases.first { width >= $0.minimumWindow } ?? .noMenus
    }
}

struct WorkingActions: View {
    @Bindable var model: EditorModel
    var fit: HeaderFit = .full

    var body: some View {
        // Undo lives in the UI-free engine, so its computed flags are not
        // observable on their own. Revision makes this strip follow each edit
        // and replay instead of leaving apparently disabled controls behind.
        let _ = model.revision

        HStack(spacing: Tokens.Space.tight) {
            HeaderGroup {
                if fit.showsClipboardRun {
                HeaderButton(
                    symbol: "scissors", title: "Cut",
                    shortcut: "⌘X", isEnabled: model.hasSelection
                ) { model.cutSelection() }
                // **Copy always copies something.** It used to go dim with
                // nothing selected, which reads as "copying is unavailable" when
                // the obvious thing to copy — the whole picture — is right
                // there. With a selection it copies the selection; without one it
                // copies the image, which is what ⌘C means in every viewer
                // people arrive from.
                HeaderButton(
                    symbol: "square.on.square",
                    title: model.hasSelection ? "Copy selection" : "Copy image",
                    shortcut: "⌘C",
                    detail: "Puts it on the clipboard, ready to paste anywhere"
                ) {
                    model.hasSelection ? model.copySelection() : model.copyWholeImage()
                }
                HeaderButton(
                    // `clipboard` when there is something on it, and the same
                    // glyph without its page when there is not — so the button
                    // says *why* it is unavailable rather than just being dim.
                    symbol: model.canPaste ? "doc.on.clipboard" : "clipboard",
                    title: model.canPaste ? "Paste image" : "Nothing to paste",
                    shortcut: "⌘V",
                    detail: model.canPaste
                        ? "Drops the clipboard onto the canvas, still movable"
                        : "Copy an image somewhere first",
                    isEnabled: model.canPaste
                ) { model.paste() }
                }
                // Never shed: the one control in this row with no chord and no
                // menu item. Everything above it is ⌘X/⌘C/⌘V.
                DragOutHandle(model: model)
            }

            HeaderGroup {
                HeaderButton(
                    symbol: "arrow.uturn.backward", title: "Undo",
                    shortcut: "⌘Z", isEnabled: model.canUndo
                ) { model.undo() }
                HeaderButton(
                    symbol: "arrow.uturn.forward", title: "Redo",
                    shortcut: "⇧⌘Z", isEnabled: model.canRedo
                ) { model.redo() }
            }

            // What the picture is, and how you are looking at it. Between the
            // clipboard and the history because that is the order of the work:
            // get something in, change it, look at it, undo it.
            if fit.showsMenus {
                HeaderGroup {
                    ImageMenu(model: model)
                    ViewMenu(model: model)
                }
            }

            HeaderGroup {
                if fit.showsZoomSteppers {
                HeaderButton(
                    symbol: "minus", title: "Zoom out", shortcut: "⌘−",
                    isEnabled: model.zoom > (EditorModel.zoomSteps.first ?? 1)
                ) { model.zoomOut() }
                }

                // **The percentage is the button.** There used to be a separate
                // `arrow.up.left.and.arrow.down.right` cell for Actual Size,
                // behind a divider, while tapping this label did exactly the
                // same thing. Two controls for one action, and the glyph on the
                // explicit one is the one every other Mac app uses for *fit* or
                // *full screen*, so the pair managed to be both redundant and
                // misleading. What is left is a real button whose label is the
                // current zoom and whose action is 100%.
                // Never shed: the only place the window states its zoom, and the
                // Actual Size button. The two steppers either side of it have
                // ⌘+, ⌘−, pinch, ⌘-scroll and the View menu.
                ZoomReadout(label: zoomLabel, isActualSize: model.zoom == 1) {
                    model.hasUserZoomed = true
                    model.zoom = 1
                }

                if fit.showsZoomSteppers {
                HeaderButton(
                    symbol: "plus", title: "Zoom in", shortcut: "⌘+",
                    isEnabled: model.zoom < (EditorModel.zoomSteps.last ?? 1)
                ) { model.zoomIn() }
                }
            }
        }
    }

    private var zoomLabel: String {
        let percent = model.zoom * 100
        return percent < 100 ? String(format: "%.0f%%", percent) : "\(Int(percent))%"
    }
}

/// What you do *with* the finished thing, at the far edge.
///
/// Separated from the working cluster on purpose. Share and Duplicate are the
/// last two actions of a session, not part of the loop — sitting them beside Undo
/// gave a destructive-ish and a terminal action the same weight as the one you
/// press forty times an hour.
struct DocumentActions: View {
    @Bindable var model: EditorModel
    var fit: HeaderFit = .full

    @Environment(TooltipController.self) private var tooltips
    @State private var shareFrame: CGRect = .zero

    var body: some View {
        HeaderGroup {
            if fit.showsLastActions {
            // **Signing has a button now.** It lived only in the Tools menu
            // under ⌃⌘S — a chord nothing else in the app uses — which made the
            // one feature nobody would guess at the one feature the window never
            // mentioned. It sits with Share rather than in the rail because it
            // is not a tool: you reach for it once per document, next to the
            // other things you do to a finished document.
            HeaderButton(
                symbol: "signature", title: "Signature",
                shortcut: "⌃⌘S",
                detail: "Sign here, or drop in a signature you have already saved"
            ) {
                model.isSignatureSheetPresented = true
            }

            HeaderDivider()
            }

            // Share is in the File menu, but a markup app's whole purpose is
            // getting the result to someone else — burying its most common last
            // step one menu down is the wrong emphasis.
            //
            // The chip is layered over the AppKit button rather than replacing
            // its own `toolTip`: hover tracking across a representable is not
            // guaranteed, and the system tooltip underneath is the floor if it
            // does not fire.
            ShareButton()
                .trackedForTooltip($shareFrame)
                .onHover { hovering in
                    hovering
                        ? tooltips.hover(
                            key: "header-share", title: "Share",
                            shortcut: nil,
                            detail: "AirDrop, Mail, Messages — as a named file, not \"Image\"",
                            anchor: shareFrame
                        )
                        : tooltips.endHover(key: "header-share")
                }

            // Everything after Share is the last two minutes of a session, and
            // every one of them has a chord and a menu-bar item. Share does not
            // go: getting the result to someone else is what this app is for.
            if fit.showsLastActions {
            HeaderButton(
                symbol: "doc.on.doc", title: "Duplicate", shortcut: "⇧⌘S",
                detail: "Opens a copy in a new window"
            ) {
                model.isDuplicateConfirmationPresented = true
            }

            HeaderDivider()

            // **A question mark in the window, not only in the menu bar.**
            //
            // The chrome is thirteen unlabelled glyphs by design, and the answer
            // to "what does this one do" lived under Help ▸ ItsPaint Help — at
            // the top of the screen, in the menu somebody has already decided is
            // not for them. It opens the guide, which is written to be read by
            // someone who has the app open beside it.
            HeaderButton(
                symbol: "questionmark.circle", title: "Guide",
                shortcut: "⌘?",
                detail: "Every tool, what it is for, and the drag that makes it work"
            ) {
                AppCommandsBridge.openGuide()
            }
            }
        }
    }
}

/// Opening the guide from a SwiftUI button.
///
/// The menu bar routes through the responder chain to the document, which is
/// where every other command lives. A SwiftUI `Button` has no sender to route
/// with, so it asks the application delegate directly — the same delegate the
/// chain would have reached, and the same URL.
@MainActor
enum AppCommandsBridge {
    static func openGuide() {
        NSApp.sendAction(#selector(AppCommands.openHelp(_:)), to: nil, from: nil)
    }
}

/// What to do with something that has just been pasted or lifted.
///
/// Floating content is a decision the app has already made for you — click
/// anywhere and it lands. That is the right default and it stays the default,
/// but it is invisible: nothing said the pixels were still movable, that the
/// canvas had grown to hold them, or that cropping to them was one click away.
/// People discovered Crop to Selection and got told to select something first.
///
/// So this states the choice and then gets out of the way. Placing is the
/// primary action because it is what clicking off already does; the bar is a
/// shortcut to the two things that are *not* obvious.
struct FloatingActions: View {
    @Bindable var model: EditorModel

    var body: some View {
        // Revision, so the size read-out follows a drag or a resize.
        let _ = model.revision

        HStack(spacing: Tokens.Space.tight) {
            Image(systemName: "square.dashed.inset.filled")
                .font(.system(size: 11))
                .foregroundStyle(.primary.opacity(Tokens.Ink.muted))

            if let size = model.selectionSize {
                Text("\(size.width) × \(size.height)")
                    .font(Tokens.Text.pillValue)
                    .foregroundStyle(.primary.opacity(Tokens.Ink.muted))
            }

            HeaderDivider()

            // "Crop to it" wanted an antecedent the bar never gave it. The bar
            // only exists while something is floating, so there is exactly one
            // thing to crop to and the shorter word is the unambiguous one.
            action("Place", symbol: "checkmark", role: .primary) { model.placeFloating() }
            action("Crop", symbol: "crop") { model.cropToSelection() }
            // Discard throws the paste away. Styled like its neighbours it was
            // one slip from Crop, which is reversible, at identical weight.
            action("Discard", symbol: "xmark", role: .destructive) { model.discardFloating() }
        }
        .padding(.horizontal, Tokens.Space.base)
        .frame(height: Tokens.Size.headerControl)
        .chromeSurface(cornerRadius: Tokens.Radius.chip)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pasted content. Place, crop to it, or discard.")
    }

    /// What one action in the bar is for, which is what it looks like.
    ///
    /// Three actions at one weight is three equally-good answers. They are not:
    /// placing is what clicking off already does, cropping is reversible, and
    /// discarding throws the paste away.
    private enum Role {
        case primary, neutral, destructive
    }

    private func action(
        _ title: String, symbol: String, role: Role = .neutral,
        perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                Text(title).font(.system(size: 11.5))
            }
            .foregroundStyle(foreground(role))
            .padding(.horizontal, Tokens.Space.base)
            .frame(height: 22)
            .background {
                RoundedRectangle(cornerRadius: Tokens.Radius.control, style: .continuous)
                    .fill(background(role))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }

    private func foreground(_ role: Role) -> AnyShapeStyle {
        switch role {
        case .primary: AnyShapeStyle(Color.white)
        // Not a red fill: the bar is small and a filled red button beside a
        // filled accent one is two things shouting. A red label on the same
        // tonal cell as Crop is enough to break the tie.
        case .destructive: AnyShapeStyle(Color.red)
        case .neutral: AnyShapeStyle(.primary.opacity(Tokens.Ink.regular))
        }
    }

    private func background(_ role: Role) -> AnyShapeStyle {
        switch role {
        case .primary: AnyShapeStyle(Color.accentColor)
        case .destructive, .neutral: AnyShapeStyle(.primary.opacity(Tokens.Fill.track))
        }
    }
}

/// A header button that opens a menu instead of doing something.
///
/// Same cell, same hover fill, same chip as every other header control — the
/// chevron is the only difference, because a control that opens a menu should
/// say so before you press it. `Menu` with `.borderlessButtonStyle` draws its
/// own chrome and its own arrow, both of which fight the header, so the label is
/// built by hand and the style is stripped back to nothing.
struct HeaderMenu<Content: View>: View {
    let symbol: String
    let title: String
    var detail: String?
    @ViewBuilder let content: Content

    @Environment(TooltipController.self) private var tooltips
    @State private var isHovering = false
    @State private var frame: CGRect = .zero

    var body: some View {
        Menu {
            content
        } label: {
            HStack(spacing: 1) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.primary.opacity(Tokens.Ink.faint))
            }
            .frame(width: 34, height: 26)
            .foregroundStyle(.primary.opacity(Tokens.Ink.regular))
            .background {
                RoundedRectangle(cornerRadius: Tokens.Radius.control, style: .continuous)
                    .fill(.primary.opacity(isHovering ? Tokens.Fill.hover : 0))
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .trackedForTooltip($frame)
        .onHover { hovering in
            isHovering = hovering
            hovering
                ? tooltips.hover(
                    key: "header-menu-\(title)", title: title,
                    shortcut: nil, detail: detail, anchor: frame
                )
                : tooltips.endHover(key: "header-menu-\(title)")
        }
        .animation(Tokens.Motion.micro, value: isHovering)
        .accessibilityLabel(title)
    }
}

/// Everything you can do *to the picture*, and how you are looking at it.
///
/// **Why this is in the header at all.** Flip, Rotate, Invert, Remove Background,
/// Image Size, the pixel grid and snapping were menu-bar-only. The menu bar is
/// the right home for a complete list and the wrong one for a thing you reach for
/// mid-edit: the pointer is on the canvas, the menu is at the top of the screen,
/// and on a second display it is on the *other screen*. Everything here is one
/// press from where your hand already is, and every item still says its key, so
/// the menu teaches its way out of being needed.
///
/// Two menus rather than one long one, matching the two menu-bar menus people
/// already know: what the picture *is*, and how you are *looking* at it.
struct ImageMenu: View {
    @Bindable var model: EditorModel

    var body: some View {
        let _ = model.revision

        HeaderMenu(
            symbol: "photo", title: "Image",
            detail: "Rotate, flip, resize, invert, or knock the background out"
        ) {
            Button("Image Size…") { model.isSizeSheetPresented = true }
                .keyboardShortcut("r")
            Divider()
            Button("Rotate 90° Right") { model.rotate(.clockwise90) }
                .keyboardShortcut("]")
            Button("Rotate 90° Left") { model.rotate(.counterClockwise90) }
                .keyboardShortcut("[")
            Button("Rotate 180°") { model.rotate(.half) }
            Button("Rotate…") { model.isRotateSheetPresented = true }
            Divider()
            Button("Flip Horizontal") { model.flipHorizontally() }
            Button("Flip Vertical") { model.flipVertically() }
            Divider()
            Button("Invert Colours") { model.invertColours() }
                .keyboardShortcut("i")
            // The one item here that can decline. It says so itself when the
            // image is too flat to key safely, rather than guessing.
            Button("Remove Background") { model.removeBackground() }
            Button("Trim Borders") { model.trimBorders() }
        }
    }
}

/// How you are looking at the picture, as opposed to what it is.
struct ViewMenu: View {
    @Bindable var model: EditorModel

    var body: some View {
        let _ = model.revision

        HeaderMenu(
            symbol: "slider.horizontal.3", title: "View",
            detail: "The pixel grid, snapping, and which edge the toolbar is on"
        ) {
            // A checkmark, not a verb. "Show Pixel Grid" next to "Hide Pixel
            // Grid" is the same item wearing two labels, and you have to read it
            // to find out which state you are in.
            Toggle("Pixel Grid", isOn: Binding(
                get: { model.showsGrid },
                set: { model.showsGrid = $0 }
            ))
            // The grid is meaningless until a pixel is comfortably bigger than
            // the line that would draw it — the same floor the menu bar applies.
            .disabled(model.zoom < 4)

            Toggle("Snap to Grid", isOn: Binding(
                get: { model.snapGrid != 0 },
                set: { model.snapGrid = $0 ? ViewMenu.defaultSnap : 0 }
            ))

            if model.snapGrid != 0 {
                Picker("Grid Spacing", selection: Binding(
                    get: { model.snapGrid },
                    set: { model.snapGrid = $0 }
                )) {
                    ForEach(ToolSettings.snapGrids, id: \.self) { size in
                        Text("\(size) px").tag(size)
                    }
                }
            }

            Divider()
            Button(model.chromeEdge.isVertical ? "Toolbar Along the Bottom" : "Toolbar Down the Side") {
                model.chromeEdge = model.chromeEdge.toggled
            }
            Divider()
            Button("Colours…") { model.presentSystemColourPicker(for: .foreground) }
        }
    }

    /// The spacing snapping returns to. Matches the menu bar's own default so
    /// the two switches cannot disagree about what "on" means.
    static let defaultSnap = 8
}

/// What you can do with a selection, once there is one.
///
/// **The problem this solves.** Marquee out a region and the useful next moves —
/// crop the picture to it, copy it, cut it — are in a menu bar nobody looks at
/// mid-gesture, or behind shortcuts you have to already know. People selected a
/// region, found Crop to Selection greyed out earlier in the session, and never
/// went back to it. The capability was there; the affordance was not.
///
/// **Why here and not beside the selection.** A bar that follows the marquee
/// covers the thing you just framed, and moves every time you adjust a handle —
/// so you end up dragging the selection to see the buttons for it. This is the
/// slot the paste bar already owns: bottom-centre, clear of the rail on either
/// edge and of the pointer read-out in the corner, always in the same place. One
/// slot, one grammar, and it appears and disappears with the selection.
///
/// The paste bar wins the slot when something is floating, because a floating
/// paste *is* a selection and offering two bars for one state is two answers.
struct SelectionActions: View {
    @Bindable var model: EditorModel

    var body: some View {
        // Revision, so the size read-out follows the marquee as it is dragged.
        let _ = model.revision

        HStack(spacing: Tokens.Space.tight) {
            Image(systemName: "square.dashed")
                .font(.system(size: 11))
                .foregroundStyle(.primary.opacity(Tokens.Ink.muted))

            if let size = model.selectionSize {
                Text("\(size.width) × \(size.height)")
                    .font(Tokens.Text.pillValue)
                    .foregroundStyle(.primary.opacity(Tokens.Ink.muted))
            }

            HeaderDivider()

            // Crop first and filled: it is the move this bar exists for, the one
            // people could not find, and the only one of the four that is not
            // already a shortcut every Mac user knows.
            action("Crop", symbol: "crop", shortcut: "⌘K", role: .primary) {
                model.cropToSelection()
            }
            action("Copy", symbol: "square.on.square", shortcut: "⌘C") { model.copySelection() }
            action("Cut", symbol: "scissors", shortcut: "⌘X") { model.cutSelection() }
            action("Delete", symbol: "trash", shortcut: "⌫", role: .destructive) {
                model.deleteSelection()
            }
        }
        .padding(.horizontal, Tokens.Space.base)
        .frame(height: Tokens.Size.headerControl)
        .chromeSurface(cornerRadius: Tokens.Radius.chip)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Selection. Crop to it, copy, cut, or delete.")
    }

    private enum Role { case primary, neutral, destructive }

    /// One action, with its key printed on it.
    ///
    /// The shortcut is *on the button* rather than in a tooltip: this bar is on
    /// screen for a few seconds at a time while somebody's hand is on the mouse,
    /// and the whole reason it is worth showing is to teach the three chords that
    /// make it unnecessary.
    private func action(
        _ title: String, symbol: String, shortcut: String,
        role: Role = .neutral, perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                Text(title).font(.system(size: 11.5))
                Text(shortcut)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(shortcutInk(role))
            }
            .foregroundStyle(foreground(role))
            .padding(.horizontal, Tokens.Space.base)
            .frame(height: 22)
            .background {
                RoundedRectangle(cornerRadius: Tokens.Radius.control, style: .continuous)
                    .fill(background(role))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func foreground(_ role: Role) -> AnyShapeStyle {
        switch role {
        case .primary: AnyShapeStyle(Color.white)
        case .destructive: AnyShapeStyle(Color.red)
        case .neutral: AnyShapeStyle(.primary.opacity(Tokens.Ink.regular))
        }
    }

    /// The key is a hint, not a label: quieter than the word it belongs to, in
    /// every role, or four buttons read as eight things.
    private func shortcutInk(_ role: Role) -> AnyShapeStyle {
        switch role {
        case .primary: AnyShapeStyle(Color.white.opacity(0.65))
        case .destructive: AnyShapeStyle(Color.red.opacity(0.6))
        case .neutral: AnyShapeStyle(.primary.opacity(Tokens.Ink.faint))
        }
    }

    private func background(_ role: Role) -> AnyShapeStyle {
        switch role {
        case .primary: AnyShapeStyle(Color.accentColor)
        case .destructive, .neutral: AnyShapeStyle(.primary.opacity(Tokens.Fill.track))
        }
    }
}

/// Where the pointer is, and how big the thing being dragged is.
///
/// **The only readout that still has to be near the artwork**, because it is
/// about the pointer rather than about the document — everything else moved up
/// into the header, where it stopped covering the bottom-right of every
/// screenshot someone was trying to annotate.
///
/// What is left is deliberately not a panel: no capsule, no material, no
/// shadow. Monospaced text at low opacity that appears when the pointer is over
/// the canvas and fades out when it leaves, so at rest there is nothing over
/// the artwork at all.
struct PointerReadout: View {
    @Bindable var model: EditorModel

    var body: some View {
        HStack(spacing: Tokens.Space.tight) {
            if let size = model.activeRegionSize {
                // While a region is being dragged its size is the useful
                // number, and it is worth an accent because it is live.
                Text("\(size.width) × \(size.height)")
                    .foregroundStyle(.primary.opacity(Tokens.Ink.strong))
            }
            if let position = model.pointerPosition {
                Text("\(position.x), \(position.y)")
                    .foregroundStyle(.primary.opacity(Tokens.Ink.faint))
            }
        }
        .font(.system(size: 10.5).monospacedDigit())
        .shadow(color: .black.opacity(0.55), radius: 3)
        .opacity(isVisible ? 1 : 0)
        .animation(Tokens.Motion.micro, value: isVisible)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var isVisible: Bool {
        model.pointerPosition != nil || model.activeRegionSize != nil
    }
}
