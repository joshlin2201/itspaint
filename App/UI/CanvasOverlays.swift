import PaintKit
import SwiftUI

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
            Text(subtitle)
                .font(.system(size: 10.5))
                .foregroundStyle(.primary.opacity(Tokens.Ink.faint))
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
struct HeaderButton: View {
    let symbol: String
    let title: String
    var shortcut: String?
    var isEnabled: Bool = true
    let action: () -> Void

    @State private var isHovering = false

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
        .onHover { isHovering = $0 }
        .animation(Tokens.Motion.micro, value: isHovering)
        .help(shortcut.map { "\(title) (\($0))" } ?? title)
        .accessibilityLabel(title)
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

    @State private var isHovering = false

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
        .onHover { isHovering = $0 }
        .animation(Tokens.Motion.micro, value: isHovering)
        .help("Actual size (⌘0)")
        .accessibilityLabel("Zoom \(label), press for actual size")
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
    var body: some View {
        LinearGradient(
            colors: [.black.opacity(0.34), .black.opacity(0)],
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
struct WorkingActions: View {
    @Bindable var model: EditorModel

    var body: some View {
        // Undo lives in the UI-free engine, so its computed flags are not
        // observable on their own. Revision makes this strip follow each edit
        // and replay instead of leaving apparently disabled controls behind.
        let _ = model.revision

        HStack(spacing: Tokens.Space.tight) {
            HeaderGroup {
                HeaderButton(
                    symbol: "scissors", title: "Cut",
                    shortcut: "⌘X", isEnabled: model.hasSelection
                ) { model.cutSelection() }
                HeaderButton(
                    symbol: "square.on.square", title: "Copy",
                    shortcut: "⌘C", isEnabled: model.hasSelection
                ) { model.copySelection() }
                HeaderButton(
                    // `clipboard` when there is something on it, and the same
                    // glyph without its page when there is not — so the button
                    // says *why* it is unavailable rather than just being dim.
                    symbol: model.canPaste ? "doc.on.clipboard" : "clipboard",
                    title: model.canPaste ? "Paste image" : "Nothing to paste",
                    shortcut: "⌘V", isEnabled: model.canPaste
                ) { model.paste() }
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

            HeaderGroup {
                HeaderButton(
                    symbol: "minus", title: "Zoom out", shortcut: "⌘−",
                    isEnabled: model.zoom > (EditorModel.zoomSteps.first ?? 1)
                ) { model.zoomOut() }

                // **The percentage is the button.** There used to be a separate
                // `arrow.up.left.and.arrow.down.right` cell for Actual Size,
                // behind a divider, while tapping this label did exactly the
                // same thing. Two controls for one action, and the glyph on the
                // explicit one is the one every other Mac app uses for *fit* or
                // *full screen*, so the pair managed to be both redundant and
                // misleading. What is left is a real button whose label is the
                // current zoom and whose action is 100%.
                ZoomReadout(label: zoomLabel, isActualSize: model.zoom == 1) {
                    model.hasUserZoomed = true
                    model.zoom = 1
                }

                HeaderButton(
                    symbol: "plus", title: "Zoom in", shortcut: "⌘+",
                    isEnabled: model.zoom < (EditorModel.zoomSteps.last ?? 1)
                ) { model.zoomIn() }
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

    var body: some View {
        HeaderGroup {
            // Share is in the File menu, but a markup app's whole purpose is
            // getting the result to someone else — burying its most common last
            // step one menu down is the wrong emphasis.
            ShareButton()
            HeaderButton(symbol: "doc.on.doc", title: "Duplicate", shortcut: "⇧⌘S") {
                model.duplicateDocument()
            }
        }
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
