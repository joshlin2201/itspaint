import Observation
import SwiftUI

/// A tooltip that names a control and teaches its shortcut.
///
/// The system tooltip is not enough here. This app's whole chrome is eleven
/// unlabelled glyphs — the stated weakness of the canvas-first direction — so
/// the tooltip is doing real teaching work, not offering a nicety. It needs to
/// appear faster than the system's ~1 second delay, show the key as a key
/// rather than as prose, and match the glass it sits above.
///
/// One tooltip exists at a time, owned by the cluster, so hovering across a row
/// of cells slides one chip rather than popping eleven.
struct Tooltip: View {
    let title: String
    let shortcut: String?
    /// One line under the title, for tools whose first drag is not obvious.
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            heading
            if let detail {
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.primary.opacity(Tokens.Ink.muted))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 210, alignment: .leading)
            }
        }
    }

    private var heading: some View {
        HStack(spacing: Tokens.Space.tight + 1) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.primary)

            if let shortcut {
                Text(shortcut)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary.opacity(Tokens.Ink.regular))
                    .frame(minWidth: 15)
                    .padding(.vertical, 1.5)
                    .padding(.horizontal, 4)
                    .background {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(.primary.opacity(Tokens.Fill.separator))
                    }
                    .overlay {
                        // A keycap reads as a key. Writing "(P)" in the label
                        // makes the reader parse a sentence instead.
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(.primary.opacity(0.10), lineWidth: 0.5)
                    }
            }
        }
        .padding(.horizontal, Tokens.Space.base)
        .padding(.vertical, Tokens.Space.tight + 1)
        .chromeSurface(cornerRadius: Tokens.Radius.chip + 1)
        .fixedSize()
        .transition(.opacity.combined(with: .offset(y: 3)))
    }
}

/// Tracks which control is hovered and after how long, so one owner can show a
/// single tooltip for a whole row.
///
/// The delay is deliberately short (300ms, versus the system's ~1s) and the
/// *re-entry* delay is zero: once a tooltip is up, moving along the row swaps
/// it instantly. Waiting again at every cell is what makes system tooltips
/// useless for scanning a toolbar.
@MainActor
@Observable
final class TooltipController {
    private(set) var visibleKey: String?
    private(set) var title: String = ""
    private(set) var shortcut: String?
    private(set) var detail: String?

    @ObservationIgnored private var pendingKey: String?
    @ObservationIgnored private var work: DispatchWorkItem?

    var isVisible: Bool { visibleKey != nil }

    func hover(key: String, title: String, shortcut: String?, detail: String? = nil) {
        guard pendingKey != key else { return }
        pendingKey = key
        work?.cancel()

        // Already showing one: swap immediately.
        if visibleKey != nil {
            visibleKey = key
            self.title = title
            self.shortcut = shortcut
            self.detail = detail
            return
        }

        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.pendingKey == key else { return }
                self.visibleKey = key
                self.title = title
                self.shortcut = shortcut
                self.detail = detail
            }
        }
        work = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30, execute: item)
    }

    func endHover(key: String) {
        guard pendingKey == key else { return }
        pendingKey = nil
        work?.cancel()

        // A short grace period so travelling between adjacent cells does not
        // flicker the chip off and on.
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.pendingKey == nil else { return }
                self.visibleKey = nil
            }
        }
        work = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: item)
    }

    func dismiss() {
        work?.cancel()
        pendingKey = nil
        visibleKey = nil
    }
}
