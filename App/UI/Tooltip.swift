import AppKit
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
                    .font(.system(size: Self.detailPointSize))
                    // A tooltip is read once, quickly, at a glance. `muted` is
                    // the value-beside-a-label step and it is too quiet for a
                    // sentence somebody has stopped to read.
                    .foregroundStyle(.primary.opacity(Tokens.Ink.regular))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: Self.detailWidth(of: detail), alignment: .leading)
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

    /// The size the explanation is set at, in one place, because the layout has
    /// to measure the same face it draws.
    static let detailPointSize: CGFloat = 11

    /// The widest a chip's explanation may get before it wraps.
    static let maxDetailWidth: CGFloat = 210

    /// A **concrete** width for the sentence, and that is the whole fix for a bug
    /// worth naming.
    ///
    /// `.fixedSize(horizontal: false, vertical: true)` keeps the *proposed* width
    /// and asks for the height that fits it. But the chip is `.fixedSize()`
    /// overall, so the width proposed down to that text was `nil` — and under a
    /// nil proposal `.frame(maxWidth: 210)` let the text report the height of one
    /// unbroken line while drawing three. The chip then clipped the other two
    /// away with its own rounded-rectangle mask.
    ///
    /// **The bug hid itself.** Every assertion in `TooltipRenderTests` bounded the
    /// chip from *above* — "not taller than 66pt" — so each line that went missing
    /// made the check pass more comfortably. What replaced them is a check that a
    /// longer sentence makes a taller chip, which is the property the eye is
    /// actually using. See `docs/CHECKS_THAT_MISS.md`.
    ///
    /// Measured rather than fixed at the cap so a three-word chip stays a
    /// three-word chip: "Already at 100%" in a 210pt box is a chip mostly made of
    /// nothing.
    static func detailWidth(of detail: String) -> CGFloat {
        // AppKit's metrics for the face SwiftUI resolves `.system(size: 11)` to,
        // plus a point of slack so a sentence that measures exactly at the cap is
        // not wrapped by a rounding difference between the two frameworks.
        let ideal = (detail as NSString)
            .size(withAttributes: [.font: NSFont.systemFont(ofSize: detailPointSize)])
            .width
        return min(ceil(ideal) + 1, maxDetailWidth)
    }

    /// The widest a chip's *title* may get.
    ///
    /// A backstop rather than a working limit. The detail line has been capped
    /// since the clipping fix, and the heading had nothing at all — so a caller
    /// that put three clauses and a live hex value in the title, which the colour
    /// chips briefly did, produced a chip about 380pt wide with no test able to
    /// see it. Titles are names; a name that needs 260pt is the bug.
    static let maxTitleWidth: CGFloat = 260

    private var heading: some View {
        HStack(spacing: Tokens.Space.tight + 1) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(
                    width: min(
                        ceil((title as NSString)
                            .size(withAttributes: [.font: NSFont.boldSystemFont(ofSize: 12)]).width) + 2,
                        Self.maxTitleWidth
                    ),
                    alignment: .leading
                )

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

    /// The hovered control's frame in screen coordinates.
    ///
    /// **Required, not optional.** It used to be optional because the rail drew
    /// its own chip from a constant offset and only the header reported a
    /// position. There is one chip now and it is placed from this, so a missing
    /// anchor cannot mean "the other layer will handle it" — it can only mean the
    /// chip goes somewhere wrong or nowhere at all. A defaulted `nil` on `hover`
    /// was a trap set for whoever adds the eleventh call site.
    private(set) var anchor: CGRect = .zero

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
        anchor: CGRect
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
                self.anchor = .zero
            }
        }
        work = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.grace, execute: item)
    }

    func dismiss() {
        work?.cancel()
        pendingKey = nil
        visibleKey = nil
        anchor = .zero
    }
}
