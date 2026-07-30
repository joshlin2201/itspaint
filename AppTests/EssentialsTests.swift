import AppKit
import Foundation
import PaintKit
import Testing
@testable import ItsPaint

/// The commands every Mac user expects to work on day one.
///
/// These are boring on purpose. Cut / copy / paste / undo / redo are the first
/// things anyone tries, and the first things they notice broken — so they get
/// real round-trip coverage through the actual pasteboard rather than an
/// assumption that the plumbing is fine.
@Suite("Essentials — clipboard and history", .serialized)
@MainActor
struct EssentialsTests {

    private func markedModel() -> EditorModel {
        let model = EditorModel(canvas: Bitmap(width: 120, height: 120, fill: .white))
        model.selectTool(.shape)
        model.shapeKind = .rectangle
        model.shapeStyle = .filled
        model.brushSize = 1
        model.background = PaintColour(hex: "FF0000")!
        _ = model.engine.beginStroke(at: PixelPoint(x: 19, y: 19))
        model.noteChange(model.engine.endStroke(at: PixelPoint(x: 61, y: 61)))
        model.background = .white
        return model
    }

    private func select(_ model: EditorModel, _ a: PixelPoint, _ b: PixelPoint) {
        model.selectTool(.select)
        _ = model.engine.beginStroke(at: a)
        _ = model.engine.endStroke(at: b)
    }

    @Test("Copy then paste round-trips through the real pasteboard")
    func copyPasteRoundTrip() throws {
        let red = PaintColour(hex: "FF0000")!.rgba8
        let model = markedModel()
        select(model, PixelPoint(x: 20, y: 20), PixelPoint(x: 50, y: 50))
        model.copySelection()

        // A different document must receive it — that is the point of a
        // clipboard, and an in-process shortcut would not prove it.
        let other = EditorModel(canvas: Bitmap(width: 200, height: 200, fill: .white))
        #expect(other.canPaste)
        other.paste()

        let floating = try #require(other.floating)
        #expect(floating.bitmap.pixels.contains(red))
        other.engine.commitFloating()
        #expect(other.canvas.pixels.contains(red))
    }

    @Test("Cut removes the pixels and puts them on the pasteboard")
    func cutRemovesAndCopies() throws {
        let red = PaintColour(hex: "FF0000")!.rgba8
        let model = markedModel()
        select(model, PixelPoint(x: 20, y: 20), PixelPoint(x: 50, y: 50))
        model.cutSelection()

        // Gone from the canvas...
        #expect(model.canvas.pixel(at: PixelPoint(x: 35, y: 35)) != red)
        // ...and available to paste.
        let other = EditorModel(canvas: Bitmap(width: 200, height: 200, fill: .white))
        other.paste()
        #expect(try #require(other.floating).bitmap.pixels.contains(red))
    }

    @Test("Cut is undoable")
    func cutUndoes() {
        let model = markedModel()
        let before = model.canvas
        select(model, PixelPoint(x: 20, y: 20), PixelPoint(x: 50, y: 50))
        model.cutSelection()
        #expect(model.canvas != before)

        model.undo()
        #expect(model.canvas == before)
    }

    @Test("Undo and redo walk the full history in both directions")
    func historyWalks() {
        let model = EditorModel(canvas: Bitmap(width: 80, height: 80, fill: .white))
        let pristine = model.canvas
        model.selectTool(.pencil)

        var snapshots: [Bitmap] = []
        for i in 0..<6 {
            _ = model.engine.beginStroke(at: PixelPoint(x: 5 + i * 10, y: 10))
            model.noteChange(model.engine.endStroke(at: PixelPoint(x: 5 + i * 10, y: 70)))
            snapshots.append(model.canvas)
        }

        for _ in 0..<6 { model.undo() }
        #expect(model.canvas == pristine)
        #expect(!model.canUndo)

        for index in 0..<6 {
            model.redo()
            #expect(model.canvas == snapshots[index], "redo \(index) diverged")
        }
        #expect(!model.canRedo)
    }

    @Test("Undo names the operation, so the Edit menu reads 'Undo Pencil'")
    func undoIsNamed() {
        let model = EditorModel(canvas: Bitmap(width: 40, height: 40))
        model.selectTool(.pencil)
        _ = model.engine.beginStroke(at: PixelPoint(x: 5, y: 5))
        model.noteChange(model.engine.endStroke())
        #expect(model.engine.undoStack.undoActionName == "Pencil")
    }

