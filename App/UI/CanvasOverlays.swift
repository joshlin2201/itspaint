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
                .foregroundStyle(.primary.opacity(0.95))
                .lineLimit(1)
                .truncationMode(.middle)

            // The subtitle carries what the document *is*, which is the thing
            // that used to sit in a floating strip over the bottom-right of
            // the artwork.
            Text(subtitle)
                .font(.system(size: 10.5))
                .foregroundStyle(.primary.opacity(0.5))
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
                .foregroundStyle(.primary.opacity(isEnabled ? 0.85 : 0.28))
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.primary.opacity(isHovering && isEnabled ? 0.12 : 0))
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

/// A hairline between two runs inside one group.
struct HeaderDivider: View {
    var body: some View {
        Rectangle()
            .fill(.primary.opacity(0.14))
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
struct WindowActions: View {
    @Bindable var model: EditorModel

    var body: some View {
        // Undo lives in the UI-free engine, so its computed flags are not
        // observable on their own. Revision makes this strip follow each edit
        // and replay instead of leaving apparently disabled controls behind.
        let _ = model.revision

        HStack(spacing: Tokens.Space.tight) {
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

                Text(zoomLabel)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.primary.opacity(0.8))
                    .frame(minWidth: 40)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        model.hasUserZoomed = true
                        model.zoom = 1
                    }
                    .help("Actual size (⌘0)")
                    .accessibilityLabel("Zoom \(zoomLabel), click for actual size")

                HeaderButton(
                    symbol: "plus", title: "Zoom in", shortcut: "⌘+",
                    isEnabled: model.zoom < (EditorModel.zoomSteps.last ?? 1)
                ) { model.zoomIn() }

                HeaderDivider()

                HeaderButton(
                    symbol: "arrow.up.left.and.arrow.down.right",
                    title: "Actual size", shortcut: "⌘0"
                ) {
                    model.hasUserZoomed = true
                    model.zoom = 1
                }
            }

            HeaderGroup {
                // Share is in the File menu, but a markup app's whole purpose
                // is getting the result to someone else — burying its most
                // common last step one menu down is the wrong emphasis.
                ShareButton()
                HeaderButton(symbol: "doc.on.doc", title: "Duplicate", shortcut: "⇧⌘S") {
                    model.duplicateDocument()
                }
            }
        }
    }

    private var zoomLabel: String {
        let percent = model.zoom * 100
        return percent < 100 ? String(format: "%.0f%%", percent) : "\(Int(percent))%"
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
                    .foregroundStyle(.primary.opacity(0.9))
            }
            if let position = model.pointerPosition {
                Text("\(position.x), \(position.y)")
                    .foregroundStyle(.primary.opacity(0.45))
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
