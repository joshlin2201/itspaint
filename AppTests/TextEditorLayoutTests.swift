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
@Suite("Text editor layout", .serialized)
@MainActor
struct TextEditorLayoutTests {

    private static var windows: [NSWindow] = []

    private func canvasEditor(model supplied: EditorModel? = nil) throws -> (CanvasNSView, EditorModel, TextEntryView) {
        let model = supplied ?? EditorModel(canvas: Bitmap(width: 600, height: 400, fill: .white))
        model.tool = .text
        let canvas = CanvasNSView(frame: .zero)
        canvas.model = model
        let window = NSWindow(contentRect: canvas.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = canvas
        Self.windows.append(window)
        let point = canvas.convert(NSPoint(x: 40, y: 60), to: nil)
        for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            if type == .leftMouseDown { canvas.mouseDown(with: event) } else { canvas.mouseUp(with: event) }
        }
        return (canvas, model, try #require(canvas.subviews.compactMap { $0 as? TextEntryView }.first))
    }

    @Test("Formatting controls keep the editor open and update highlighted text")
    func formattingKeepsSelection() throws {
        let (canvas, model, view) = try canvasEditor()
        view.insertText("hello world", replacementRange: NSRange(location: 0, length: 0))
        view.setSelectedRange(NSRange(location: 6, length: 5))
        canvas.textDidEndEditing(Notification(name: NSText.didEndEditingNotification, object: view))
        #expect(view.superview === canvas, "clicking formatting committed the text")
        model.textFont = "Georgia"
        let storage = try #require(view.textStorage)
        let first = try #require(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        let selected = try #require(storage.attribute(.font, at: 6, effectiveRange: nil) as? NSFont)
        #expect(first.familyName != selected.familyName, "font change did not target the highlighted word")
    }

    @Test("Multiple text boxes stay editable after finishing, with mixed fonts intact")
    func reopenAndKeepFonts() throws {
        let (canvas, model, view) = try canvasEditor()
        view.insertText("hello world", replacementRange: NSRange(location: 0, length: 0))
        view.setSelectedRange(NSRange(location: 6, length: 5))
        model.textFont = "Georgia"
        canvas.commitText()
        let first = try #require(model.engine.textObjects.first)
        #expect(first.runs.count == 2)
        let object = TextObject(frame: PixelRect(x: 40, y: 220, width: 240, height: 60),
                                runs: [TextRun(text: "another label", style: .init(fontName: "Menlo", pointSize: 24))])
        model.noteChange(model.engine.upsertTextObject(object))
        let window = try #require(canvas.window)
        let point = canvas.convert(NSPoint(x: 100, y: 80), to: nil)
        for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            if type == .leftMouseDown { canvas.mouseDown(with: event) } else { canvas.mouseUp(with: event) }
        }
        let reopened = try #require(canvas.subviews.compactMap { $0 as? TextEntryView }.first)
        #expect(reopened.string == "hello world")
        reopened.setSelectedRange(NSRange(location: 0, length: 5))
        reopened.insertText("hi", replacementRange: reopened.selectedRange())
        canvas.commitText()
        #expect(model.engine.textObjects.count == 2)
        #expect(model.engine.textObjects.first?.runs.map(\.text).joined() == "hi world")
        model.undo()
        #expect(model.engine.textObjects.first == first, "undo did not restore editable text")
        model.redo()
        #expect(model.engine.textObjects.first?.runs.map(\.text).joined() == "hi world")
    }

    @Test("Bold can be switched off and formatting undo preserves the selection")
    func formattingUndoAndTraits() throws {
        let (_, model, view) = try canvasEditor()
        view.insertText("words", replacementRange: NSRange(location: 0, length: 0))
        view.setSelectedRange(NSRange(location: 0, length: 5))
        view.breakUndoCoalescing()
        while let undo = view.undoManager, undo.groupingLevel > 0 { undo.endUndoGrouping() }
        model.toggleTextTrait(\.isTextBold)
        var font = try #require(view.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
        while let undo = view.undoManager, undo.groupingLevel > 0 { undo.endUndoGrouping() }
        model.toggleTextTrait(\.isTextBold)
        font = try #require(view.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(!NSFontManager.shared.traits(of: font).contains(.boldFontMask))
        while let undo = view.undoManager, undo.groupingLevel > 0 { undo.endUndoGrouping() }
        view.undoManager?.undo()
        try #require(view.string == "words")
        font = try #require(view.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
        #expect(view.selectedRange() == NSRange(location: 0, length: 5))
    }

