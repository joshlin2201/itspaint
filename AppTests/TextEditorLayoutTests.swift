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
        #expect(model.engine.textObjects.first?.frame.width == 111)
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
