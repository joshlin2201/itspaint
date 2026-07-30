import AppKit
import PaintKit
import Testing
@testable import ItsPaint

/// The live text editor's layout, which is where the multi-line bug actually was.
///
/// The first fix — making the box grow — was necessary but not sufficient, and
/// the difference was invisible except on screen: `isVerticallyResizable` lets
/// the *view* grow, while the text *container* keeps whatever height it was
/// created with. A second line was laid out and then clipped, which looks
/// identical to the box failing to grow.
///
/// Asserted here rather than screenshotted, because a screenshot of this needs
/// a window, focus, a keystroke and a mouse drag to all land in order, and one
/// of them not landing reads as a passing test.
@Suite("Text editor layout")
@MainActor
struct TextEditorLayoutTests {

    private func editor(width: CGFloat = 240, height: CGFloat = 44) -> TextEntryView {
        let view = TextEntryView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        view.font = NSFont(name: "Helvetica", size: 24) ?? .systemFont(ofSize: 24)
        view.isRichText = false
        view.applyUnboundedVerticalLayout()
        return view
    }

    @Test("The container is unbounded vertically, not capped at the frame")
    func containerIsUnbounded() {
        let view = editor()
        let container = try! #require(view.textContainer)
        #expect(container.size.height > 10_000, "the container is still capped at the frame height")
        #expect(container.size.width == view.frame.width)
        #expect(view.isVerticallyResizable)
    }

    @Test("A second line lays out taller rather than being clipped")
    func secondLineLaysOut() {
        let view = editor()
        view.string = "AAA"
        let one = view.laidOutTextHeight
        #expect(one > 0)

        view.string = "AAA\nBBB"
        let two = view.laidOutTextHeight

        // This is the assertion the bug would have failed: the container capped
        // at 44pt reported the same height for one line and for two.
        #expect(two > one * 1.5, "two lines laid out at \(two) versus one at \(one)")
    }

    @Test("Every typed line is laid out, however many there are")
    func manyLinesAllLayOut() {
        let view = editor()
        var previous: CGFloat = 0
        for count in 1...6 {
            view.string = (1...count).map { "line \($0)" }.joined(separator: "\n")
            let height = view.laidOutTextHeight
            #expect(height > previous, "line \(count) did not increase the laid-out height")
            previous = height
        }
    }

    @Test("Widening the box rewraps rather than keeping the old width")
    func widthChangeRewraps() {
        let view = editor(width: 90, height: 44)
        view.string = "wrap this sentence onto several lines"
        let narrow = view.laidOutTextHeight

        view.setFrameSize(NSSize(width: 400, height: 44))
        view.applyUnboundedVerticalLayout()
        let wide = view.laidOutTextHeight

        #expect(wide < narrow, "a wider box did not rewrap: \(wide) vs \(narrow)")
    }

    @Test("Without the fix, a capped container genuinely clips the second line")
    func cappedContainerClips() {
        // The point of this one is to prove the tests above would have caught
        // the bug rather than merely agreeing with the fix. This is the old
        // configuration: the view resizable, the container left at the frame
        // height.
        let view = TextEntryView(frame: NSRect(x: 0, y: 0, width: 240, height: 44))
        view.font = NSFont(name: "Helvetica", size: 24) ?? .systemFont(ofSize: 24)
        view.isRichText = false
        view.isVerticallyResizable = true
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: 240, height: 44)

        view.string = "AAA"
        let one = view.laidOutTextHeight
        view.string = "AAA\nBBB"
        let two = view.laidOutTextHeight

        // Clipped: two lines report no more usable height than the cap allows.
        #expect(two <= 44 + 1, "the capped container did not clip, so the guard above is not load-bearing")
        #expect(two < one * 1.5 + 1, "one line \(one), two lines \(two) — expected clipping")
    }

    @Test("The laid-out height is close to what the rasteriser will measure")
    func agreesWithRenderer() {
        // The editor is a *preview* of the commit. If the two disagree about how
        // tall the text is, the box grows to one size and the pixels land at
        // another — which is the class of bug this whole path had.
        let width = 240
        let text = "AAA\nBBB\nCCC"
        let view = editor(width: CGFloat(width))
        view.string = text

        var style = TextRenderer.Style(fontName: "Helvetica", pointSize: 24)
        style.colour = .black
        let measured = TextRenderer.measure(text, style: style, maxWidth: width)

        let editorHeight = view.laidOutTextHeight
        let ratio = editorHeight / CGFloat(measured.height)
        #expect(ratio > 0.75 && ratio < 1.35,
                "editor says \(editorHeight), renderer says \(measured.height)")
    }
}
