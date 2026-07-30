import AppKit
import PaintKit
import SwiftUI

/// The box you sign in.
///
/// An `NSView` rather than a SwiftUI `DragGesture` for one reason: signing is a
/// fast, curvy gesture and SwiftUI delivers drag updates coalesced per frame, which
/// on a quick flourish drops the corners and turns handwriting into a polygon.
/// `mouseDragged:` on a plain view gives every point the device reported.
///
/// It draws a live preview with Core Graphics and hands the raw points back. The
/// bitmap is rasterised once on save, by the engine's own brush — drawing the
/// preview twice, once for the screen and once for the file, would be two chances
/// to disagree about what was signed.
struct SigningStrip: NSViewRepresentable {
    @Binding var strokes: [[CGPoint]]
    /// Previewed in the colour it will be saved in — otherwise the box shows one
    /// signature and the library keeps a different one.
    let ink: PaintColour

    func makeNSView(context: Context) -> StripView {
        let view = StripView()
        view.onChange = { strokes = $0 }
        view.ink = NSColor(
            srgbRed: ink.red, green: ink.green, blue: ink.blue, alpha: ink.alpha
        )
        return view
    }

    func updateNSView(_ nsView: StripView, context: Context) {
        nsView.ink = NSColor(
            srgbRed: ink.red, green: ink.green, blue: ink.blue, alpha: ink.alpha
        )
        // Only push down when the model has genuinely diverged — Clear is the one
        // case — otherwise every point the view reports would echo straight back
        // and interrupt the stroke in progress.
        if nsView.strokes.count != strokes.count && strokes.isEmpty {
            nsView.strokes = []
            nsView.needsDisplay = true
        }
    }

    final class StripView: NSView {
        var strokes: [[CGPoint]] = []
        var ink: NSColor = .black
        var onChange: (([[CGPoint]]) -> Void)?

        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { true }

        override func resetCursorRects() {
            // A crosshair, not an arrow: this is a drawing surface, and the arrow
            // makes it look like something to click.
            addCursorRect(bounds, cursor: .crosshair)
        }

        override func mouseDown(with event: NSEvent) {
            strokes.append([point(for: event)])
            needsDisplay = true
        }

        override func mouseDragged(with event: NSEvent) {
            guard !strokes.isEmpty else { return }
            strokes[strokes.count - 1].append(point(for: event))
            needsDisplay = true
        }

        override func mouseUp(with event: NSEvent) {
            guard !strokes.isEmpty else { return }
            strokes[strokes.count - 1].append(point(for: event))
            needsDisplay = true
            onChange?(strokes)
        }

        private func point(for event: NSEvent) -> CGPoint {
            let p = convert(event.locationInWindow, from: nil)
            // Clamped rather than dropped: a stroke that runs off the edge should
            // end at the edge, not vanish mid-letter.
            return CGPoint(
                x: min(max(p.x, 0), bounds.width),
                y: min(max(p.y, 0), bounds.height)
            )
        }

        override func draw(_ dirtyRect: NSRect) {
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            context.setStrokeColor(ink.cgColor)
            context.setLineWidth(2.4)
            context.setLineCap(.round)
            context.setLineJoin(.round)

            for stroke in strokes where stroke.count > 1 {
                context.beginPath()
                context.move(to: stroke[0])
                // Quadratic through midpoints: joining the raw samples with
                // straight lines shows every hand tremor as a visible corner,
                // which reads as a shaky signature rather than a smooth one.
                for i in 1..<(stroke.count - 1) {
                    let mid = CGPoint(
                        x: (stroke[i].x + stroke[i + 1].x) / 2,
                        y: (stroke[i].y + stroke[i + 1].y) / 2
                    )
                    context.addQuadCurve(to: mid, control: stroke[i])
                }
                context.addLine(to: stroke[stroke.count - 1])
                context.strokePath()
            }

            // A single tap still leaves a mark, so a dot in an "i" is not lost.
            for stroke in strokes where stroke.count == 1 {
                context.setFillColor(ink.cgColor)
                context.fillEllipse(in: CGRect(
                    x: stroke[0].x - 1.2, y: stroke[0].y - 1.2, width: 2.4, height: 2.4
                ))
            }
        }
    }
}
