import AppKit
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