    @Test("Edit-menu undo and redo stay in the active native text session")
    func menuUndoKeepsTextEditor() throws {
        let (canvas, model, view) = try canvasEditor()
        view.insertText("hello", replacementRange: NSRange(location: 0, length: 0))
        view.breakUndoCoalescing()
        while let undo = view.undoManager, undo.groupingLevel > 0 { undo.endUndoGrouping() }
        // A second simulated event needs its own group; the test does not
        // return to AppKit's event loop between the two insertions.
        view.undoManager?.beginUndoGrouping()
        view.insertText(" world", replacementRange: NSRange(location: 5, length: 0))
        view.breakUndoCoalescing()
        while let undo = view.undoManager, undo.groupingLevel > 0 { undo.endUndoGrouping() }
        #expect(view.tryToPerform(Selector(("undo:")), with: nil))
        #expect(view.string == "hello")
        #expect(view.superview === canvas && model.isEditingText)
        #expect(view.tryToPerform(Selector(("redo:")), with: nil))
        #expect(view.string == "hello world")
        #expect(view.superview === canvas && model.isEditingText)
    }

    @Test("Zoom keeps the editor, selection, and document font size")
    func zoomKeepsEditor() throws {
        let (canvas, model, view) = try canvasEditor()
        view.insertText("zoom me", replacementRange: NSRange(location: 0, length: 0))
        view.setSelectedRange(NSRange(location: 0, length: 4))
        let size = model.textSize
        canvas.zoom = 2
        #expect(view.superview === canvas)
        #expect(view.selectedRange() == NSRange(location: 0, length: 4))
        canvas.commitText()
        #expect(try #require(model.engine.textObjects.first?.runs.first).style.pointSize == size)
    }

