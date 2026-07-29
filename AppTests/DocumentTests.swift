import AppKit
import PaintKit
import Foundation
import Testing
@testable import ItsPaint

/// App-layer tests. The heavy pixel coverage lives in PaintKit; these cover the
/// seams the package cannot see — the document, and the model that bridges the
/// engine to SwiftUI.

@Suite("Editor model", .serialized)
@MainActor
struct EditorModelTests {

    @Test("Changing a tool reaches the engine")
    func toolPropagates() {
        let model = EditorModel(canvas: Bitmap(width: 16, height: 16))
        model.selectTool(.highlighter)
        #expect(model.engine.settings.tool == .highlighter)
    }

    @Test("Swapping colours updates both the engine and the published pair")
    func swapPropagates() {
        let model = EditorModel(canvas: Bitmap(width: 16, height: 16))
        model.foreground = PaintColour(hex: "FF0000")!
        model.background = PaintColour(hex: "0000FF")!
        model.swapColours()

        #expect(model.foreground == PaintColour(hex: "0000FF")!)
        #expect(model.engine.colours.foreground == PaintColour(hex: "0000FF")!)
    }

    @Test("A new edit fires the commit hook exactly once")
    func editHookFiresOnce() {
        let model = EditorModel(canvas: Bitmap(width: 32, height: 32))
        var commits: [String] = []
        model.onEditCommitted = { commits.append($0) }

        model.selectTool(.pencil)
        model.noteChange(model.engine.beginStroke(at: PixelPoint(x: 4, y: 4)))
        model.noteChange(model.engine.continueStroke(to: PixelPoint(x: 10, y: 10)))
        model.noteChange(model.engine.endStroke())

        #expect(commits == ["Pencil"])
    }

    @Test("Undo does not register another undo")
    func undoDoesNotRecurse() {
        // If replaying an undo counted as a new edit, Cmd-Z would push a fresh
        // action every time and never reach the start of the history.
        let model = EditorModel(canvas: Bitmap(width: 32, height: 32))
        model.selectTool(.pencil)
        model.noteChange(model.engine.beginStroke(at: PixelPoint(x: 4, y: 4)))
        model.noteChange(model.engine.endStroke())

        var commitsAfterUndo = 0
        model.onEditCommitted = { _ in commitsAfterUndo += 1 }
        model.undo()

        #expect(commitsAfterUndo == 0)
    }

    @Test("The eyedropper's sampled colour reaches the published foreground")
    func eyedropperSyncs() {
        let model = EditorModel(canvas: Bitmap(width: 16, height: 16, fill: .white))
        model.foreground = PaintColour(hex: "FF0000")!
        model.selectTool(.eyedropper)
        _ = model.engine.beginStroke(at: PixelPoint(x: 8, y: 8))
        model.syncFromEngine()

        #expect(model.foreground == PaintColour.white)
    }

    @Test("Zoom snaps to a defined step rather than an arbitrary scale")
    func zoomSnaps() {
        let model = EditorModel(canvas: Bitmap(width: 16, height: 16))
        model.zoom = 3.3
        #expect(EditorModel.zoomSteps.contains(model.zoom))
    }

    @Test("Zoom in and out stay inside the ramp")
    func zoomClamps() {
        let model = EditorModel(canvas: Bitmap(width: 16, height: 16))
        for _ in 0..<20 { model.zoomIn() }
        #expect(model.zoom == EditorModel.zoomSteps.last)
        for _ in 0..<40 { model.zoomOut() }
        #expect(model.zoom == EditorModel.zoomSteps.first)
    }

    @Test("Rotating swaps the reported canvas size")
    func rotateUpdatesSize() {
        let model = EditorModel(canvas: Bitmap(width: 40, height: 20))
        model.rotate(.clockwise90)
        #expect(model.canvasSize.width == 20)
        #expect(model.canvasSize.height == 40)
    }

    @Test("A visual-only selection does not mark the document changed")
    func visualSelectionDoesNotDirtyDocument() {
        let model = EditorModel(canvas: Bitmap(width: 12, height: 8, fill: .white))
        var documentChanges = 0
        model.onCanvasChanged = { _ in documentChanges += 1 }

        model.noteVisualChange(PixelRect(x: 0, y: 0, width: 12, height: 8))

        #expect(model.revision == 1)
        #expect(documentChanges == 0)
    }
}

