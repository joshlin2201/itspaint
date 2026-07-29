import AppKit
import PaintKit

/// Builds the main menu.
///
/// Every command lives here, in one readable list, with its shortcut next to
/// it. Actions route through the responder chain (`nil` target), so each one is
/// automatically enabled only when something down the chain can perform it —
/// which is how a menu avoids offering commands that do nothing.
@MainActor
enum MainMenuBuilder {

    static func build() -> NSMenu {
        let root = NSMenu()
        root.addItem(appMenu())
        root.addItem(fileMenu())
        root.addItem(editMenu())
        root.addItem(viewMenu())
        root.addItem(imageMenu())
        root.addItem(toolsMenu())
        root.addItem(windowMenu())
        root.addItem(helpMenu())
        return root
    }

    // MARK: - Menus

    private static func appMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "ItsPaint")

        menu.addItem(withTitle: "About ItsPaint", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        add(to: menu, "Settings…", #selector(AppCommands.showSettings(_:)), ",")
        menu.addItem(.separator())

        let services = NSMenu(title: "Services")
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        servicesItem.submenu = services
        menu.addItem(servicesItem)
        NSApp.servicesMenu = services

        menu.addItem(.separator())
        add(to: menu, "Hide ItsPaint", #selector(NSApplication.hide(_:)), "h")
        let hideOthers = add(to: menu, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        add(to: menu, "Show All", #selector(NSApplication.unhideAllApplications(_:)), "")
        menu.addItem(.separator())
        add(to: menu, "Quit ItsPaint", #selector(NSApplication.terminate(_:)), "q")

        item.submenu = menu
        return item
    }

    private static func fileMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "File")

        add(to: menu, "New", #selector(NSDocumentController.newDocument(_:)), "n")
        add(to: menu, "Open…", #selector(NSDocumentController.openDocument(_:)), "o")

        // AppKit populates Open Recent automatically for any submenu that
        // contains a `clearRecentDocuments:` item. That is the documented hook;
        // the `_setMenuName:` trick that also works is private API and would be
        // grounds for App Store rejection.
        let recents = NSMenu(title: "Open Recent")
        add(to: recents, "Clear Menu", #selector(NSDocumentController.clearRecentDocuments(_:)), "")
        let recentsItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        recentsItem.submenu = recents
        menu.addItem(recentsItem)

        menu.addItem(.separator())
        add(to: menu, "Close", #selector(NSWindow.performClose(_:)), "w")
        add(to: menu, "Save…", #selector(NSDocument.save(_:)), "s")
        let saveAs = add(to: menu, "Save As…", #selector(NSDocument.saveAs(_:)), "s")
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        // The three File commands people notice are missing. All three come
        // free from NSDocument once the document declares its types.
        add(to: menu, "Duplicate", #selector(NSDocument.duplicate(_:)), "S")
            .keyEquivalentModifierMask = [.command, .shift, .option]
        add(to: menu, "Rename…", #selector(NSDocument.rename(_:)), "")
        add(to: menu, "Move To…", #selector(NSDocument.move(_:)), "")
        add(to: menu, "Revert to Saved", #selector(NSDocument.revertToSaved(_:)), "")
        menu.addItem(.separator())
        let export = add(to: menu, "Export…", #selector(DrawingDocument.exportImage(_:)), "e")
        export.keyEquivalentModifierMask = [.command, .shift]
        add(to: menu, "Copy Whole Image", #selector(AppCommands.copyWholeImage(_:)), "c")
            .keyEquivalentModifierMask = [.command, .option]
        add(to: menu, "Share…", #selector(AppCommands.shareImage(_:)), "")
        menu.addItem(.separator())
        add(to: menu, "Page Setup…", #selector(NSDocument.runPageLayout(_:)), "P")
        add(to: menu, "Print…", #selector(NSDocument.printDocument(_:)), "p")

        item.submenu = menu
        return item
    }

    private static func editMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Edit")

        add(to: menu, "Undo", Selector(("undo:")), "z")
        let redo = add(to: menu, "Redo", Selector(("redo:")), "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        add(to: menu, "Cut", #selector(NSText.cut(_:)), "x")
        add(to: menu, "Copy", #selector(NSText.copy(_:)), "c")
        add(to: menu, "Paste", #selector(NSText.paste(_:)), "v")
        // Pasting a screenshot larger than the canvas and silently losing its
        // edges is the classic paste failure; this grows the canvas instead.
        let pasteFit = add(to: menu, "Paste and Fit", #selector(AppCommands.pasteFitting(_:)), "v")
        pasteFit.keyEquivalentModifierMask = [.command, .shift]
        add(to: menu, "Delete", #selector(NSText.delete(_:)), "")
        menu.addItem(.separator())
        add(to: menu, "Select All", #selector(NSText.selectAll(_:)), "a")
        let deselect = add(to: menu, "Deselect", #selector(AppCommands.deselect(_:)), "a")
        deselect.keyEquivalentModifierMask = [.command, .shift]
        add(to: menu, "Invert Selection", #selector(AppCommands.invertSelection(_:)), "i")
            .keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        add(to: menu, "Crop to Selection", #selector(AppCommands.cropToSelection(_:)), "k")
        add(to: menu, "Trim Borders", #selector(AppCommands.trimBorders(_:)), "t")
            .keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        add(to: menu, "Swap Colours", #selector(AppCommands.swapColours(_:)), "x")
            .keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())

        // Standard system items. Their absence is one of the first things a
        // Mac user notices, and both are free.
        add(to: menu, "Emoji & Symbols", #selector(NSApplication.orderFrontCharacterPalette(_:)), " ")
            .keyEquivalentModifierMask = [.command, .control]
        let dictation = NSMenuItem(
            title: "Start Dictation…", action: Selector(("startDictation:")), keyEquivalent: ""
        )
        dictation.target = nil
        menu.addItem(dictation)

        item.submenu = menu
        return item
    }

    private static func viewMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "View")

        add(to: menu, "Zoom In", #selector(AppCommands.zoomIn(_:)), "+")
        add(to: menu, "Zoom Out", #selector(AppCommands.zoomOut(_:)), "-")
        add(to: menu, "Actual Size", #selector(AppCommands.zoomActual(_:)), "0")
        add(to: menu, "Zoom to Fit", #selector(AppCommands.zoomToFit(_:)), "9")
        menu.addItem(.separator())
        add(to: menu, "Show Pixel Grid", #selector(AppCommands.togglePixelGrid(_:)), "'")
        add(to: menu, "Move Toolbar", #selector(AppCommands.toggleToolbarEdge(_:)), "t")
            .keyEquivalentModifierMask = [.command, .option]
        add(to: menu, "Colours…", #selector(AppCommands.showColours(_:)), "C")
            .keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        add(to: menu, "Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f")
            .keyEquivalentModifierMask = [.command, .control]

        item.submenu = menu
        return item
    }

    private static func imageMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Image")

        // Crop and Trim live in Edit, next to the selection commands they act
        // on — not here. Listing them twice gave two items the same key, and
        // one of a colliding pair silently never fires.
        add(to: menu, "Image Size…", #selector(AppCommands.showSizeSheet(_:)), "r")
        menu.addItem(.separator())
        add(to: menu, "Flip Horizontal", #selector(AppCommands.flipHorizontal(_:)), "")
        add(to: menu, "Flip Vertical", #selector(AppCommands.flipVertical(_:)), "")
        menu.addItem(.separator())
        add(to: menu, "Rotate 90° Right", #selector(AppCommands.rotateRight(_:)), "]")
        add(to: menu, "Rotate 90° Left", #selector(AppCommands.rotateLeft(_:)), "[")
        add(to: menu, "Rotate 180°", #selector(AppCommands.rotateHalf(_:)), "")
        // Quarter turns are exact and need no dialog; any other angle resamples
        // and grows the canvas, so it gets a sheet with a size preview.
        add(to: menu, "Rotate…", #selector(AppCommands.showRotateSheet(_:)), "")
        menu.addItem(.separator())
        add(to: menu, "Invert Colours", #selector(AppCommands.invertColours(_:)), "i")
        add(to: menu, "Clear Image", #selector(AppCommands.clearImage(_:)), "")
            .keyEquivalentModifierMask = [.command, .shift]

        item.submenu = menu
        return item
    }

    /// Every tool, named, with its key.
    ///
    /// The cluster is eleven unlabelled glyphs by design — its stated weakness.
    /// This is where a new user reads what they are and learns the shortcuts,
    /// and where a VoiceOver user reaches them without hunting a floating bar.
    private static func toolsMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Tools")

        for (index, group) in ToolKind.groups.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            for kind in group {
                let entry = NSMenuItem(
                    title: kind.displayName,
                    action: #selector(AppCommands.selectToolFromMenu(_:)),
                    keyEquivalent: String(kind.shortcut)
                )
                // Plain letters, no modifier — matching what the canvas already
                // listens for, so the menu documents reality rather than
                // inventing a second set of bindings.
                entry.keyEquivalentModifierMask = []
                entry.target = nil
                entry.representedObject = kind.rawValue
                entry.image = NSImage(
                    systemSymbolName: kind.symbolName, accessibilityDescription: kind.displayName
                )
                menu.addItem(entry)
            }
        }

        menu.addItem(.separator())

        // Shapes are one tool with fifteen kinds, so they get a submenu rather
        // than fifteen rail buttons — the same trade the options panel makes.
        let shapes = NSMenu(title: "Shape")
        for (index, kind) in ShapeKind.allCases.enumerated() {
            let entry = NSMenuItem(
                title: kind.displayName,
                action: #selector(AppCommands.selectShapeFromMenu(_:)),
                keyEquivalent: index < 9 ? String(index + 1) : ""
            )
            entry.keyEquivalentModifierMask = [.option]
            entry.target = nil
            entry.representedObject = kind.rawValue
            entry.image = NSImage(
                systemSymbolName: kind.symbolName, accessibilityDescription: kind.displayName
            )
            shapes.addItem(entry)
        }
        let shapesItem = NSMenuItem(title: "Shape", action: nil, keyEquivalent: "")
        shapesItem.submenu = shapes
        menu.addItem(shapesItem)

        menu.addItem(.separator())

        // Text traits, in the Tools menu rather than a Format menu: this app
        // has exactly one text tool, and a whole menu bar item for three
        // toggles would be the ribbon mistake in menu form.
        let text = NSMenu(title: "Text")
        add(to: text, "Bold", #selector(AppCommands.toggleBold(_:)), "b")
        add(to: text, "Italic", #selector(AppCommands.toggleItalic(_:)), "i")
        add(to: text, "Underline", #selector(AppCommands.toggleUnderline(_:)), "u")
        let textItem = NSMenuItem(title: "Text", action: nil, keyEquivalent: "")
        textItem.submenu = text
        menu.addItem(textItem)

        menu.addItem(.separator())
        add(to: menu, "Swap Colours", #selector(AppCommands.swapColours(_:)), "x")
            .keyEquivalentModifierMask = []
        add(to: menu, "Larger Brush", #selector(AppCommands.increaseBrush(_:)), "]")
            .keyEquivalentModifierMask = []
        add(to: menu, "Smaller Brush", #selector(AppCommands.decreaseBrush(_:)), "[")
            .keyEquivalentModifierMask = []

        item.submenu = menu
        return item
    }

    /// The canvas's own right-click menu.
    ///
    /// Built from the same selectors as the main menu — `nil` target, responder
    /// chain — so an item can never appear here enabled while its menu-bar twin
    /// is disabled, or vice versa.
    static func canvasMenu() -> NSMenu {
        let menu = NSMenu()
        add(to: menu, "Undo", Selector(("undo:")), "")
        add(to: menu, "Redo", Selector(("redo:")), "")
        menu.addItem(.separator())
        add(to: menu, "Cut", #selector(NSText.cut(_:)), "")
        add(to: menu, "Copy", #selector(NSText.copy(_:)), "")
        add(to: menu, "Paste", #selector(NSText.paste(_:)), "")
        add(to: menu, "Delete", #selector(NSText.delete(_:)), "")
        menu.addItem(.separator())
        add(to: menu, "Select All", #selector(NSText.selectAll(_:)), "")
        add(to: menu, "Deselect", #selector(AppCommands.deselect(_:)), "")
        add(to: menu, "Crop to Selection", #selector(AppCommands.cropToSelection(_:)), "")
        add(to: menu, "Trim Borders", #selector(AppCommands.trimBorders(_:)), "")
        menu.addItem(.separator())
        add(to: menu, "Copy Whole Image", #selector(AppCommands.copyWholeImage(_:)), "")
        add(to: menu, "Export…", #selector(DrawingDocument.exportImage(_:)), "")
        menu.addItem(.separator())
        add(to: menu, "Swap Colours", #selector(AppCommands.swapColours(_:)), "")
        add(to: menu, "Image Size…", #selector(AppCommands.showSizeSheet(_:)), "")
        return menu
    }

    private static func windowMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Window")

        add(to: menu, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
        add(to: menu, "Zoom", #selector(NSWindow.performZoom(_:)), "")
        menu.addItem(.separator())
        add(to: menu, "Bring All to Front", #selector(NSApplication.arrangeInFront(_:)), "")

        item.submenu = menu
        NSApp.windowsMenu = menu
        return item
    }

    private static func helpMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Help")
        add(to: menu, "ItsPaint Help", #selector(NSApplication.showHelp(_:)), "?")
        item.submenu = menu
        NSApp.helpMenu = menu
        return item
    }

    // MARK: - Helper

    @discardableResult
    private static func add(
        to menu: NSMenu, _ title: String, _ action: Selector, _ key: String
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        // nil target = route through the responder chain, so the item enables
        // itself only when something can actually handle it.
        item.target = nil
        menu.addItem(item)
        return item
    }
}

/// Selectors the menu targets. Declared on a protocol-free stub so the compiler
/// checks the names; the responder chain supplies the real implementations.
@objc protocol AppCommands {
    func showSettings(_ sender: Any?)
    func swapColours(_ sender: Any?)
    func toggleBold(_ sender: Any?)
    func toggleItalic(_ sender: Any?)
    func toggleUnderline(_ sender: Any?)
    func pasteFitting(_ sender: Any?)
    func deselect(_ sender: Any?)
    func invertSelection(_ sender: Any?)
    func zoomToFit(_ sender: Any?)
    func cropToSelection(_ sender: Any?)
    func trimBorders(_ sender: Any?)
    func showSizeSheet(_ sender: Any?)
    func showRotateSheet(_ sender: Any?)
    func zoomIn(_ sender: Any?)
    func zoomOut(_ sender: Any?)
    func zoomActual(_ sender: Any?)
    func togglePixelGrid(_ sender: Any?)
    func showColours(_ sender: Any?)
    func selectToolFromMenu(_ sender: Any?)
    func selectShapeFromMenu(_ sender: Any?)
    func toggleToolbarEdge(_ sender: Any?)
    func copyWholeImage(_ sender: Any?)
    func shareImage(_ sender: Any?)
    func increaseBrush(_ sender: Any?)
    func decreaseBrush(_ sender: Any?)
    func flipHorizontal(_ sender: Any?)
    func flipVertical(_ sender: Any?)
    func rotateRight(_ sender: Any?)
    func rotateLeft(_ sender: Any?)
    func rotateHalf(_ sender: Any?)
    func invertColours(_ sender: Any?)
    func clearImage(_ sender: Any?)
}