    @Test("Select all covers the canvas and deselect clears it")
    func selectAllAndDeselect() {
        let model = markedModel()
        model.selectAll()
        #expect(model.selectionBounds == model.canvas.bounds)

        model.deselect()
        #expect(model.selection == nil)
    }

    @Test("Copy and cut work from a lasso, through the pasteboard")
    func lassoClipboard() throws {
        // The freeform tools have to reach the clipboard like any other
        // selection — with the traced shape, not its bounding box.
        let model = markedModel()
        model.selectTool(.select)
        model.selectionKind = .lasso
        _ = model.engine.beginStroke(at: PixelPoint(x: 25, y: 25))
        _ = model.engine.continueStroke(to: PixelPoint(x: 58, y: 25))
        _ = model.engine.continueStroke(to: PixelPoint(x: 58, y: 58))
        model.noteChange(model.engine.endStroke(at: PixelPoint(x: 25, y: 25)))
        #expect(model.selection?.isRectangular == false)

        model.copySelection()
        let other = EditorModel(canvas: Bitmap(width: 200, height: 200, fill: .white))
        other.paste()
        let floating = try #require(other.floating)
        // Outside the traced triangle stays transparent through the round trip.
        #expect(try #require(floating.bitmap.pixel(at: PixelPoint(x: 2, y: 30))).a == 0)
    }

    @Test("Escape clears a lasso selection")
    func escapeClearsLasso() throws {
        let model = markedModel()
        model.selectTool(.select)
        model.selectionKind = .lasso
        _ = model.engine.beginStroke(at: PixelPoint(x: 25, y: 25))
        _ = model.engine.continueStroke(to: PixelPoint(x: 58, y: 25))
        _ = model.engine.continueStroke(to: PixelPoint(x: 58, y: 58))
        _ = model.engine.endStroke(at: PixelPoint(x: 25, y: 25))
        #expect(model.hasSelection)

        // Through the real key handler, not `deselect()` — the binding is the
        // thing under test, and a test that skips it passes with Escape unbound.
        let view = CanvasNSView()
        view.model = model
        view.keyDown(with: try #require(escapeKey()))
        #expect(!model.hasSelection)
    }

    /// A synthetic Escape, for driving the canvas's own key handling.
    private func escapeKey() -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53
        )
    }

    @Test("Delete clears the selection without touching the rest")
    func deleteSelection() {
        let red = PaintColour(hex: "FF0000")!.rgba8
        let model = markedModel()
        select(model, PixelPoint(x: 20, y: 20), PixelPoint(x: 40, y: 40))
        model.deleteSelection()

        #expect(model.canvas.pixel(at: PixelPoint(x: 30, y: 30)) != red)
        // Outside the marquee the block survives.
        #expect(model.canvas.pixel(at: PixelPoint(x: 55, y: 55)) == red)
    }

    /// The actions bar reads `hasFloatingContent`, and the engine it asks is not
    /// observable — so this checks the mirror, not the engine. Placing and then
    /// undoing past the placement is the case that used to leave the bar up with
    /// nothing to place.
    @Test("The floating flag follows the content through place, undo and redo")
    func floatingFlagFollowsHistory() {
        let model = markedModel()
        select(model, PixelPoint(x: 20, y: 20), PixelPoint(x: 50, y: 50))
        #expect(!model.hasFloatingContent)

        model.copySelection()
        model.paste()
        #expect(model.hasFloatingContent)

        // The value going false is not enough — the bar only goes away if
        // SwiftUI is *told*. A computed passthrough to the engine registers no
        // dependency here, which is the whole bug: correct answer, never asked
        // for again.
        // `onChange` is `@Sendable`, and it fires synchronously on whichever
        // thread mutated — here, this one.
        nonisolated(unsafe) var notified = false
        withObservationTracking { _ = model.hasFloatingContent } onChange: { notified = true }

        model.placeFloating()
        #expect(!model.hasFloatingContent)
        #expect(notified, "nothing invalidates the bar, so it stays up over nothing")

        // Undoing the placement, then the edit under it. Neither leaves anything
        // floating, so neither should leave the bar up.
        model.undo()
        #expect(!model.hasFloatingContent)
        model.undo()
        #expect(!model.hasFloatingContent)

        model.redo()
        #expect(!model.hasFloatingContent)
    }
}

@Suite("Essentials — shortcuts and tools")
struct ShortcutTests {

