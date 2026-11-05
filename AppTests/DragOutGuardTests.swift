import AppKit
import PaintKit
import Testing
@testable import ItsPaint

/// The answers the drag-out surface gives the titlebar, and the lock it holds on
/// the window while the pointer is over it. Issue #28: the window moved with the
/// pointer on 0.19.0, which already said `mouseDownCanMoveWindow` was false —
/// so the flag alone was not the guard, and this pins the rest of it.
@Suite("Drag-out guard")
@MainActor
struct DragOutGuardTests {
    private func surfaceInWindow() -> (NSWindow, DragOutSurface.DragSurfaceView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        let view = DragOutSurface.DragSurfaceView(frame: NSRect(x: 10, y: 150, width: 26, height: 26))
        window.contentView?.addSubview(view)
        return (window, view)
    }

    private func enterExit(_ type: NSEvent.EventType, in window: NSWindow) throws -> NSEvent {
        try #require(NSEvent.enterExitEvent(
            with: type, location: NSPoint(x: 20, y: 160), modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0,
            userData: nil
        ))
    }

    @Test("The titlebar is told no, and the first click is taken")
    func answersToTheTitlebar() {
        let (_, view) = surfaceInWindow()
        #expect(view.mouseDownCanMoveWindow == false)
        #expect(view.acceptsFirstMouse(for: nil) == true)
    }

    @Test("The window is locked while the pointer is on the handle, and only then")
    func locksTheWindowUnderThePointer() throws {
        let (window, view) = surfaceInWindow()
        #expect(window.isMovable)

        view.mouseEntered(with: try enterExit(.mouseEntered, in: window))
        #expect(window.isMovable == false)

        // A press that ends on the handle keeps the lock: the pointer is still there.
        view.releaseLock(pointerInWindow: NSPoint(x: 20, y: 160))
        #expect(window.isMovable == false)

        // A drop that lands elsewhere lets go.
        view.releaseLock(pointerInWindow: NSPoint(x: 200, y: 20))
        #expect(window.isMovable)

        view.mouseEntered(with: try enterExit(.mouseEntered, in: window))
        #expect(window.isMovable == false)
        view.mouseExited(with: try enterExit(.mouseExited, in: window))
        #expect(window.isMovable)
    }

    @Test("Leaving the window leaves it movable")
    func leavingTheWindowUnlocksIt() throws {
        let (window, view) = surfaceInWindow()
        view.mouseEntered(with: try enterExit(.mouseEntered, in: window))
        #expect(window.isMovable == false)
        view.removeFromSuperview()
        #expect(window.isMovable)
    }
}

/// A fast second click on the header is not a titlebar double-click. The header
/// sits in the titlebar band of a `.fullSizeContentView` window, and a click no
/// enabled control claims used to zoom the window: on Undo once the history ran
/// out mid-burst, and on the padding and gaps around the cells.
///
/// Real events through the real queue, because the titlebar is what is under
/// test: `NSApp.postEvent` takes the path a mouse takes, and the gesture that
/// zooms the window only exists on that path.
@Suite("Header rapid clicks", .serialized)
@MainActor
struct HeaderRapidClickTests {
    /// Holds the document for as long as the window: nothing else does in a test,
    /// and closing a window whose document has gone crashes in `-[NSWindow _close]`.
    @MainActor
    private struct Fixture {
        let document: DrawingDocument
        let window: NSWindow
        let history: [Bitmap]

        var undone: Int? {
            history.lastIndex(of: document.model.canvas).map { history.count - 1 - $0 }
        }
    }