@Suite("Document", .serialized)
@MainActor
struct DrawingDocumentTests {

    @Test("A new document opens a usable white canvas")
    func newDocumentDefaults() {
        let document = DrawingDocument()
        #expect(document.model.canvas.width == DrawingDocument.defaultCanvasSize.width)
        #expect(document.model.canvas.pixels.allSatisfy { $0 == .white })
    }

    @Test("The app and native document use one stable public identity")
    func publicIdentityIsConsistent() throws {
        #expect(Bundle.main.bundleIdentifier == "com.joshlin.itspaint")
        #expect(DrawingDocument.packageType == "com.joshlin.itspaint-drawing")

        let exportedTypes = try #require(
            Bundle.main.object(forInfoDictionaryKey: "UTExportedTypeDeclarations")
                as? [[String: Any]]
        )
        let exportedIdentifiers = exportedTypes.compactMap {
            $0["UTTypeIdentifier"] as? String
        }
        #expect(exportedIdentifiers.contains(DrawingDocument.packageType))

        let documentTypes = try #require(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleDocumentTypes")
                as? [[String: Any]]
        )
        let advertisedTypes = documentTypes.flatMap {
            $0["LSItemContentTypes"] as? [String] ?? []
        }
        #expect(advertisedTypes.contains(DrawingDocument.packageType))
    }

    @Test("Drawing marks the document dirty")
    func editingMarksDirty() {
        let document = DrawingDocument()
        #expect(!document.isDocumentEdited)

        document.model.selectTool(.pencil)
        document.model.noteChange(document.model.engine.beginStroke(at: PixelPoint(x: 5, y: 5)))
        document.model.noteChange(document.model.engine.endStroke())

        #expect(document.isDocumentEdited)
    }

    @Test("A .itspaint package round-trips its pixels and colours")
    func packageRoundTrip() throws {
        let document = DrawingDocument()
        document.model.selectTool(.pencil)
        document.model.foreground = PaintColour(hex: "FF00AA")!
        _ = document.model.engine.beginStroke(at: PixelPoint(x: 10, y: 10))
        _ = document.model.engine.endStroke()
        let expected = document.model.canvas

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("itspaint-doc-\(UUID().uuidString).itspaint")
        defer { try? FileManager.default.removeItem(at: url) }

        try document.write(to: url, ofType: DrawingDocument.packageType)
        #expect(FileManager.default.fileExists(atPath: url.path))

        let reopened = DrawingDocument()
        try reopened.read(from: url, ofType: DrawingDocument.packageType)
        #expect(reopened.model.canvas == expected)
    }

    @Test("Reopening a package restores the colours it was saved with")
    func packageRestoresEditingState() throws {
        // The metadata was being written and then never read, so every reopened
        // document came back with the default black-on-white pair.
        let document = DrawingDocument()
        document.model.foreground = PaintColour(hex: "FF00AA")!
        document.model.background = PaintColour(hex: "112233")!

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("itspaint-doc-\(UUID().uuidString).itspaint")
        defer { try? FileManager.default.removeItem(at: url) }
        try document.write(to: url, ofType: DrawingDocument.packageType)

        let reopened = DrawingDocument()
        try reopened.read(from: url, ofType: DrawingDocument.packageType)
        #expect(reopened.model.foreground == PaintColour(hex: "FF00AA")!)
        #expect(reopened.model.background == PaintColour(hex: "112233")!)
        #expect(reopened.model.engine.colours.foreground == PaintColour(hex: "FF00AA")!)
    }

    @Test("A package without metadata still opens its artwork")
    func packageMissingMetadataFallsBack() throws {
        let package = try makePackageWithDistinctState()
        defer { try? FileManager.default.removeItem(at: package.url) }
        try FileManager.default.removeItem(
            at: package.url.appendingPathComponent(DrawingDocument.PackageEntry.metadata)
        )

        let reopened = DrawingDocument()
        try reopened.read(from: package.url, ofType: DrawingDocument.packageType)

        #expect(reopened.model.canvas == package.canvas)
        #expect(reopened.model.foreground == .black)
        #expect(reopened.model.background == .white)
        #expect(reopened.model.palette == .standard)
    }

    @Test("Corrupt package metadata falls back without hiding the artwork")
    func packageCorruptMetadataFallsBack() throws {
        let package = try makePackageWithDistinctState()
        defer { try? FileManager.default.removeItem(at: package.url) }
        try Data("{".utf8).write(
            to: package.url.appendingPathComponent(DrawingDocument.PackageEntry.metadata)
        )

        let reopened = DrawingDocument()
        try reopened.read(from: package.url, ofType: DrawingDocument.packageType)

        #expect(reopened.model.canvas == package.canvas)
        #expect(reopened.model.foreground == .black)
    }

    @Test("Metadata at the byte limit remains compatible")
    func packageMetadataBoundaryIsAccepted() throws {
        let package = try makePackageWithDistinctState()
        defer { try? FileManager.default.removeItem(at: package.url) }
        let metadataURL = package.url.appendingPathComponent(DrawingDocument.PackageEntry.metadata)
        var metadata = try Data(contentsOf: metadataURL)
        #expect(metadata.count < DrawingDocument.PackagePolicy.maximumMetadataBytes)
        metadata.append(
            Data(
                repeating: 0x20,
                count: DrawingDocument.PackagePolicy.maximumMetadataBytes - metadata.count
            )
        )
        try metadata.write(to: metadataURL)

        let reopened = DrawingDocument()
        try reopened.read(from: package.url, ofType: DrawingDocument.packageType)

        #expect(reopened.model.canvas == package.canvas)
        #expect(reopened.model.foreground == package.foreground)
    }

    @Test("Oversized package metadata is ignored without a large allocation")
    func packageOversizedMetadataFallsBack() throws {
        let package = try makePackageWithDistinctState()
        defer { try? FileManager.default.removeItem(at: package.url) }
        let metadataURL = package.url.appendingPathComponent(DrawingDocument.PackageEntry.metadata)
        let handle = try FileHandle(forWritingTo: metadataURL)
        try handle.truncate(
            atOffset: UInt64(DrawingDocument.PackagePolicy.maximumMetadataBytes + 1)
        )
        try handle.close()

        let reopened = DrawingDocument()
        try reopened.read(from: package.url, ofType: DrawingDocument.packageType)

        #expect(reopened.model.canvas == package.canvas)
        #expect(reopened.model.foreground == .black)
    }

    @Test("An oversized encoded palette invalidates only optional metadata")
    func packageOversizedPaletteFallsBack() throws {
        let package = try makePackageWithDistinctState()
        defer { try? FileManager.default.removeItem(at: package.url) }
        let metadataURL = package.url.appendingPathComponent(DrawingDocument.PackageEntry.metadata)
        let original = try Data(contentsOf: metadataURL)
        var object = try #require(
            JSONSerialization.jsonObject(with: original) as? [String: Any]
        )
        var palette = try #require(object["palette"] as? [String: Any])
        let swatches = try #require(palette["swatches"] as? [[String: Any]])
        let first = try #require(swatches.first)
        palette["swatches"] = Array(
            repeating: first,
            count: Palette.maximumSwatchCount + 1
        )
        object["palette"] = palette
        let oversizedPalette = try JSONSerialization.data(withJSONObject: object)
        #expect(oversizedPalette.count < DrawingDocument.PackagePolicy.maximumMetadataBytes)
        try oversizedPalette.write(to: metadataURL)

        let reopened = DrawingDocument()
        try reopened.read(from: package.url, ofType: DrawingDocument.packageType)

        #expect(reopened.model.canvas == package.canvas)
        #expect(reopened.model.foreground == .black)
        #expect(reopened.model.palette == .standard)
    }

    @Test("A symlinked metadata entry is not followed")
    func packageMetadataSymlinkFallsBack() throws {
        let package = try makePackageWithDistinctState()
        let external = FileManager.default.temporaryDirectory
            .appendingPathComponent("itspaint-metadata-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: package.url)
            try? FileManager.default.removeItem(at: external)
        }
        let metadataURL = package.url.appendingPathComponent(DrawingDocument.PackageEntry.metadata)
        try FileManager.default.moveItem(at: metadataURL, to: external)
        try FileManager.default.createSymbolicLink(at: metadataURL, withDestinationURL: external)

        let reopened = DrawingDocument()
        try reopened.read(from: package.url, ofType: DrawingDocument.packageType)

        #expect(reopened.model.canvas == package.canvas)
        #expect(reopened.model.foreground == .black)
    }

    @Test("A non-regular metadata entry is not read")
    func packageMetadataDirectoryFallsBack() throws {
        let package = try makePackageWithDistinctState()
        defer { try? FileManager.default.removeItem(at: package.url) }
        let metadataURL = package.url.appendingPathComponent(DrawingDocument.PackageEntry.metadata)
        try FileManager.default.removeItem(at: metadataURL)
        try FileManager.default.createDirectory(at: metadataURL, withIntermediateDirectories: false)

        let reopened = DrawingDocument()
        try reopened.read(from: package.url, ofType: DrawingDocument.packageType)

        #expect(reopened.model.canvas == package.canvas)
        #expect(reopened.model.foreground == .black)
    }

    @Test("A symlinked canvas is rejected without mutating the document")
    func packageCanvasSymlinkIsRejected() throws {
        let package = try makePackageWithDistinctState()
        let external = FileManager.default.temporaryDirectory
            .appendingPathComponent("itspaint-canvas-\(UUID().uuidString).png")
        defer {
            try? FileManager.default.removeItem(at: package.url)
            try? FileManager.default.removeItem(at: external)
        }
        let canvasURL = package.url.appendingPathComponent(DrawingDocument.PackageEntry.image)
        try FileManager.default.moveItem(at: canvasURL, to: external)
        try FileManager.default.createSymbolicLink(at: canvasURL, withDestinationURL: external)

        let reopened = DrawingDocument()
        let original = reopened.model.canvas
        #expect(throws: (any Error).self) {
            try reopened.read(from: package.url, ofType: DrawingDocument.packageType)
        }
        #expect(reopened.model.canvas == original)
    }

    @Test("A non-regular canvas is rejected without mutating the document")
    func packageCanvasDirectoryIsRejected() throws {
        let package = try makePackageWithDistinctState()
        defer { try? FileManager.default.removeItem(at: package.url) }
        let canvasURL = package.url.appendingPathComponent(DrawingDocument.PackageEntry.image)
        try FileManager.default.removeItem(at: canvasURL)
        try FileManager.default.createDirectory(at: canvasURL, withIntermediateDirectories: false)

        let reopened = DrawingDocument()
        let original = reopened.model.canvas
        #expect(throws: (any Error).self) {
            try reopened.read(from: package.url, ofType: DrawingDocument.packageType)
        }
        #expect(reopened.model.canvas == original)
    }

    @Test("An oversized encoded canvas is rejected using a sparse file")
    func packageEncodedCanvasLimitIsEnforced() throws {
        let package = try makePackageWithDistinctState()
        defer { try? FileManager.default.removeItem(at: package.url) }
        let canvasURL = package.url.appendingPathComponent(DrawingDocument.PackageEntry.image)
        let handle = try FileHandle(forWritingTo: canvasURL)
        try handle.truncate(
            atOffset: UInt64(DrawingDocument.PackagePolicy.maximumCanvasBytes + 1)
        )
        try handle.close()

        let reopened = DrawingDocument()
        let original = reopened.model.canvas
        #expect(throws: (any Error).self) {
            try reopened.read(from: package.url, ofType: DrawingDocument.packageType)
        }
        #expect(reopened.model.canvas == original)
    }

    @Test("Reading keeps the model the window is already showing")
    func revertReusesTheModel() throws {
        // Revert to Saved reads into the open document: swapping in a fresh
        // model would leave the window bound to the old one and showing the
        // pre-revert pixels.
        let document = DrawingDocument()
        let original = document.model
        document.model.selectTool(.fill)
        document.model.foreground = PaintColour(hex: "00FF00")!
        _ = document.model.engine.beginStroke(at: PixelPoint(x: 4, y: 4))

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("itspaint-doc-\(UUID().uuidString).itspaint")
        defer { try? FileManager.default.removeItem(at: url) }
        try document.write(to: url, ofType: DrawingDocument.packageType)

        document.model.clearImage()
        let revisionBeforeRevert = document.model.revision
        try document.read(from: url, ofType: DrawingDocument.packageType)

        #expect(document.model === original)
        #expect(document.model.canvas.pixel(at: PixelPoint(x: 4, y: 4)) == PaintColour(hex: "00FF00")!.rgba8)
        // And the view is told to repaint.
        #expect(document.model.revision > revisionBeforeRevert)
        // A read is not an edit: nothing to undo, nothing to save back.
        #expect(!document.model.canUndo)
    }

    @Test("Saving to a plain image writes the flattened artwork")
    func imageExport() throws {
        let document = DrawingDocument()
        document.model.selectTool(.fill)
        document.model.foreground = PaintColour(hex: "112233")!
        _ = document.model.engine.beginStroke(at: PixelPoint(x: 4, y: 4))

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("itspaint-doc-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        try document.write(to: url, ofType: "public.png")
        let restored = try ImageCodec.decode(contentsOf: url)
        #expect(restored == document.model.canvas)
    }

    @Test("Opening an image adopts its dimensions")
    func openImage() throws {
        var source = Bitmap(width: 37, height: 21, fill: .white)
        source.setPixel(.black, at: PixelPoint(x: 3, y: 3))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("itspaint-open-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try ImageCodec.write(source, to: url)

        let document = DrawingDocument()
        try document.read(from: url, ofType: "public.png")
        #expect(document.model.canvas == source)
    }

    @Test("Opening a PNG and writing it straight back is byte-identical")
    func openWriteIsLossless() throws {
        // Guards against the worst failure a document app can have: opening
        // someone's file and quietly degrading it. PNG is lossless both ways,
        // so anything other than identical bytes means the pipeline is lying.
        var source = Bitmap(width: 64, height: 48, fill: .white)
        Raster.fillRect(PixelRect(x: 8, y: 8, width: 20, height: 16),
                        colour: RGBA8(r: 200, g: 30, b: 60), into: &source)
        source.setPixel(.black, at: PixelPoint(x: 63, y: 47))

        let original = FileManager.default.temporaryDirectory
            .appendingPathComponent("itspaint-lossless-\(UUID().uuidString).png")
        let rewritten = FileManager.default.temporaryDirectory
            .appendingPathComponent("itspaint-lossless-out-\(UUID().uuidString).png")
        defer {
            try? FileManager.default.removeItem(at: original)
            try? FileManager.default.removeItem(at: rewritten)
        }
        try ImageCodec.write(source, to: original)

        let document = DrawingDocument()
        try document.read(from: original, ofType: "public.png")
        try document.write(to: rewritten, ofType: "public.png")

        let a = try Data(contentsOf: original)
        let b = try Data(contentsOf: rewritten)
        #expect(a == b)
    }

    @Test("Opening a file does not mark it edited")
    func openingIsNotAnEdit() throws {
        // If merely opening dirtied the document, autosave would rewrite files
        // the user only looked at.
        var source = Bitmap(width: 32, height: 32, fill: .white)
        source.setPixel(.black, at: PixelPoint(x: 1, y: 1))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("itspaint-clean-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try ImageCodec.write(source, to: url)

        let document = DrawingDocument()
        try document.read(from: url, ofType: "public.png")
        #expect(!document.isDocumentEdited)
    }

    @Test("Only the native package autosaves in place")
    func autosaveIsScopedToNativeDocuments() throws {
        // An imported PNG is the user's original file; background re-encoding
        // it is data loss waiting to happen.
        let imported = DrawingDocument()
        imported.fileType = "public.png"
        #expect(imported.autosavingFileType == nil)

        let native = DrawingDocument()
        native.fileType = DrawingDocument.packageType
        #expect(native.autosavingFileType == DrawingDocument.packageType)
    }

    @Test("Every writable type maps to a file extension")
    func extensionsResolve() {
        // A type we advertise but can't name a file for would produce a save
        // panel that writes an extensionless file.
        let document = DrawingDocument()
        for type in DrawingDocument.writableTypes {
            let ext = document.fileNameExtension(forType: type, saveOperation: .saveOperation)
            #expect(ext?.isEmpty == false, "no extension for \(type)")
        }
    }

    @Test("Export scaling rejects an unsupported target instead of writing the original size")
    func exportScalingFailsClosed() {
        let options = ExportOptions()
        options.scale = 2
        let tall = Bitmap(width: 1, height: Bitmap.maximumDimension)

        #expect(throws: ImageCodec.CodecError.self) {
            try options.scaled(tall)
        }
    }

    private func makePackageWithDistinctState() throws -> (
        url: URL,
        canvas: Bitmap,
        foreground: PaintColour
    ) {
        let foreground = PaintColour(hex: "FF00AA")!
        let document = DrawingDocument()
        document.model.foreground = foreground
        document.model.background = PaintColour(hex: "112233")!
        document.model.selectTool(.pencil)
        _ = document.model.engine.beginStroke(at: PixelPoint(x: 7, y: 9))
        _ = document.model.engine.endStroke()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("itspaint-secure-\(UUID().uuidString).itspaint")
        try document.write(to: url, ofType: DrawingDocument.packageType)
        return (url, document.model.canvas, foreground)
    }
}

@Suite("Menu commands", .serialized)
@MainActor
struct MenuCommandTests {

    /// The Tools menu carries its tool in `representedObject` — the item and the
    /// action have to agree about that or all eleven items do nothing.
    @Test("A Tools menu item selects its tool")
    func toolsMenuSelectsTools() throws {
        let document = DrawingDocument()
        let item = NSMenuItem(
            title: ToolKind.eraser.displayName,
            action: #selector(DrawingDocument.selectToolFromMenu(_:)),
            keyEquivalent: ""
        )
        item.representedObject = ToolKind.eraser.rawValue

        document.selectToolFromMenu(item)
        #expect(document.model.tool == .eraser)
        // And the menu reflects what is armed.
        #expect(document.validateMenuItem(item))
        #expect(item.state == .on)
    }

    @Test("Every Tools menu item is wired to something that answers")
    func everyToolsItemIsLive() throws {
        // A menu of eleven permanently-disabled items is worse than no menu.
        let document = DrawingDocument()
        let tools = try #require(
            MainMenuBuilder.build().items
                .first { $0.submenu?.title == "Tools" }?
                .submenu?.items
                .filter { $0.representedObject != nil }
        )
        #expect(tools.count == ToolKind.allCases.count)
        for item in tools {
            #expect(
                document.responds(to: try #require(item.action)),
                "\(item.title) is wired to a selector nothing implements"
            )
        }
    }

    @Test("The running app has a real menu bar")
    func liveMenuBarIsInstalled() throws {
        // The tests run inside the app host, so this is the actual launch path:
        // a menu bar missing File and Edit is not a degraded experience, it is
        // a broken app, and it is invisible to every other test here.
        let menu = try #require(NSApp.mainMenu)
        let titles = menu.items.compactMap(\.submenu?.title)
        #expect(titles.contains("File"))
        #expect(titles.contains("Edit"))
        #expect(titles.contains("Tools"))
    }

    @Test("The canvas menu is wired to commands that exist")
    func canvasContextMenuIsLive() throws {
        // The right-click menu is built from the same selectors as the menu
        // bar, so this catches the failure mode that matters: an item that
        // opens, reads well, and does nothing.
        let document = DrawingDocument()
        let menu = MainMenuBuilder.canvasMenu()
        let titles = menu.items.map(\.title)
        for expected in ["Cut", "Copy", "Paste", "Crop to Selection", "Copy Whole Image"] {
            #expect(titles.contains(expected), "the canvas menu is missing \(expected)")
        }
        for item in menu.items where !item.isSeparatorItem {
            let action = try #require(item.action, "\(item.title) has no action")
            // Undo and Redo are the responder chain's own, not the document's.
            guard !["undo:", "redo:"].contains(NSStringFromSelector(action)) else { continue }
            #expect(
                document.responds(to: action) || NSApp.responds(to: action),
                "\(item.title) is wired to a selector nothing implements"
            )
        }
    }

    @Test("Picking a tool opens its options; picking it again puts them away")
    func optionsPanelToggles() {
        // The panel is a step in choosing how to draw, not an inspector: the
        // canvas dismisses it on the first click, and the armed tool brings it
        // back.
        let model = EditorModel(canvas: Bitmap(width: 32, height: 32))
        // Deliberately *not* a hardcoded tool: the point is "a tool you are not
        // already holding", and naming one couples the test to whichever tool
        // happens to be the default.
        let other = ToolKind.allCases.first { $0 != model.tool }!

        model.selectTool(other)
        #expect(model.isOptionsExpanded)

        model.selectTool(other)
        #expect(!model.isOptionsExpanded)

        model.selectTool(.eraser)
        #expect(model.isOptionsExpanded)

        // A shape picked from the gallery arms the shape tool and shows it.
        model.isOptionsExpanded = false
        model.selectShape(.star5)
        #expect(model.tool == .shape)
        #expect(model.shapeKind == .star5)
        #expect(model.isOptionsExpanded)
    }

    @Test("The toolbar remembers which edge it was moved to")
    func toolbarEdgePersists() {
        let model = EditorModel(canvas: Bitmap(width: 16, height: 16))
        let original = model.chromeEdge
        model.chromeEdge = original.toggled
        #expect(EditorModel.ChromeEdge.remembered == original.toggled)
        model.chromeEdge = original
        #expect(EditorModel.ChromeEdge.remembered == original)
    }

    @Test("The toolbar is equally thin on either edge")
    func toolbarGeometryFitsItsOrientation() {
        // One thickness, both orientations: the side rail is the bottom bar
        // stood on its end, so it has to be as thin as that bar is short.
        #expect(Tokens.Rail.thickness < 60)

        let window = CGSize(width: 1_000, height: 700)
        let besideLeftRail = Tokens.Chrome.canvasArea(in: window, rail: .left)
        let aboveBottomRail = Tokens.Chrome.canvasArea(in: window, rail: .bottom)

        // The rail takes its thickness off whichever axis it sits on, and
        // nothing off the other one.
        #expect(besideLeftRail.width < aboveBottomRail.width)
        #expect(aboveBottomRail.height < besideLeftRail.height)
        #expect(aboveBottomRail.width - besideLeftRail.width
            == besideLeftRail.height - aboveBottomRail.height)
    }

    @Test("The top header uses one centred control line")
    func topHeaderGeometryIsAligned() {
        #expect(Tokens.Size.headerControl == 32)
        #expect(Tokens.Chrome.titleReserve - Tokens.Size.headerControl == 12)
        #expect(Tokens.Chrome.trafficLightClearance == 68)
    }

    @Test("Brush size steps proportionally and stays in range")
    func brushStepsAndClamps() {
        let model = EditorModel(canvas: Bitmap(width: 16, height: 16))
        model.brushSize = 4
        model.stepBrushSize(up: true)
        #expect(model.brushSize == 5)

        model.brushSize = 40
        model.stepBrushSize(up: true)
        #expect(model.brushSize == 44)

        model.brushSize = ToolSettings.sizeRange.upperBound
        model.stepBrushSize(up: true)
        #expect(model.brushSize == ToolSettings.sizeRange.upperBound)

        model.brushSize = ToolSettings.sizeRange.lowerBound
        model.stepBrushSize(up: false)
        #expect(model.brushSize == ToolSettings.sizeRange.lowerBound)
    }

    @Test("Brush size commands are offered only to tools that have a size")
    func brushItemsValidate() {
        let document = DrawingDocument()
        let item = NSMenuItem(
            title: "Larger Brush",
            action: #selector(DrawingDocument.increaseBrush(_:)),
            keyEquivalent: ""
        )
        document.model.selectTool(.brush)
        #expect(document.validateMenuItem(item))
        document.model.selectTool(.eyedropper)
        #expect(!document.validateMenuItem(item))
    }
}