    @Test("Every tool shortcut is unique")
    func uniqueShortcuts() {
        let shortcuts = ToolKind.allCases.map(\.shortcut)
        #expect(Set(shortcuts).count == ToolKind.allCases.count)
    }

    @Test("No tool claims X — that belongs to swapping colours")
    func xIsReserved() {
        #expect(!ToolKind.allCases.map(\.shortcut).contains("x"))
    }

    @Test("Only marking tools show a brush footprint")
    func footprintScope() {
        // A ring around the fill bucket or the eyedropper would imply an area
        // those tools do not have.
        #expect(ToolKind.pencil.showsBrushPreview)
        #expect(ToolKind.brush.showsBrushPreview)
        #expect(!ToolKind.fill.showsBrushPreview)
        #expect(!ToolKind.eyedropper.showsBrushPreview)
        #expect(!ToolKind.select.showsBrushPreview)
    }

    @Test("The rail stays small enough to learn in minutes")
    func toolSetStaysSmall() {
        // The original's whole advantage was that you could master it in
        // minutes. The guard against feature creep undoing that is not "few
        // features" — it is few *rail buttons*: variations belong inside the
        // tool that owns them, the way fifteen shapes live inside one tool.
        #expect(ToolKind.allCases.count <= 14)
        #expect(ToolKind.groups.count == 3)
        #expect(ToolKind.groups.allSatisfy { $0.count <= 5 }, "a run got too long to scan")
    }
}

@Suite("Menu bar", .serialized)
@MainActor
struct MenuBarTests {

    /// The menu bar is the one part of a Mac app you cannot ship broken, and it
    /// is invisible to every other test — so it gets asserted structurally
    /// rather than eyeballed in a screenshot.
    @Test("Every top-level menu is present")
    func topLevelMenus() {
        let menu = MainMenuBuilder.build()
        let titles = menu.items.compactMap(\.submenu?.title)
        for expected in ["File", "Edit", "View", "Image", "Tools", "Window", "Help"] {
            #expect(titles.contains(expected), "missing \(expected) menu")
        }
        // App menu plus the seven above.
        #expect(menu.items.count >= 8)
    }

    private func items(in menuTitle: String) -> [String] {
        MainMenuBuilder.build().items
            .first { $0.submenu?.title == menuTitle }?
            .submenu?.items.map(\.title) ?? []
    }

    @Test("File carries the commands people notice are missing")
    func fileCommands() {
        let titles = items(in: "File")
        for expected in ["New", "Open…", "Close", "Save…", "Duplicate", "Rename…", "Move To…", "Export…", "Print…"] {
            #expect(titles.contains(expected), "File is missing \(expected)")
        }
    }

    @Test("Edit carries the full clipboard and selection set")
    func editCommands() {
        let titles = items(in: "Edit")
        for expected in ["Undo", "Redo", "Cut", "Copy", "Paste",
                         "Select All", "Deselect", "Invert Selection",
                         "Crop to Selection", "Trim Borders"] {
            #expect(titles.contains(expected), "Edit is missing \(expected)")
        }
    }

    @Test("Every tool has a named menu item carrying its key")
    func toolsMenuNamesEveryTool() {
        let tools = MainMenuBuilder.build().items
            .first { $0.submenu?.title == "Tools" }?.submenu
        let titles = tools?.items.map(\.title) ?? []

        for kind in ToolKind.allCases {
            #expect(titles.contains(kind.displayName), "Tools is missing \(kind.displayName)")
        }
        // And each carries the plain letter the canvas listens for, so the menu
        // documents reality instead of inventing a second set of bindings.
        for item in tools?.items ?? [] {
            guard let raw = item.representedObject as? String,
                  let kind = ToolKind(rawValue: raw) else { continue }
            #expect(item.keyEquivalent == String(kind.shortcut))
            #expect(item.keyEquivalentModifierMask.isEmpty)
        }
    }

    @Test("No two menu items share a shortcut")
    func shortcutsDoNotCollide() {
        // Two items with the same key means one of them silently never fires.
        var seen: [String: String] = [:]
        for top in MainMenuBuilder.build().items {
            for item in top.submenu?.items ?? [] {
                guard !item.keyEquivalent.isEmpty else { continue }
                let signature = "\(item.keyEquivalentModifierMask.rawValue):\(item.keyEquivalent)"
                if let existing = seen[signature] {
                    Issue.record("'\(item.title)' collides with '\(existing)' on \(signature)")
                }
                seen[signature] = item.title
            }
        }
    }
}