    @Test("Resizing rewraps and the border does not swallow text selection")
    func resizeAndSelect() throws {
        let (canvas, model, view) = try canvasEditor()
        view.insertText("one two three four five six seven eight nine", replacementRange: NSRange(location: 0, length: 0))
        let before = view.laidOutTextHeight
        let window = try #require(view.window)
        let start = view.convert(NSPoint(x: view.boxBounds.maxX + 2, y: view.boxBounds.midY), to: nil)
        let end = canvas.convert(NSPoint(x: 150, y: 120), to: nil)
        let hitPoint = try #require(canvas.superview).convert(start, from: nil)
        let hit = canvas.hitTest(hitPoint)
        #expect(hit === view,
                "the visible resize handle hit \(String(describing: hit)); editor frame \(view.frame), bounds \(view.bounds)")
        func event(_ type: NSEvent.EventType, _ point: NSPoint) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        let initialFrame = model.engine.textObjects.first?.frame
        view.mouseDown(with: try event(.leftMouseDown, start))
        view.mouseUp(with: try event(.leftMouseUp, start))
        #expect(model.engine.textObjects.first?.frame == initialFrame, "clicking a handle resized without dragging")
        view.mouseDown(with: try event(.leftMouseDown, start))
        view.mouseDragged(with: try event(.leftMouseDragged, end))
        // Assert before mouse-up: the drag must return to AppKit for live redraw.
        #expect(view.laidOutTextHeight > before)
        // The edge travels as far as the pointer did, from where it was.
        #expect(model.engine.textObjects.first?.frame.width == 108)
        view.mouseUp(with: try event(.leftMouseUp, end))
        let box = view.boxBounds
        #expect(!view.isOnBorder(NSPoint(x: box.minX + 2, y: box.midY)))
        #expect(view.handle(at: NSPoint(x: box.minX + 2, y: box.midY)) == nil)
        #expect(view.handle(at: NSPoint(x: box.minX - 2, y: box.midY)) == .left)
        #expect(view.isOnBorder(NSPoint(x: box.minX - 2, y: box.midY)))
    }

    @Test("Rich text with more than 1024 style runs survives finishing")
    func manyStyleRuns() throws {
        let (canvas, model, view) = try canvasEditor()
        let runs = (0..<1025).map { index in
            TextRun(text: "a", style: .init(fontName: index.isMultiple(of: 2) ? "Helvetica" : "Georgia", pointSize: 24))
        }
        view.textStorage?.setAttributedString(TextContent.attributed(runs, zoom: 1))
        view.didChangeText()
        canvas.commitText()
        #expect(model.engine.textObjects.first?.runs.count == 1025)
        #expect(model.engine.textObjects.first?.runs.map(\.text).joined() == String(repeating: "a", count: 1025))
    }

    @Test("An invalid draft cannot be orphaned by another click, image command, or save")
    func invalidDraftStaysOpen() throws {
        let document = DrawingDocument()
        let (canvas, model, view) = try canvasEditor(model: document.model)
        // Programmatic attributed paste can bypass ordinary keystroke preflight.
        view.textStorage?.setAttributedString(NSAttributedString(string: String(repeating: "x", count: 65_537),
                                                                 attributes: TextContent.attributes(.init(pointSize: 24), zoom: 1)))
        view.didChangeText()
        let before = model.engine.canvas
        model.clearImage()
        model.undo()
        #expect(model.engine.canvas == before)
        #expect(model.isEditingText)
        let window = try #require(canvas.window)
        let point = canvas.convert(NSPoint(x: 400, y: 300), to: nil)
        let event = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
                                                   windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        canvas.mouseDown(with: event)
        #expect(canvas.subviews.compactMap { $0 as? TextEntryView }.count == 1)
        #expect(view.superview === canvas)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("invalid-draft-\(UUID().uuidString).itspaint")
        #expect(throws: NSError.self) { try document.write(to: url, ofType: DrawingDocument.packageType) }
        #expect(!FileManager.default.fileExists(atPath: url.path))
        view.cancelOperation(nil)
        #expect(!model.isEditingText)
        #expect(!document.isDocumentEdited)
    }

    @Test("Save and autosave preserve the live editor and its selection")
    func saveKeepsTypingSession() throws {
        let document = DrawingDocument()
        let (canvas, model, view) = try canvasEditor(model: document.model)
        view.insertText("keep editing", replacementRange: NSRange(location: 0, length: 0))
        view.setSelectedRange(NSRange(location: 5, length: 7))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("live-save-\(UUID().uuidString).itspaint")
        defer { try? FileManager.default.removeItem(at: url) }
        try document.write(to: url, ofType: DrawingDocument.packageType)
        #expect(view.superview === canvas)
        #expect(model.isEditingText)
        #expect(view.selectedRange() == NSRange(location: 5, length: 7))
        let saved = DrawingDocument()
        try saved.read(from: url, ofType: DrawingDocument.packageType)
        #expect(saved.model.engine.textObjects.first?.runs.map(\.text).joined() == "keep editing")
        view.insertText("typing", replacementRange: view.selectedRange())
        view.cancelOperation(nil)
        #expect(model.engine.textObjects.first?.runs.map(\.text).joined() == "keep editing")
        #expect(model.canUndo)
    }

    @Test("An unfinished draft is protected on close and Escape restores clean state")
    func draftCancel() throws {
        let document = DrawingDocument()
        let (_, model, view) = try canvasEditor(model: document.model)
        view.insertText("draft", replacementRange: NSRange(location: 0, length: 0))
        #expect(document.isDocumentEdited)
        view.cancelOperation(nil)
        #expect(!document.isDocumentEdited)
        #expect(model.engine.textObjects.isEmpty)
        #expect(!model.canUndo)
    }

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

        var style = TextRenderer.Style(fontName: "Helvetica", pointSize: 24)
        style.colour = .black
        view.textStorage?.setAttributedString(TextContent.attributed([TextRun(text: text, style: style)], zoom: 1))
        let measured = TextRenderer.measure(text, style: style, maxWidth: width)

        let editorHeight = view.laidOutTextHeight
        #expect(abs(editorHeight - CGFloat(measured.height)) <= 1,
                "editor says \(editorHeight), renderer says \(measured.height)")
    }

    @Test("Committed multiline pixels stay at the native editor's line positions")
    func committedLinesMatchNativeEditor() throws {
        let width = 240, height = 180
        let runs = [TextRun(text: "Edit\nme\nlive", style: .init(fontName: "Helvetica", pointSize: 36))]
        let view = editor(width: CGFloat(width), height: CGFloat(height))
        view.textStorage?.setAttributedString(TextContent.attributed(runs, zoom: 1))
        let layout = try #require(view.layoutManager)
        let container = try #require(view.textContainer)
        layout.ensureLayout(for: container)
        let glyphs = layout.glyphRange(for: container)
        var native = Bitmap(width: width, height: height, fill: .white)
        native.drawWithCoreGraphics { context in
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            layout.drawGlyphs(forGlyphRange: glyphs, at: .zero)
            NSGraphicsContext.restoreGraphicsState()
        }
        var committed = Bitmap(width: width, height: height, fill: .white)
        TextRenderer.draw(runs, in: committed.bounds, into: &committed)
        func inkRows(_ bitmap: Bitmap) -> [ClosedRange<Int>] {
            var rows: [ClosedRange<Int>] = []
            var start: Int?
            for y in 0...height {
                let hasInk = y < height && (0..<width).contains { x in
                    let pixel = bitmap.unsafePixel(at: PixelPoint(x: x, y: y))
                    return pixel.r < 100 && pixel.g < 100 && pixel.b < 100
                }
                if hasInk, start == nil { start = y }
                if !hasInk, let first = start { rows.append(first...(y - 1)); start = nil }
            }
            return rows
        }
        let nativeRows = inkRows(native), committedRows = inkRows(committed)
        #expect(nativeRows.count == 3)
        #expect(committedRows.count == nativeRows.count, "a native line disappeared after finishing")
        for (native, committed) in zip(nativeRows, committedRows) {
            #expect(abs(native.lowerBound - committed.lowerBound) <= 1 && abs(native.upperBound - committed.upperBound) <= 1,
                    "native ink at \(native) moved to \(committed) after finishing")
        }
    }

    @Test("Attributed paste and Font panel changes keep saved line metrics and native undo")
    func importedFontsMatchSavedLayout() throws {
        let (canvas, model, view) = try canvasEditor()
        canvas.zoom = 2
        let raw = NSAttributedString(string: "AAA\nBBB\nCCC", attributes: [.font: NSFont(name: "Helvetica", size: 24)!])
        let pasteboard = NSPasteboard(name: .init("ItsPaint-text-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let range = NSRange(location: 0, length: raw.length)
        pasteboard.setData(try raw.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]), forType: .rtf)
        #expect(view.readSelection(from: pasteboard, type: .rtf))
        #expect(view.string == raw.string)
        func checkLayout() {
            let runs = TextContent.runs(view.attributedString(), zoom: 2)
            #expect(runs.allSatisfy { abs($0.style.pointSize - 24) < 0.01 }, "zoom changed imported document font size")
            let measured = TextRenderer.measure(runs, maxWidth: Int(view.boxBounds.width / 2))
            #expect(abs(view.laidOutTextHeight / 2 - CGFloat(measured.height)) <= 1,
                    "imported font preview differs from saved text")
        }
        checkLayout()
        while let undo = view.undoManager, undo.groupingLevel > 0 { undo.endUndoGrouping() }
        view.undoManager?.undo()
        #expect(view.string.isEmpty)
        view.undoManager?.redo()
        #expect(view.string == raw.string)
        checkLayout()
        view.textStorage?.setAttributedString(TextContent.attributed([TextRun(text: raw.string, style: .init(fontName: "Helvetica", pointSize: 24))], zoom: 2))
        view.setSelectedRange(range)
        NSFontManager.shared.setSelectedFont(NSFont(name: "Helvetica", size: 24)!, isMultiple: false)
        view.changeFont(NSFontManager.shared)
        #expect(view.selectedRange() == range)
        checkLayout()
        #expect(model.engine.textObjects.first?.runs.map(\.text).joined() == raw.string)
        #expect(view.writeSelection(to: pasteboard, type: .rtf))
        let copied = try NSAttributedString(data: #require(pasteboard.data(forType: .rtf)),
                                           options: [.documentType: NSAttributedString.DocumentType.rtf],
                                           documentAttributes: nil)
        #expect(TextContent.runs(copied, zoom: 1).allSatisfy { abs($0.style.pointSize - 24) < 0.01 },
                "copy exported the zoomed display size instead of document points")
        let (otherCanvas, otherModel, otherView) = try canvasEditor()
        otherCanvas.zoom = 2
        #expect(otherView.readSelection(from: pasteboard, type: .rtf))
        #expect(otherModel.engine.textObjects.first?.runs.allSatisfy { abs($0.style.pointSize - 24) < 0.01 } == true)
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

