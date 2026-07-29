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
    @IBAction func shareImage(_ sender: Any?) {
        guard let window = windowControllers.first?.window,
              let view = window.contentView,
              let data = try? ImageCodec.encode(model.canvas, as: .png),
              let image = NSImage(data: data)
        else { return }
        let picker = NSSharingServicePicker(items: [image])
        picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
    }

    @IBAction func showSettings(_ sender: Any?) {
        // Deliberately not implemented yet. Rather than ship a menu item that
        // opens an empty window, it stays disabled until there is a setting
        // worth showing — a dead control is a defect, not a placeholder.
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

        case #selector(showSettings(_:)):
            return false

        default:
            return super.validateMenuItem(menuItem)
        }
    }
}
