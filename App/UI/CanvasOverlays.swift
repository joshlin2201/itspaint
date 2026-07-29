import PaintKit
import SwiftUI

/// The filename, on its own glass chip beside the traffic lights.
///
/// A chip rather than a titlebar: the titlebar is transparent so the artwork
/// runs under it, and the chip is the smallest surface that keeps the filename
/// legible over whatever happens to be there.
struct TitleChip: View {
    let name: String
    let isEdited: Bool

    var body: some View {
        Text(isEdited ? "\(name) — Edited" : name)
            .font(Tokens.Text.chip)
            .foregroundStyle(.primary.opacity(0.92))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, Tokens.Space.snug)
            .frame(height: Tokens.Size.headerControl)
            .chromeSurface(cornerRadius: Tokens.Radius.chip, elevated: false)
            .accessibilityLabel(isEdited ? "\(name), edited" : name)
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

/// Undo / redo / duplicate, floating at the top trailing corner.
struct WindowActions: View {
    @Bindable var model: EditorModel

    var body: some View {
        // Undo lives in the UI-free engine, so its computed flags are not
        // observable on their own. Revision makes this strip follow each edit
        // and replay instead of leaving apparently disabled controls behind.
        let _ = model.revision

        HStack(spacing: Tokens.Space.hair) {
            action("arrow.uturn.backward", "Undo", enabled: model.canUndo) { model.undo() }
            action("arrow.uturn.forward", "Redo", enabled: model.canRedo) { model.redo() }
            action("doc.on.doc", "Duplicate", enabled: true) { model.duplicateDocument() }
        }
        .padding(.horizontal, Tokens.Space.tight)
        .frame(height: Tokens.Size.headerControl)
        .chromeSurface(cornerRadius: Tokens.Radius.chip, elevated: false)
    }

    private func action(
        _ symbol: String, _ title: String, enabled: Bool, perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .frame(width: 26, height: 26)
                .foregroundStyle(.primary.opacity(enabled ? 0.9 : 0.3))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(title)
        .accessibilityLabel(title)
    }
}

/// Pointer position, canvas size and zoom — the status bar, floating.
///
/// The classic app kept exactly this in a strip along the bottom, and it is
/// still the right set: where you are, how big it is, how far in you are. The
/// zoom steppers are here rather than only in a menu because zoom is the one
/// view control people reach for constantly.
struct StatusStrip: View {
    @Bindable var model: EditorModel

    var body: some View {
        HStack(spacing: Tokens.Space.snug) {
            // Reserved so the row does not reflow as the pointer enters and
            // leaves the canvas.
            Label {
                Text(model.pointerPosition.map { "\($0.x), \($0.y)" } ?? "—")
                    .frame(minWidth: 58, alignment: .leading)
            } icon: {
                Image(systemName: "dot.scope").font(.system(size: 9))
            }
            .foregroundStyle(.primary.opacity(model.pointerPosition == nil ? 0.35 : 0.75))

            divider

            Text("\(model.canvasSize.width) × \(model.canvasSize.height)")
                .foregroundStyle(.primary.opacity(0.75))

            divider

            HStack(spacing: 2) {
                zoomStep("minus", enabled: model.zoom > (EditorModel.zoomSteps.first ?? 1)) {
                    model.zoomOut()
                }
                Text(zoomLabel)
                    .frame(minWidth: 38)
                    .monospacedDigit()
                zoomStep("plus", enabled: model.zoom < (EditorModel.zoomSteps.last ?? 1)) {
                    model.zoomIn()
                }
                zoomStep("arrow.up.left.and.arrow.down.right", enabled: true) {
                    model.hasUserZoomed = true
                    model.zoom = 1
                }
                .help("Actual size (⌘0)")
            }
        }
        .font(Tokens.Text.readout)
        .padding(.horizontal, Tokens.Space.snug)
        .frame(height: Tokens.Size.statusStrip)
        .chromeSurface(cornerRadius: Tokens.Radius.chip, elevated: false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "Canvas \(model.canvasSize.width) by \(model.canvasSize.height), zoom \(zoomLabel)"
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(.primary.opacity(0.16))
            .frame(width: 1, height: 12)
    }

    private func zoomStep(
        _ symbol: String, enabled: Bool, perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 20, height: 20)
                .foregroundStyle(.primary.opacity(enabled ? 0.8 : 0.28))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var zoomLabel: String {
        let percent = model.zoom * 100
        return percent < 100 ? String(format: "%.0f%%", percent) : "\(Int(percent))%"
    }
}
