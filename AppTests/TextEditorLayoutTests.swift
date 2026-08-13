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

    /// `width`/`height` are the **box**, not the view: the view is outset by the
    /// handle margin so the whole handle ring is inside it and clickable.
    private func editor(width: CGFloat = 240, height: CGFloat = 44) -> TextEntryView {
        let view = TextEntryView(frame: .zero)
        view.font = NSFont(name: "Helvetica", size: 24) ?? .systemFont(ofSize: 24)
        view.isRichText = false
        view.setBoxFrame(NSRect(x: 0, y: 0, width: width, height: height))
        return view
    }

    @Test("The container is unbounded vertically, not capped at the frame")
    func containerIsUnbounded() {
        let view = editor()
        let container = try! #require(view.textContainer)
        #expect(container.size.height > 10_000, "the container is still capped at the frame height")
        // The box's width, not the view's — the view carries the handle margin.
        #expect(container.size.width == view.boxBounds.width)
        #expect(view.isVerticallyResizable)
    }

    @Test("The view is outset so the whole handle ring is inside it")
    func handleRingIsInsideTheView() {
        let view = editor(width: 240, height: 44)
        let box = view.boxBounds

        #expect(box.width == 240, "the box is not the size it was asked for")
        #expect(box.height == 44)
        // Outset on every side by the margin.
        #expect(view.frame.width == 240 + view.handleMargin * 2)
        #expect(view.frame.height == 44 + view.handleMargin * 2)

        // Every handle centre, plus the margin around it, lies inside the view —
        // which is what makes the corner grabbable. Half of each handle used to
        // fall outside, and clicks that missed hit the canvas and began a move.
        let rect = PixelRect(
            x: 0, y: 0, width: Int(box.width), height: Int(box.height)
        )
        for (_, centre) in rect.handleCentres() {
            let spot = NSRect(
                x: box.minX + CGFloat(centre.x) - view.handleMargin,
                y: box.minY + CGFloat(centre.y) - view.handleMargin,
                width: view.handleMargin * 2, height: view.handleMargin * 2
            )
            #expect(view.bounds.contains(spot), "handle at \(centre) is not fully inside the view")
        }
    }

    @Test("The text is inset back to where the box is")
    func textSitsInTheBox() {
        // The margin must not shift the text, or the preview stops matching the
        // committed pixels.
        let view = editor()
        #expect(view.textContainerInset.width == view.handleMargin)
        #expect(view.textContainerInset.height == view.handleMargin)
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

        view.setBoxFrame(NSRect(x: 0, y: 0, width: 400, height: 44))
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
        view.handleMargin = 0
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

@Suite("The box holds what is typed into it")
@MainActor
struct TextBoxGrowthTests {

    private func style(_ size: Double) -> TextRenderer.Style {
        var s = TextRenderer.Style()
        s.pointSize = size
        return s
    }

    /// The complaint: pressing Return did not move the box. CoreText measures a
    /// trailing newline as nothing, so the caller has to count them, and the height
    /// the box grows to has to come from the same measurement that draws the text.
    @Test(arguments: [12.0, 18.0, 32.0])
    func aReturnAddsExactlyOneLine(size: Double) {
        let s = style(size)
        let line = TextRenderer.lineHeight(for: s)
        let one = TextRenderer.measure("Hello", style: s, maxWidth: 400).height
        let afterReturn = TextRenderer.measure("Hello\n", style: s, maxWidth: 400).height + line
        #expect(afterReturn == one + line,
                "Return grew the box by \(afterReturn - one)px, not one \(line)px line")
    }

    /// Interior blank lines are measured by CoreText; only the final one is dropped.
    /// The first version of this test added a line per trailing newline and made a box
    /// three times too tall after three Returns.
    @Test func onlyTheFinalEmptyLineIsUncounted() {
        let s = style(16)
        let line = TextRenderer.lineHeight(for: s)
        let one = TextRenderer.measure("Hi", style: s, maxWidth: 400).height
        for (text, expectedLines) in [("Hi", 1), ("Hi\n", 2), ("Hi\n\n", 3), ("Hi\n\n\n", 4)] {
            let measured = TextRenderer.measure(text, style: s, maxWidth: 400).height
            let box = measured + (text.last?.isNewline == true ? line : 0)
            #expect(box == expectedLines * line,
                    "\(text.debugDescription) sized to \(box)px, wanted \(expectedLines) x \(line)px")
        }
        #expect(one == line)
    }

    /// A line has to be tall enough for the glyphs it holds, at every size, or the
    /// box clips its own text. This is the assertion the old multipliers failed.
    @Test(arguments: [9.0, 11.0, 14.0, 24.0, 48.0, 96.0])
    func aLineIsNeverShorterThanItsText(size: Double) {
        let s = style(size)
        #expect(TextRenderer.lineHeight(for: s)
                >= TextRenderer.measure("Hxgjq", style: s, maxWidth: 4000).height)
    }
}
