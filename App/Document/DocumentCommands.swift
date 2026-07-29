import AppKit
import PaintKit

/// Menu command implementations.
///
/// These live on the document because the document is in the responder chain
/// for its own windows. That is what makes each command act on the *frontmost*
/// drawing without any of them reaching for `NSApp.keyWindow` and guessing.
extension DrawingDocument {

    // MARK: - Tools

    /// One action for all eleven Tools items: the menu carries the tool in
    /// `representedObject`, so adding a tool never means adding a selector.
    @IBAction func selectToolFromMenu(_ sender: Any?) {
        guard let raw = (sender as? NSMenuItem)?.representedObject as? String,
              let kind = ToolKind(rawValue: raw)
        else { return }
        model.selectTool(kind)
    }

    /// Same trick for the fifteen shapes: the kind rides in `representedObject`.
    @IBAction func selectShapeFromMenu(_ sender: Any?) {
        guard let raw = (sender as? NSMenuItem)?.representedObject as? String,
              let kind = ShapeKind(rawValue: raw)
        else { return }
        model.selectShape(kind)
    }

    @IBAction func toggleToolbarEdge(_ sender: Any?) {
        model.chromeEdge = model.chromeEdge.toggled
    }

    @IBAction func increaseBrush(_ sender: Any?) { model.stepBrushSize(up: true) }
    @IBAction func decreaseBrush(_ sender: Any?) { model.stepBrushSize(up: false) }

    // MARK: - Text style

    /// ⌘B / ⌘I / ⌘U — arming the text tool as well as setting the trait, so
    /// they work from anywhere rather than only once you are already typing.
    @IBAction func toggleBold(_ sender: Any?) { model.toggleTextTrait(\.isTextBold) }
    @IBAction func toggleItalic(_ sender: Any?) { model.toggleTextTrait(\.isTextItalic) }
    @IBAction func toggleUnderline(_ sender: Any?) { model.toggleTextTrait(\.isTextUnderlined) }

    // MARK: - Colours

    @IBAction func swapColours(_ sender: Any?) { model.swapColours() }

    // MARK: - Clipboard and selection

    @IBAction func cut(_ sender: Any?) { model.cutSelection() }
    @IBAction func copy(_ sender: Any?) { model.copySelection() }
    @IBAction func paste(_ sender: Any?) { model.paste() }
    @IBAction func pasteFitting(_ sender: Any?) { model.pasteFittingCanvas() }
    @IBAction func delete(_ sender: Any?) { model.deleteSelection() }
    @IBAction func selectAll(_ sender: Any?) { model.selectAll() }
    @IBAction func deselect(_ sender: Any?) { model.deselect() }
    @IBAction func invertSelection(_ sender: Any?) { model.invertSelection() }

    // MARK: - View

    @IBAction func zoomIn(_ sender: Any?) { model.zoomIn() }
    @IBAction func zoomOut(_ sender: Any?) { model.zoomOut() }
    @IBAction func zoomActual(_ sender: Any?) { model.hasUserZoomed = true; model.zoom = 1 }

    @IBAction func zoomToFit(_ sender: Any?) {
        guard let size = windowControllers.first?.window?.contentView?.bounds.size else { return }
        // Subtract the docked chrome so "fit" fits the canvas area rather than
        // the window; fitting to the window would tuck the artwork under the
        // rail and inspector.
        model.zoomToFit(
            Tokens.Chrome.canvasArea(in: size, rail: model.chromeEdge)
        )
    }
    @IBAction func togglePixelGrid(_ sender: Any?) { model.showsGrid.toggle() }

    /// ⇧⌘C opens the swatch popover. In canvas-first there is no permanent
    /// colour surface, so the keystroke is the guaranteed way in.
    @IBAction func showColours(_ sender: Any?) { model.isColourPopoverRequested = true }

    // MARK: - Image

    @IBAction func cropToSelection(_ sender: Any?) { model.cropToSelection() }
    @IBAction func trimBorders(_ sender: Any?) { model.trimBorders() }
    @IBAction func showSizeSheet(_ sender: Any?) { model.isSizeSheetPresented = true }
    @IBAction func showRotateSheet(_ sender: Any?) { model.isRotateSheetPresented = true }
    @IBAction func flipHorizontal(_ sender: Any?) { model.flipHorizontally() }
    @IBAction func flipVertical(_ sender: Any?) { model.flipVertically() }
    @IBAction func rotateRight(_ sender: Any?) { model.rotate(.clockwise90) }
    @IBAction func rotateLeft(_ sender: Any?) { model.rotate(.counterClockwise90) }
    @IBAction func rotateHalf(_ sender: Any?) { model.rotate(.half) }
    @IBAction func invertColours(_ sender: Any?) { model.invertColours() }
    @IBAction func clearImage(_ sender: Any?) { model.clearImage() }

