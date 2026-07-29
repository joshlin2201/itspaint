import AppKit
import PaintKit
import SwiftUI


/// Hosts the AppKit canvas inside a scroll view.
///
/// The scroll view is the single vertical *and* horizontal scroll owner for
/// this region. Nothing inside the canvas area scrolls independently — a nested
/// scroller here would steal wheel events mid-stroke.
struct CanvasScrollView: NSViewRepresentable {
    @Bindable var model: EditorModel

    func makeNSView(context: Context) -> NSScrollView {
        let canvas = CanvasNSView()
        canvas.model = model
        canvas.zoom = model.zoom
        canvas.enableDropping()

        let scrollView = ViewportScrollView()
        // The viewport changes without any observable state changing — a window
        // resize, the rail moving edge — and the fit has to follow it or the
        // artwork ends up behind a scrollbar on a window that could show it all.
        scrollView.onViewportChange = { [weak scrollView] in
            guard let scrollView, let canvas = scrollView.documentView as? CanvasNSView else { return }
            fitToViewport(scrollView, canvas: canvas)
        }
        scrollView.contentView = CentringClipView()
        scrollView.documentView = canvas
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = false
        scrollView.drawsBackground = true
        // The well the artwork sits on. A distinct, recessive tone is what
        // makes the canvas edge legible without drawing a border around it.
        scrollView.backgroundColor = .underPageBackgroundColor
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.scrollerStyle = .overlay
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let canvas = scrollView.documentView as? CanvasNSView else { return }
        canvas.model = model
        canvas.zoom = model.zoom
        // Switching tools lands an open text box rather than dropping it.
        canvas.commitText(unless: model.tool)

        // Reading `revision` is what makes SwiftUI re-invoke this on every pixel
        // change, and handing it to the view is what keeps that cheap: a change
        // the canvas already painted itself repaints nothing. Note what is NOT
        // done here — re-laying out and rebuilding cursor rects on every stroke
        // segment, which is work proportional to input rate for no benefit.
        canvas.repaintIfChanged(revision: model.revision)
        canvas.refreshCursorIfNeeded()
        canvas.invalidateCanvasSize()
        fitToViewport(scrollView, canvas: canvas)
        // After the fit, so the reveal scrolls against the zoom the content
        // will actually be drawn at.
        canvas.revealFloatingIfNeeded()
    }

    /// Keep the whole artwork in the viewport until the user picks a zoom.
    ///
    /// Recomputed from the current viewport every time rather than only ratcheted
    /// down: the earlier shrink-only version latched onto whatever size the clip
    /// view happened to have mid-layout, and a transient 150pt viewport left the
    /// document stuck at 19% with no way back except zooming by hand.
    ///
    /// Never magnifies past 100% — "fit" on a small sketch should not blow it
    /// up — and stands down the moment the user chooses a zoom themselves.
    private func fitToViewport(_ scrollView: NSScrollView, canvas: CanvasNSView) {
        guard !model.hasUserZoomed else { return }
        let viewport = scrollView.contentView.bounds.size
        // A viewport this small is a layout pass in progress, not a window.
        guard viewport.width > 120, viewport.height > 120 else { return }

        let scale = min(
            viewport.width / Double(model.canvas.width),
            viewport.height / Double(model.canvas.height)
        )
        // A hair under, so rounding never leaves a one-pixel overflow that
        // brings a scroller back.
        let fit = min(1, scale * 0.998)
        guard abs(fit - model.zoom) > 0.002 else { return }

        model.setZoomExact(fit)
        canvas.zoom = model.zoom
        canvas.invalidateCanvasSize()
    }
}

/// A scroll view that reports when its viewport changes size.
///
/// `updateNSView` only runs when observable state changes, and a window resize
/// changes none — so without this the shrink-to-fit would run once at open and
/// then never again.
private final class ViewportScrollView: NSScrollView {
    var onViewportChange: (() -> Void)?

    /// Pinch-to-zoom arrives here, not at the document view — `NSScrollView`
    /// is the responder AppKit offers magnification to, and it swallows the
    /// event when its own magnification is turned off.
    override func magnify(with event: NSEvent) {
        guard let canvas = documentView as? CanvasNSView else {
            return super.magnify(with: event)
        }
        canvas.zoomFromGesture(by: 1 + event.magnification, atWindowPoint: event.locationInWindow)
    }

    /// Same for ⌘-scroll, so the two gestures cannot diverge.
    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.contains(.command),
              let canvas = documentView as? CanvasNSView
        else { return super.scrollWheel(with: event) }

        let step = event.hasPreciseScrollingDeltas
            ? event.scrollingDeltaY * 0.006
            : event.scrollingDeltaY * 0.04
        canvas.zoomFromGesture(by: 1 + step, atWindowPoint: event.locationInWindow)
    }

    private var lastViewport: NSSize = .zero

    override func layout() {
        super.layout()
        let size = contentView.bounds.size
        guard size != lastViewport else { return }
        lastViewport = size
        // Reported *after* the layout pass, never during it. Changing observed
        // state here makes SwiftUI rebuild this very view tree while AppKit is
        // still walking it, and AppKit then messages a view it has already
        // released — a segfault inside `isFlipped`, nowhere near the cause.
        DispatchQueue.main.async { [weak self] in self?.onViewportChange?() }
    }
}

/// Keeps the artwork centred while it is smaller than the viewport.
///
/// Done by constraining the clip view's bounds rather than by repositioning the
/// document view. Moving the document view fights AppKit — the scroll machinery
/// recomputes that origin, so the canvas snaps back to the top-left and the
/// centring silently does nothing. `constrainBoundsRect` is the supported hook
/// and it also keeps scrolling, magnifying and live resize correct.
private final class CentringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let document = documentView else { return rect }
        let content = document.frame.size

        if content.width < rect.width {
            rect.origin.x = ((content.width - rect.width) / 2).rounded(.down)
        }
        if content.height < rect.height {
            rect.origin.y = ((content.height - rect.height) / 2).rounded(.down)
        }
        return rect
    }
}
