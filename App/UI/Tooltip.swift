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
        // **One surface, both lines.** The detail used to be printed outside the
        // chip, straight onto the artwork: grey text at 60% on whatever colour
        // the picture happened to be, with no background at all. It was the
        // least legible text in the app and it was the text doing the teaching.
        VStack(alignment: .leading, spacing: 4) {
            heading
            if let detail {
                Text(detail)
                    .font(.system(size: 11))
                    // A tooltip is read once, quickly, at a glance. `muted` is
                    // the value-beside-a-label step and it is too quiet for a
                    // sentence somebody has stopped to read.
                    .foregroundStyle(.primary.opacity(Tokens.Ink.regular))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 210, alignment: .leading)
            }
        }
        .padding(.horizontal, Tokens.Space.base + 1)
        .padding(.vertical, Tokens.Space.tight + 1)
        .background {
            let shape = RoundedRectangle(cornerRadius: Tokens.Radius.panel, style: .continuous)
            // Not `.chromeSurface`. That material is tuned for chrome sitting
            // over artwork it wants to let through; a tooltip has to be opaque
            // enough to read a sentence against a photograph. This is the same
            // grammar — material, tint floor, luminous hairline — with the floor
            // raised until the text wins.
            shape
                .fill(.regularMaterial)
                .overlay { shape.fill(Color(nsColor: .textBackgroundColor).opacity(0.55)) }
                .overlay { shape.strokeBorder(.primary.opacity(0.14), lineWidth: 0.5) }
                .compositingGroup()
                .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.panel, style: .continuous))
        .fixedSize()
        .transition(.opacity.combined(with: .offset(y: 3)))
    }

    private var heading: some View {
        HStack(spacing: Tokens.Space.tight + 1) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)

            if let shortcut {
                Text(shortcut)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary.opacity(Tokens.Ink.strong))
                    .frame(minWidth: 15)
                    .padding(.vertical, 1.5)
                    .padding(.horizontal, 4)
                    .background {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(.primary.opacity(Tokens.Fill.track))
                    }
                    .overlay {
                        // A keycap reads as a key. Writing "(P)" in the label
                        // makes the reader parse a sentence instead.
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(.primary.opacity(0.14), lineWidth: 0.5)
                    }
            }
        }
    }
}

/// Tracks which control is hovered and after how long, so one owner can show a
/// single tooltip for a whole row.
///
/// The delay is deliberately short and the *re-entry* delay is zero: once a
/// tooltip is up, moving along the row swaps it instantly. Waiting again at
/// every cell is what makes system tooltips useless for scanning a toolbar.
@MainActor
@Observable
final class TooltipController {
    private(set) var visibleKey: String?
    private(set) var title: String = ""
    private(set) var shortcut: String?
    private(set) var detail: String?

    /// The hovered control's frame in screen coordinates, for the controls whose
    /// chip cannot be positioned from the rail's own geometry.
    ///
    /// The rail knows where its cells are, so it leaves this nil and offsets the
    /// chip itself. The header does not — its cluster slides with the window
    /// width — so header buttons report where they actually are and the chip
    /// follows the glyph rather than guessing at the middle of the row.
    private(set) var anchor: CGRect?

    @ObservationIgnored private var pendingKey: String?
    @ObservationIgnored private var work: DispatchWorkItem?

    /// How long the pointer has to rest before the first chip appears.
    ///
    /// The system waits about a second. This was 300ms, which is still long
    /// enough to feel like a wait rather than an answer — you notice yourself
    /// pausing. 110ms is under the threshold where a delay reads as a delay,
    /// and it is still far enough above zero that sweeping the pointer across
    /// the header on the way somewhere else does not flash a chip.
    static let delay: TimeInterval = 0.11

    /// And how long a chip lingers after the pointer leaves, so travelling
    /// between two adjacent cells does not blink it off and on.
    static let grace: TimeInterval = 0.08

    var isVisible: Bool { visibleKey != nil }

    func hover(
        key: String,
        title: String,
        shortcut: String?,
        detail: String? = nil,
        anchor: CGRect? = nil
    ) {
        guard pendingKey != key else { return }
        pendingKey = key
        work?.cancel()

        // Already showing one: swap immediately.
        if visibleKey != nil {
            visibleKey = key
            self.title = title
            self.shortcut = shortcut
            self.detail = detail
            self.anchor = anchor
            return
        }

        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.pendingKey == key else { return }
                self.visibleKey = key
                self.title = title
                self.shortcut = shortcut
                self.detail = detail
                self.anchor = anchor
            }
        }
        work = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.delay, execute: item)
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
                self.anchor = nil
            }
        }
        work = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.grace, execute: item)
    }

    func dismiss() {
        work?.cancel()
        pendingKey = nil
        visibleKey = nil
        anchor = nil
    }
}