    // MARK: - Sharing

    @IBAction func copyWholeImage(_ sender: Any?) { model.copyWholeImage() }

    /// The system share sheet, anchored to the window it came from.
    /// The system share sheet, anchored to whatever asked for it.
    ///
    /// **Shares a file URL, not an `NSImage`.** The picker accepts both, but an
    /// in-memory image has no name — so AirDrop sends "Image", Mail attaches an
    /// untitled file, and Notes files it as an unnamed attachment. A real `.png`
    /// on disk named after the document gets the full service list *and* keeps
    /// the name at the other end, which is the whole point of sharing it.
    ///
    /// The file goes to a temporary directory the sandbox already grants, and
    /// the system copies it into whichever service the user picks.
    @IBAction func shareImage(_ sender: Any?) {
        guard let window = windowControllers.first?.window,
              let view = window.contentView
        else { return }

        let items: [Any]
        do {
            items = [try exportedImageURL()]
        } catch {
            // Sharing is not worth failing over — fall back to the image
            // itself, which still reaches every service that takes one.
            guard let data = try? ImageCodec.encode(model.canvas, as: .png),
                  let image = NSImage(data: data)
            else { return }
            items = [image]
        }

        let picker = NSSharingServicePicker(items: items)
        // Anchored to the control that invoked it where there is one, so the
        // popover points at the button rather than at the window's corner.
        if let button = sender as? NSView {
            picker.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        } else {
            let anchor = NSRect(
                x: view.bounds.maxX - Tokens.Space.safeInset,
                y: view.bounds.maxY - Tokens.Chrome.titleReserve,
                width: 1, height: 1
            )
            picker.show(relativeTo: anchor, of: view, preferredEdge: .minY)
        }
    }

    /// Write the canvas to a uniquely-named temporary `.png` for sharing.
    ///
    /// Uniquely-named because sharing the same document twice in a session must
    /// not have the second share silently hand out the first one's pixels.
    private func exportedImageURL() throws -> URL {
        let data = try ImageCodec.encode(model.canvas, as: .png)
        let name = (displayName.isEmpty ? "Untitled" : displayName)
            .replacingOccurrences(of: "/", with: "-")
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("Share-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        let url = directory
            .appendingPathComponent(name)
            .appendingPathExtension("png")
        try data.write(to: url, options: .atomic)
        return url
    }

    @IBAction func showSettings(_ sender: Any?) {
        SettingsWindowController.show()
    }

    /// Reflect state in the menu: checkmarks for toggles, and disable the
    /// commands that genuinely cannot run right now. A menu that offers
    /// "Crop to Selection" with nothing selected teaches people to distrust it.
    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(togglePixelGrid(_:)):
            menuItem.state = model.showsGrid ? .on : .off
            // The grid is meaningless until a pixel is comfortably bigger than
            // the line that would draw it.
            return model.zoom >= 4

        case #selector(zoomIn(_:)):
            return model.zoom < (EditorModel.zoomSteps.last ?? 1)
        case #selector(zoomOut(_:)):
            return model.zoom > (EditorModel.zoomSteps.first ?? 1)
        case #selector(zoomActual(_:)):
            return model.zoom != 1

        case #selector(cut(_:)), #selector(copy(_:)), #selector(delete(_:)),
             #selector(cropToSelection(_:)), #selector(deselect(_:)):
            return model.hasSelection

        case #selector(invertSelection(_:)):
            // Always available: with nothing selected it means "select all".
            return true

        case #selector(paste(_:)), #selector(pasteFitting(_:)):
            return model.canPaste

        case #selector(selectShapeFromMenu(_:)):
            menuItem.state = (menuItem.representedObject as? String) == model.shapeKind.rawValue ? .on : .off
            return true

        case #selector(toggleToolbarEdge(_:)):
            menuItem.title = "Move Toolbar to the \(model.chromeEdge.toggled.displayName)"
            return true

        case #selector(selectToolFromMenu(_:)):
            // Tick the active tool, so the menu is also where you check which
            // of eleven unlabelled glyphs is currently armed.
            menuItem.state = (menuItem.representedObject as? String) == model.tool.rawValue ? .on : .off
            return true

        case #selector(increaseBrush(_:)), #selector(decreaseBrush(_:)):
            return model.tool.usesBrushSize

        // Ticked when armed, whichever tool is in hand — pressing ⌘B with the
        // brush selected arms bold text, so the menu has to say so.
        case #selector(toggleBold(_:)):
            menuItem.state = model.isTextBold ? .on : .off
            return true
        case #selector(toggleItalic(_:)):
            menuItem.state = model.isTextItalic ? .on : .off
            return true
        case #selector(toggleUnderline(_:)):
            menuItem.state = model.isTextUnderlined ? .on : .off
            return true


        default:
            return super.validateMenuItem(menuItem)
        }
    }
}