/// What a drag does, and what the pointer says while it does it.
///
/// Events go straight to the views, in order, so nothing here needs a window
/// server or the focus. `NSCursor.current` reads back what the app last set.
extension TextEditorLayoutTests {
    private func mouse(_ type: NSEvent.EventType, _ point: NSPoint, _ window: NSWindow, clicks: Int = 1) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                                        windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                        clickCount: clicks, pressure: 1))
    }

    /// A press at `start` in `view`'s coordinates and `steps` drags to `start + delta`.
    /// The whole path is worked out first, because a moved view moves its coordinates.
    private func drag(_ view: NSView, from start: NSPoint, by delta: NSPoint, steps: Int = 1,
                      release: Bool = true) throws {
        let window = try #require(view.window)
        let path = (0...steps).map { step in
            view.convert(NSPoint(x: start.x + delta.x * Double(step) / Double(steps),
                                 y: start.y + delta.y * Double(step) / Double(steps)), to: nil)
        }
        view.mouseDown(with: try mouse(.leftMouseDown, path[0], window))
        for point in path.dropFirst() { view.mouseDragged(with: try mouse(.leftMouseDragged, point, window)) }
        if release { view.mouseUp(with: try mouse(.leftMouseUp, path[steps], window)) }
    }

    private func click(_ view: NSView, at point: NSPoint, clicks: Int = 1) throws {
        let window = try #require(view.window)
        let at = view.convert(point, to: nil)
        view.mouseDown(with: try mouse(.leftMouseDown, at, window, clicks: clicks))
        view.mouseUp(with: try mouse(.leftMouseUp, at, window, clicks: clicks))
    }

    private func typed(_ text: String = "hello") throws -> (CanvasNSView, EditorModel, TextEntryView) {
        let (canvas, model, view) = try canvasEditor()
        view.insertText(text, replacementRange: NSRange(location: 0, length: 0))
        return (canvas, model, view)
    }

    private func border(_ view: TextEntryView) -> NSPoint {
        NSPoint(x: view.boxBounds.minX + view.boxBounds.width / 4, y: view.boxBounds.minY - 4)
    }

    private func frame(_ model: EditorModel) throws -> PixelRect {
        try #require(model.engine.textObjects.first).frame
    }

    private func canvas(for model: EditorModel) -> CanvasNSView {
        let canvas = CanvasNSView(frame: .zero)
        canvas.model = model
        let window = NSWindow(contentRect: canvas.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = canvas
        Self.windows.append(window)
        return canvas
    }

    private func floatingModel() -> EditorModel {
        let model = EditorModel(canvas: Bitmap(width: 600, height: 400, fill: .white))
        _ = model.engine.paste(Bitmap(width: 200, height: 200, fill: .black))
        model.syncFromEngine()
        return model
    }

    @Test("A slow drag at high zoom keeps up with the pointer")
    func slowDragAtHighZoom() throws {
        let (canvas, model, view) = try typed()
        canvas.zoom = 4
        let before = try frame(model)
        try drag(view, from: border(view), by: NSPoint(x: 80, y: 40), steps: 80)
        #expect(try frame(model).minX == before.minX + 20)
        #expect(try frame(model).minY == before.minY + 10)
    }

    @Test("A box stopped by the edge is back under the pointer when the pointer returns")
    func edgeDoesNotUnhookTheBox() throws {
        let (_, model, view) = try typed()
        let before = try frame(model)
        let start = border(view)
        let window = try #require(view.window)
        let at = { (x: Double) in view.convert(NSPoint(x: start.x + x, y: start.y), to: nil) }
        let (home, away, back) = (at(0), at(-200), at(-10))
        view.mouseDown(with: try mouse(.leftMouseDown, home, window))
        view.mouseDragged(with: try mouse(.leftMouseDragged, away, window))
        #expect(try frame(model).minX == 0)
        view.mouseDragged(with: try mouse(.leftMouseDragged, back, window))
        view.mouseUp(with: try mouse(.leftMouseUp, back, window))
        #expect(try frame(model).minX == before.minX - 10)
    }

    @Test("A moved box lands on the alignment grid, as a paste does")
    func moveSnaps() throws {
        let (_, model, view) = try typed()
        model.snapGrid = 16
        try drag(view, from: border(view), by: NSPoint(x: 27, y: 19))
        #expect(try frame(model).minX % 16 == 0)
        #expect(try frame(model).minY % 16 == 0)
    }

    @Test("The bottom handle makes the box taller, and it stays taller")
    func bottomHandleResizes() throws {
        let (_, model, view) = try typed()
        let before = try frame(model)
        try drag(view, from: NSPoint(x: view.boxBounds.midX, y: view.boxBounds.maxY + 2), by: NSPoint(x: 0, y: 80))
        #expect(try frame(model).height == before.height + 80)
        view.insertText("!", replacementRange: NSRange(location: 5, length: 0))
        #expect(try frame(model).height == before.height + 80)
    }

    @Test("The top handle resizes from the top and leaves the bottom edge where it was")
    func topHandleResizes() throws {
        let (_, model, view) = try typed()
        let before = try frame(model)
        try drag(view, from: NSPoint(x: view.boxBounds.midX, y: view.boxBounds.minY - 2), by: NSPoint(x: 0, y: -30))
        #expect(try frame(model).minY == before.minY - 30)
        #expect(try frame(model).maxY == before.maxY)
    }

    @Test("A top handle cannot crush the text, and the bottom edge still holds")
    func topHandleStopsAtTheText() throws {
        let (_, model, view) = try typed()
        let before = try frame(model)
        try drag(view, from: NSPoint(x: view.boxBounds.midX, y: view.boxBounds.minY - 2), by: NSPoint(x: 0, y: 300))
        #expect(try frame(model) == before)
    }

    @Test("A top corner dragged sideways leaves the top edge, and the rewrap grows the bottom")
    func sidewaysTopCorner() throws {
        let (_, model, view) = try typed("hello world again")
        let before = try frame(model)
        try drag(view, from: NSPoint(x: view.boxBounds.maxX + 2, y: view.boxBounds.minY - 2), by: NSPoint(x: -140, y: 0))
        #expect(try frame(model).minY == before.minY)
        #expect(try frame(model).width == before.width - 140)
        #expect(try frame(model).height > before.height)
    }

    @Test("Sideways travel gives the box no height of its own to keep")
    func sidewaysSetsNoFloor() throws {
        let (_, model, view) = try typed("hello world again")
        let before = try frame(model)
        let corner = NSPoint(x: view.boxBounds.maxX + 2, y: view.boxBounds.maxY + 2)
        try drag(view, from: corner, by: NSPoint(x: -140, y: 0))
        #expect(try frame(model).height > before.height)
        try drag(view, from: NSPoint(x: view.boxBounds.maxX + 2, y: view.boxBounds.maxY + 2), by: NSPoint(x: 140, y: 0))
        #expect(try frame(model).height == before.height)
    }

    @Test("A landed box that fitted its text still follows it when reopened, and a tall one stays")
    func reopenedFloor() throws {
        let (canvas, model, view) = try typed("one\ntwo\nthree")
        view.didChangeText()
        let grown = try frame(model)
        let away = NSPoint(x: 500, y: 350)
        try click(canvas, at: away)
        try click(canvas, at: NSPoint(x: grown.minX + 4, y: grown.minY + 4))
        let reopened = try #require(canvas.subviews.compactMap { $0 as? TextEntryView }.first)
        reopened.selectAll(nil)
        reopened.insertText("one", replacementRange: reopened.selectedRange())
        #expect(try frame(model).height < grown.height)
    }

    @Test("Pressing a handle off-centre does not make the edge jump to the pointer")
    func handleDoesNotJump() throws {
        let (_, model, view) = try typed()
        let before = try frame(model)
        try drag(view, from: NSPoint(x: view.boxBounds.maxX + 6, y: view.boxBounds.midY), by: NSPoint(x: 1, y: 0))
        #expect(try frame(model).width == before.width + 1)
    }

    @Test("A box dragged out tall keeps its height through the first keystroke")
    func draggedOutHeightSurvivesTyping() throws {
        let model = EditorModel(canvas: Bitmap(width: 600, height: 400, fill: .white))
        model.tool = .text
        let canvas = canvas(for: model)
        try drag(canvas, from: NSPoint(x: 40, y: 60), by: NSPoint(x: 300, y: 200))
        let view = try #require(canvas.subviews.compactMap { $0 as? TextEntryView }.first)
        view.insertText("a", replacementRange: NSRange(location: 0, length: 0))
        #expect(try frame(model).height >= 200)
    }

    @Test("The hand closes on the box and stays closed for the whole drag")
    func moveCursor() throws {
        let (_, _, view) = try typed()
        try drag(view, from: border(view), by: NSPoint(x: 30, y: 0), steps: 3, release: false)
        #expect(NSCursor.current === NSCursor.closedHand)
        view.mouseUp(with: try mouse(.leftMouseUp, view.convert(border(view), to: nil), try #require(view.window)))
        #expect(NSCursor.current === NSCursor.openHand)
    }

    @Test("A handle keeps its arrows for the whole drag, wherever the pointer goes")
    func resizeCursor() throws {
        let (_, _, view) = try typed()
        try drag(view, from: NSPoint(x: view.boxBounds.midX, y: view.boxBounds.maxY + 2), by: NSPoint(x: 0, y: -200),
                 steps: 3, release: false)
        #expect(NSCursor.current === CanvasNSView.cursor(for: .bottom))
    }

    @Test("The grab area under the arrows is the one the press uses, on a short box too")
    func cursorAndHitAgree() throws {
        let model = EditorModel(canvas: Bitmap(width: 600, height: 400, fill: .white))
        model.engine.settings.textStyle.pointSize = 12
        let (_, _, view) = try canvasEditor(model: model)
        for x in stride(from: 0.0, to: view.bounds.width, by: 1) {
            for y in stride(from: 0.0, to: view.bounds.height, by: 1) {
                let point = NSPoint(x: x, y: y)
                guard view.isOnBorder(point) else { continue }
                let arrows = view.handleSpots.contains { $0.spot.contains(point) }
                #expect((view.handle(at: point) != nil) == arrows, "at \(point)")
            }
        }
    }

    @Test("Clicking away lands the box and opens nothing; the next click starts one")
    func clickAwayOnlyLands() throws {
        let (canvas, model, _) = try typed()
        let empty = NSPoint(x: 400, y: 300)
        try click(canvas, at: empty)
        #expect(!model.isEditingText)
        #expect(model.engine.textObjects.count == 1)
        try click(canvas, at: empty)
        #expect(model.isEditingText)
    }

    @Test("Dragging out from an open box still starts the next box in one gesture")
    func dragAwayStartsANewBox() throws {
        let (canvas, model, _) = try typed()
        try drag(canvas, from: NSPoint(x: 300, y: 200), by: NSPoint(x: 120, y: 80))
        #expect(model.isEditingText)
    }

    @Test("A double-click opens a box for the Select tool and leaves every other tool alone")
    func doubleClickIsForSelect() throws {
        let (canvas, model, _) = try typed()
        try click(canvas, at: NSPoint(x: 500, y: 350))
        let inside = NSPoint(x: 60, y: 70)
        model.tool = .eyedropper
        try click(canvas, at: inside, clicks: 2)
        #expect(model.tool == .eyedropper)
        #expect(!model.isEditingText)
        model.tool = .select
        try click(canvas, at: inside, clicks: 2)
        #expect(model.tool == .text)
        #expect(model.isEditingText)
    }

    @Test("Reopening a box that hangs off the canvas leaves its frame and wrap alone")
    func reopenKeepsTheOverhang() throws {
        let (canvas, model, view) = try typed()
        try drag(view, from: border(view), by: NSPoint(x: 500, y: 0))
        let moved = try frame(model)
        #expect(moved.maxX > 600)
        try click(canvas, at: NSPoint(x: 20, y: 380))
        try click(canvas, at: NSPoint(x: moved.minX + 2, y: moved.minY + 2))
        #expect(model.isEditingText)
        // Landing is what writes the box back, so that is what has to be read.
        try click(canvas, at: NSPoint(x: 20, y: 380))
        #expect(try frame(model) == moved)
    }

    @Test("With the Text tool, a press on a paste carries it, as the cursor said it would")
    func textToolCarriesAPaste() throws {
        // In this order: picking a tool lands whatever is floating.
        let model = EditorModel(canvas: Bitmap(width: 600, height: 400, fill: .white))
        model.tool = .text
        _ = model.engine.paste(Bitmap(width: 200, height: 200, fill: .black))
        model.syncFromEngine()
        let canvas = canvas(for: model)
        let before = try #require(model.floating).frame
        try drag(canvas, from: NSPoint(x: before.minX + 100, y: before.minY + 100), by: NSPoint(x: 40, y: 30))
        #expect(!model.isEditingText)
        #expect(try #require(model.floating).frame.minX == before.minX + 40)
    }

    @Test("Carrying a paste closes the hand, resizing one keeps the arrow, and letting go restores")
    func carryCursors() throws {
        let model = floatingModel()
        model.tool = .select
        let canvas = canvas(for: model)
        let box = try #require(model.floating).frame
        try drag(canvas, from: NSPoint(x: box.minX + 100, y: box.minY + 100), by: NSPoint(x: 20, y: 0), release: false)
        #expect(NSCursor.current === NSCursor.closedHand)
        let window = try #require(canvas.window)
        canvas.mouseUp(with: try mouse(.leftMouseUp, canvas.convert(NSPoint(x: box.minX + 120, y: box.minY + 100), to: nil), window))
        #expect(NSCursor.current === NSCursor.openHand)

        let moved = try #require(model.floating).frame
        let corner = NSPoint(x: moved.maxX - 1, y: moved.maxY - 1)
        try drag(canvas, from: corner, by: NSPoint(x: 30, y: 30), release: false)
        #expect(NSCursor.current === CanvasNSView.cursor(for: .bottomRight))
    }

    @Test("A paste's handle, pressed off-centre, moves the edge by the drag and no more")
    func pasteHandleDoesNotJump() throws {
        let model = floatingModel()
        model.tool = .select
        let canvas = canvas(for: model)
        let box = try #require(model.floating).frame
        try drag(canvas, from: NSPoint(x: box.maxX + 2, y: box.maxY + 2), by: NSPoint(x: 1, y: 1))
        #expect(try #require(model.floating).frame.width == box.width + 1)
    }

    @Test("A mouse-up the app never saw cannot strand a text box being dragged out")
    func dragOutDoesNotStick() throws {
        let model = EditorModel(canvas: Bitmap(width: 600, height: 400, fill: .white))
        model.tool = .text
        let canvas = canvas(for: model)
        try drag(canvas, from: NSPoint(x: 50, y: 50), by: NSPoint(x: 100, y: 80), release: false)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: canvas.window)
        model.tool = .pencil
        let before = model.canvas
        try drag(canvas, from: NSPoint(x: 100, y: 200), by: NSPoint(x: 50, y: 0))
        #expect(model.canvas != before)
        #expect(!model.isEditingText)
    }

    @Test("A key-up the app never saw cannot leave the canvas in pan mode")
    func spaceDoesNotStick() throws {
        let model = EditorModel(canvas: Bitmap(width: 600, height: 400, fill: .white))
        model.tool = .pencil
        let canvas = canvas(for: model)
        let window = try #require(canvas.window)
        let space = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                  windowNumber: window.windowNumber, context: nil, characters: " ",
                                                  charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49))
        canvas.keyDown(with: space)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        let before = model.canvas
        try drag(canvas, from: NSPoint(x: 100, y: 100), by: NSPoint(x: 50, y: 0))
        #expect(model.canvas != before)
    }
}