    private func openWindow(strokes: Int = 0) async throws -> Fixture {
        let document = DrawingDocument()
        document.makeWindowControllers()
        document.showWindows()
        let window = try #require(document.windowControllers.first?.window)
        window.setContentSize(NSSize(width: 1100, height: 620))
        window.center()

        // A test host launched in the background cannot activate itself, and the
        // case that matters is the front window. `open` is how it gets there.
        let activate = Process()
        activate.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        activate.arguments = [Bundle.main.bundlePath]
        if (try? activate.run()) != nil { activate.waitUntilExit() }
        for _ in 0..<40 where !NSApp.isActive { try await Task.sleep(for: .milliseconds(50)) }
        window.makeKeyAndOrderFront(nil)

        let model = document.model
        model.selectTool(.pencil)
        var history = [model.canvas]
        for i in 0..<strokes {
            _ = model.engine.beginStroke(at: PixelPoint(x: 5 + i * 10, y: 10))
            model.noteChange(model.engine.endStroke(at: PixelPoint(x: 5 + i * 10, y: 70)))
            history.append(model.canvas)
        }
        try await Task.sleep(for: .milliseconds(400))
        return Fixture(document: document, window: window, history: history)
    }

    /// The working cluster and the document actions, left to right, as laid out.
    private func clusters(in window: NSWindow) throws -> [NSRect] {
        var found: [NSRect] = []
        func walk(_ view: NSView) {
            if view is TitlebarClickGuard.GuardView {
                found.append(view.convert(view.bounds, to: nil))
            }
            view.subviews.forEach(walk)
        }
        walk(try #require(window.contentView))
        return found.sorted { $0.minX < $1.minX }
    }

    private func undoCell(in window: NSWindow) throws -> NSPoint {
        let working = try #require(clusters(in: window).first)
        let history = working.minX + Tokens.Header.clipboard + Tokens.Space.tight
        return NSPoint(x: history + Tokens.Header.groupPad / 2 + Tokens.Header.cell / 2, y: working.midY)
    }

    private func redoCell(in window: NSWindow) throws -> NSPoint {
        var point = try undoCell(in: window)
        point.x += Tokens.Header.cell + Tokens.Header.cellGap
        return point
    }

    private func event(_ type: NSEvent.EventType, _ point: NSPoint, clicks: Int, _ window: NSWindow) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0,
            clickCount: clicks, pressure: type == .leftMouseDown ? 1 : 0
        ))
    }

    private func press(_ type: NSEvent.EventType, _ point: NSPoint, clicks: Int, _ window: NSWindow) throws {
        NSApp.postEvent(try event(type, point, clicks: clicks, window), atStart: false)
    }

    /// One burst of clicks close enough together that AppKit numbers them 1, 2, 3,
    /// which is what a fast finger produces.
    private func clicks(_ count: Int, at point: NSPoint, in window: NSWindow) async throws {
        for click in 1...count {
            try press(.leftMouseDown, point, clicks: click, window)
            try press(.leftMouseUp, point, clicks: click, window)
            try await Task.sleep(for: .milliseconds(70))
        }
        try await Task.sleep(for: .milliseconds(500))
    }

    @Test("Two fast clicks on Undo undo twice and leave the window alone")
    func doubleClickOnUndo() async throws {
        let fixture = try await openWindow(strokes: 5)
        defer { fixture.window.close() }
        let frame = fixture.window.frame

        try await clicks(2, at: try undoCell(in: fixture.window), in: fixture.window)

        #expect(fixture.window.frame == frame)
        #expect(fixture.undone == 2)
    }

    @Test("Six fast clicks on Undo undo six times")
    func burstOnUndo() async throws {
        let fixture = try await openWindow(strokes: 8)
        defer { fixture.window.close() }
        let frame = fixture.window.frame

        try await clicks(6, at: try undoCell(in: fixture.window), in: fixture.window)

        #expect(fixture.window.frame == frame)
        #expect(fixture.undone == 6)
    }

    @Test("Clicking past the end of the history does not zoom the window")
    func clicksPastTheEndOfHistory() async throws {
        let fixture = try await openWindow(strokes: 2)
        defer { fixture.window.close() }
        let frame = fixture.window.frame

        try await clicks(5, at: try undoCell(in: fixture.window), in: fixture.window)

        #expect(fixture.window.frame == frame)
        #expect(fixture.undone == 2)
    }

    @Test("A disabled Redo does not zoom the window either")
    func disabledRedoIsNotTitlebar() async throws {
        let fixture = try await openWindow(strokes: 1)
        defer { fixture.window.close() }
        let frame = fixture.window.frame

        try await clicks(2, at: try redoCell(in: fixture.window), in: fixture.window)

        #expect(fixture.window.frame == frame)
    }

    @Test("A double-click on the capsule around a cell does not zoom the window")
    func capsulePaddingIsNotTitlebar() async throws {
        let fixture = try await openWindow(strokes: 5)
        defer { fixture.window.close() }
        let frame = fixture.window.frame
        var point = try undoCell(in: fixture.window)
        // Above the 26pt cell, still inside the 32pt capsule.
        point.y += 14

        try await clicks(2, at: point, in: fixture.window)

        #expect(fixture.window.frame == frame)
    }

    @Test("A double-click in the gap between two capsules does not zoom the window")
    func gapBetweenCapsulesIsNotTitlebar() async throws {
        let fixture = try await openWindow()
        defer { fixture.window.close() }
        let frame = fixture.window.frame
        let working = try #require(clusters(in: fixture.window).first)
        let gap = NSPoint(x: working.minX + Tokens.Header.clipboard + Tokens.Space.tight / 2, y: working.midY)

        try await clicks(2, at: gap, in: fixture.window)

        #expect(fixture.window.frame == frame)
    }

    @Test("The Window menu's Zoom still zooms, right after a burst on the header")
    func menuZoomStillZooms() async throws {
        let fixture = try await openWindow()
        defer { fixture.window.close() }
        let frame = fixture.window.frame
        try await clicks(2, at: try undoCell(in: fixture.window), in: fixture.window)
        #expect(fixture.window.frame == frame)

        fixture.window.performZoom(NSMenuItem())
        try await Task.sleep(for: .milliseconds(500))

        #expect(fixture.window.frame != frame)
    }

    /// The decision on its own, for both ends of the click: the system asks on
    /// the mouse-up on macOS 15. This is the one that means something on CI, because
    /// the runner's macOS 15 passes the tests above with or without `DocumentWindow`.
    @Test("Only a repeat click over the header is refused a zoom")
    func refusalStaysOnTheHeader() async throws {
        let fixture = try await openWindow()
        defer { fixture.window.close() }
        let window = try #require(fixture.window as? DocumentWindow)
        let cell = try undoCell(in: window)
        let working = try #require(clusters(in: window).first)
        let empty = NSPoint(x: working.maxX + 40, y: working.midY)

        #expect(window.isRepeatClickOnHeader(try event(.leftMouseDown, cell, clicks: 2, window)))
        #expect(window.isRepeatClickOnHeader(try event(.leftMouseUp, cell, clicks: 2, window)))
        #expect(!window.isRepeatClickOnHeader(try event(.leftMouseDown, cell, clicks: 1, window)))
        #expect(!window.isRepeatClickOnHeader(try event(.leftMouseDown, empty, clicks: 2, window)))
        #expect(!window.isRepeatClickOnHeader(nil))
    }

    /// macOS 27 only. On the CI runner's macOS 15 a posted double-click does not
    /// reliably reach the titlebar, with or without `DocumentWindow`, so this would
    /// be testing the runner.
    @Test("A double-click on the empty titlebar still zooms the window",
          .enabled(if: ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27))
    func emptyTitlebarStillZooms() async throws {
        let fixture = try await openWindow()
        defer { fixture.window.close() }
        let frame = fixture.window.frame
        let working = try #require(clusters(in: fixture.window).first)
        // Clear of the filename, the centred cluster and the document actions.
        let empty = NSPoint(x: working.maxX + 40, y: working.midY)

        try await clicks(2, at: empty, in: fixture.window)

        #expect(fixture.window.frame != frame)
    }
}
