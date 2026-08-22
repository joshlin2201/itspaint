import AppKit
import Darwin
import PaintKit
import SwiftUI
import UniformTypeIdentifiers

/// The document.
///
/// `NSDocument` rather than SwiftUI's `DocumentGroup`: this app needs a custom
/// package format, real undo integration, autosave-in-place, Versions, and
/// control over the window it opens into. `DocumentGroup` is concise but thin
/// in exactly those places, and discovering that late means rewriting the
/// document layer after the tools are already built on it.
final class DrawingDocument: NSDocument {

    let model: EditorModel

    /// Format this document was opened from, so Save writes it back the same
    /// way instead of silently converting the user's PNG into something else.
    private var sourceFormat: ImageCodec.Format?

    /// The PDF this document came from, when it came from one: the whole file,
    /// which page of it is on the canvas, and the size that page is printed at.
    /// Save writes the page back into it rather than replacing the document with
    /// one flat picture.
    private var pdfSource: PDFCodec.Source?

    /// The export panel's own job is built outside `write(to:ofType:)`, so the
    /// test that proves an exported page keeps its printed size needs the source
    /// the same way the panel gets it.
    var pdfSourceForTesting: PDFCodec.Source? { pdfSource }

    /// Kept so it can be torn down: without this, every document ever opened
    /// leaves an entry in the notification centre for the life of the process.
    ///
    /// Removed in `close()` rather than `deinit` because the token is not
    /// `Sendable`, and a `deinit` is nonisolated — Swift 6 will not let one touch
    /// main-actor state, which is the correct complaint. `close()` is the
    /// documented teardown point and it runs on the main actor.
    private var clipboardObserver: NSObjectProtocol?

    static let defaultCanvasSize = (width: 1280, height: 800)

    // MARK: - Lifecycle

    override init() {
        // The user's preferred size, falling back to the built-in default. The
        // constant stays as the fallback rather than being replaced, so a
        // corrupt or missing preference cannot produce a document with no
        // canvas at all.
        let size = Settings.shared.newCanvasSize
        let canvas = Bitmap(width: size.width, height: size.height, fill: .white)
        model = EditorModel(canvas: canvas)
        super.init()
        Settings.shared.apply(to: model)
        wireModel()
    }

    private func wireModel() {
        model.onCanvasChanged = { [weak self] _ in
            self?.updateChangeCount(.changeDone)
        }
        model.onEditCommitted = { [weak self] name in
            self?.registerUndoAction(named: name)
        }
        model.onDuplicate = { [weak self] in
            _ = try? self?.duplicate()
        }
        model.onTurnToPage = { [weak self] index in
            self?.turnToPage(index)
        }
        syncDocumentIdentity()
    }

    /// Mirror the filename and dirty flag into the model, because the title
    /// chip lives in the content view — the real titlebar is transparent so the
    /// artwork can reach the top edge.
    private func syncDocumentIdentity() {
        model.documentName = displayName ?? "Untitled"
        model.isEdited = isDocumentEdited
    }

    override func updateChangeCount(_ change: NSDocument.ChangeType) {
        super.updateChangeCount(change)
        MainActor.assumeIsolated { model.isEdited = isDocumentEdited }
    }

    override func close() {
        // Otherwise a stale closure keeps writing into a closed document.
        ColourPanelController.shared.relinquish(owner: model.colourPanelOwner)
        if let clipboardObserver {
            NotificationCenter.default.removeObserver(clipboardObserver)
            self.clipboardObserver = nil
        }
        super.close()
    }

    override class var autosavesInPlace: Bool { true }

    // `autosavingFileType` is deliberately NOT overridden.
    //
    // It used to return nil for imported images, to keep an autosave from
    // silently re-encoding someone's JPEG. What that actually bought was worse:
    // `autosavesInPlace` promises AppKit that changes are already safe on disk,
    // so closing an edited PNG asked nothing and threw the edit away — trim a
    // screenshot, press ⌘Q, and the work was gone. The same nil also leaves
    // `hasUnautosavedChanges` stuck true, so every close re-enters the autosave
    // machinery that cannot run.
    //
    // Nothing here sets `NSDocumentController.autosavingDelay`, so there is no
    // periodic autosave to degrade a lossy file: the only automatic write
    // happens when the document closes, which is the moment the user would have
    // pressed Save anyway.

    override var windowNibName: NSNib.Name? { nil }

    // MARK: - Windows

    override func makeWindowControllers() {
        let hosting = NSHostingController(rootView: EditorView(model: model))

        // Size the WINDOW to the artwork, not the artwork to a fixed window.
        //
        // Canvas-first means the frame should be barely perceptible, and
        // fitting a 1000×640 image into a window sized to 86% of a 6K display
        // cannot achieve that — the only ways to close the gap are to magnify
        // the artwork (which lies about pixel art) or to shrink the window to
        // the art. The second is honest, and it is what Preview does.
        //
        // The chrome floats *over* the canvas in this direction, so it claims
        // no space of its own; the gap below is a hairline, not a reservation.
        let sized = Self.windowFit(
            forCanvas: (model.canvas.width, model.canvas.height),
            on: NSScreen.main
        )
        model.setZoomExact(sized.zoom)

        let window = NSWindow(contentViewController: hosting)
        window.setContentSize(sized.contentSize)
        window.minSize = NSSize(width: 560, height: 420)
        window.title = displayName

        // Canvas-first: the artwork runs to all four edges, so the titlebar is
        // transparent and the content view extends under it. The filename moves
        // to its own glass chip in the content, and a scrim keeps the traffic
        // lights legible over bright artwork.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = false
        // Not `.preferred`: a forced tab bar occupies exactly the strip this
        // direction keeps transparent, and restates the filename the title chip
        // already shows. Users can still merge windows deliberately.
        window.tabbingMode = .automatic
        window.center()

        syncDocumentIdentity()

        // Follow the artwork when it grows — pasting a screenshot larger than
        // the canvas now enlarges the canvas, and a document that quietly
        // outgrows its window is one you have to resize by hand before you can
        // see what you just pasted.
        model.onCanvasResized = { [weak window, weak self] width, height in
            guard let window, let self, Settings.shared.resizeWindowWithCanvas else { return }
            self.growWindow(window, toFitCanvas: (width, height))
        }

        // The clipboard is the one piece of state that changes while this app is
        // *not* frontmost — copying a screenshot happens somewhere else, which is
        // the whole workflow. Re-reading on activation is what keeps the Paste
        // button from being stale the moment it matters most.
        clipboardObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.refreshClipboardState() }
        }
        model.refreshClipboardState()

        let controller = NSWindowController(window: window)
        controller.shouldCascadeWindows = true
        addWindowController(controller)
    }

    /// The window size and zoom a canvas of `size` wants.
    ///
    /// Shared by the open path and the grow path so a window opened at 1000×640
    /// and a window grown to 1000×640 are the same window.
    static func windowFit(
        forCanvas size: (width: Int, height: Int), on screen: NSScreen?
    ) -> (contentSize: NSSize, zoom: Double) {
        // Size the WINDOW to the artwork, not the artwork to a fixed window.
        //
        // Canvas-first means the frame should be barely perceptible, and
        // fitting a 1000×640 image into a window sized to 86% of a 6K display
        // cannot achieve that — the only ways to close the gap are to magnify
        // the artwork (which lies about pixel art) or to shrink the window to
        // the art. The second is honest, and it is what Preview does.
        let visible = screen?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        let ceiling = NSSize(width: visible.width * 0.94, height: visible.height * 0.94)

        // Scale down only if the artwork is bigger than the screen allows.
        let zoom = min(
            1,
            min(
                (ceiling.width - Tokens.Chrome.frameGap * 2) / Double(max(1, size.width)),
                (ceiling.height - Tokens.Chrome.frameGap * 2) / Double(max(1, size.height))
            )
        )
        let contentSize = NSSize(
            width: min(
                max(Double(size.width) * zoom + Tokens.Chrome.frameGap * 2, 560),
                ceiling.width
            ),
            height: min(
                max(Double(size.height) * zoom + Tokens.Chrome.frameGap * 2, 420),
                ceiling.height
            )
        )
        return (contentSize, zoom)
    }

    /// Enlarge the window to hold a grown canvas, keeping it on screen.
    ///
    /// **Only ever grows.** Shrinking would fight a window the user has
    /// deliberately sized, and cropping a canvas is a far rarer intent than
    /// pasting into one.
    private func growWindow(_ window: NSWindow, toFitCanvas size: (width: Int, height: Int)) {
        let wanted = Self.windowFit(forCanvas: size, on: window.screen ?? NSScreen.main).contentSize
        let current = window.contentLayoutRect.size
        guard wanted.width > current.width + 1 || wanted.height > current.height + 1 else { return }

        let target = NSSize(
            width: max(current.width, wanted.width),
            height: max(current.height, wanted.height)
        )
        // Grow from the window's own centre rather than its bottom-left, which
        // is what `setContentSize` alone does — a window that expands downward
        // off the screen edge is worse than one that did not grow at all.
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: target))
        frame.origin = NSPoint(
            x: window.frame.midX - frame.width / 2,
            y: window.frame.midY - frame.height / 2
        )
        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        }
        window.setFrame(frame, display: true, animate: true)
    }

    // MARK: - Concurrency contract for file I/O
    //
    // `read` and `write` are nonisolated on NSDocument because AppKit is
    // allowed to run them off the main thread. This document opts out of both,
    // so the main-actor model is genuinely safe to touch inside them. Pinning
    // it explicitly — rather than relying on the framework default — is what
    // makes `MainActor.assumeIsolated` below a guarantee instead of a hope.

    override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool { false }

    override func canAsynchronouslyWrite(
        to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType
    ) -> Bool { false }

    // MARK: - Reading

    override func read(from url: URL, ofType typeName: String) throws {
        // Decode first, off the model entirely: a failed read must leave the
        // open document untouched rather than half-replaced.
        let isPackage = typeName == Self.packageType || url.pathExtension.lowercased() == "itspaint"
        let format = isPackage ? nil : ImageCodec.Format.inferred(from: url)

        // A PDF arrives as a page and a way back to the file it came from. The
        // whole file is kept, because saving has to put the other pages back —
        // signing page four of a lease must not cost anyone pages one to three.
        if format == .pdf {
            let page = try PDFCodec.open(contentsOf: url)
            MainActor.assumeIsolated {
                sourceFormat = .pdf
                pdfSource = page.source
                model.pdfPage = (index: page.source.pageIndex, count: page.source.pageCount)
                model.load(canvas: page.bitmap, metadata: nil)
            }
            return
        }

        let contents = isPackage
            ? try Self.readPackage(at: url)
            : (canvas: try ImageCodec.decode(contentsOf: url), metadata: nil)

        MainActor.assumeIsolated {
            sourceFormat = format
            pdfSource = nil
            model.pdfPage = nil
            // Loaded into the existing model rather than a fresh one: Revert to
            // Saved reads into a document whose window already captured this
            // object, so replacing it would leave the old pixels on screen.
            model.load(canvas: contents.canvas, metadata: contents.metadata)
        }
    }

    // MARK: - Pages

    /// Turn to another page of the PDF this document was opened from.
    ///
    /// The current page's edits are folded back into the in-memory file first,
    /// so a signature on page four is still there when you come back from page
    /// five. Undo does not cross the page boundary — the canvas is genuinely a
    /// different image — which is why the fold happens here rather than at save
    /// time: the alternative is losing the signature to a page turn.
    private func turnToPage(_ index: Int) {
        guard let source = pdfSource, index != source.pageIndex,
              index >= 0, index < source.pageCount
        else { return }

        do {
            let folded = try PDFCodec.encode(model.canvas, replacing: source)
            let page = try PDFCodec.open(
                data: folded,
                page: index,
                named: displayName.isEmpty ? "This document" : displayName
            )
            pdfSource = page.source
            model.pdfPage = (index: page.source.pageIndex, count: page.source.pageCount)
            model.load(canvas: page.bitmap, metadata: nil)
            // **The history does not cross the page boundary.** Every registered
            // undo replays a bitmap edit onto whatever canvas is loaded, so an
            // undo left over from page four would paint page four's pixels onto
            // page five. Revert to Saved clears the stack for the same reason.
            undoManager?.removeAllActions()
            // The fold is a real change to the file even though the visible
            // page has only been swapped, so the document is dirty until saved.
            updateChangeCount(.changeDone)
        } catch {
            model.present(
                message: error.localizedDescription,
                recovery: (error as? LocalizedError)?.recoverySuggestion
            )
        }
    }

    /// The pixels, plus the editing state stored beside them. A package written
    /// by an older build (or with a damaged `document.json`) still opens — the
    /// artwork is the document, the rest is preference.
    nonisolated private static func readPackage(
        at url: URL
    ) throws -> (canvas: Bitmap, metadata: DocumentMetadata?) {
        let packageDescriptor = try openPackageDirectory(at: url)
        defer { Darwin.close(packageDescriptor) }

        let canvasURL = url.appendingPathComponent(PackageEntry.image)
        let canvasData = try readRegularEntry(
            named: PackageEntry.image,
            in: packageDescriptor,
            maximumBytes: PackagePolicy.maximumCanvasBytes
        )
        let canvas = try ImageCodec.decode(data: canvasData, sourceURL: canvasURL)

        // Metadata is preference, not artwork. Missing, damaged, oversized or
        // non-regular metadata therefore falls back to the defaults, while the
        // required canvas remains fail-closed above.
        let metadata: DocumentMetadata?
        do {
            let data = try readRegularEntry(
                named: PackageEntry.metadata,
                in: packageDescriptor,
                maximumBytes: PackagePolicy.maximumMetadataBytes
            )
            metadata = try? JSONDecoder().decode(DocumentMetadata.self, from: data)
        } catch {
            metadata = nil
        }
        return (canvas, metadata)
    }

    /// Open the package once and resolve both fixed child names relative to
    /// that pinned directory. This keeps validation and use attached to one
    /// directory even if its pathname is replaced concurrently.
    nonisolated private static func openPackageDirectory(at url: URL) throws -> Int32 {
        let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            throw PackageReadError.unreadablePackage(url)
        }
        return descriptor
    }

    /// Read a fixed package child through `openat`, refusing symlinks and every
    /// non-regular file type. The size check is repeated by a capped read loop,
    /// so growing a file after `fstat` cannot turn this into an unbounded read.
    nonisolated private static func readRegularEntry(
        named name: String,
        in packageDescriptor: Int32,
        maximumBytes: Int
    ) throws -> Data {
        guard !name.contains("/"), name != ".", name != ".." else {
            throw PackageReadError.invalidEntry(name)
        }

        let descriptor = name.withCString {
            Darwin.openat(
                packageDescriptor,
                $0,
                // `O_NONBLOCK` prevents a malicious FIFO from hanging before
                // `fstat` gets the chance to reject it as non-regular.
                O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK
            )
        }
        guard descriptor >= 0 else {
            throw PackageReadError.invalidEntry(name)
        }
        defer { Darwin.close(descriptor) }

        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0,
              (information.st_mode & S_IFMT) == S_IFREG
        else {
            throw PackageReadError.invalidEntry(name)
        }
        guard information.st_size >= 0,
              UInt64(information.st_size) <= UInt64(maximumBytes)
        else {
            throw PackageReadError.entryTooLarge(name, maximumBytes: maximumBytes)
        }

        var result = Data()
        result.reserveCapacity(min(Int(information.st_size), maximumBytes))
        while result.count <= maximumBytes {
            let requested = min(64 * 1024, maximumBytes + 1 - result.count)
            var chunk = Data(count: requested)
            let byteCount = chunk.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, $0.count)
            }
            if byteCount < 0 {
                if errno == EINTR { continue }
                throw PackageReadError.unreadableEntry(name)
            }
            if byteCount == 0 { break }
            result.append(chunk.prefix(byteCount))
        }
        guard result.count <= maximumBytes else {
            throw PackageReadError.entryTooLarge(name, maximumBytes: maximumBytes)
        }
        return result
    }

    // MARK: - Writing

    /// Everything writing needs, lifted off the main actor in one hop.
    private struct WriteSnapshot: Sendable {
        let canvas: Bitmap
        let foreground: PaintColour
        let background: PaintColour
        let palette: Palette
        let sourceFormat: ImageCodec.Format?
        let pdfSource: PDFCodec.Source?
    }

    nonisolated private func makeWriteSnapshot() -> WriteSnapshot {
        MainActor.assumeIsolated {
            WriteSnapshot(
                canvas: model.canvas,
                foreground: model.foreground,
                background: model.background,
                palette: model.palette,
                sourceFormat: sourceFormat,
                pdfSource: pdfSource
            )
        }
    }

    override func write(to url: URL, ofType typeName: String) throws {
        let snapshot = makeWriteSnapshot()

        if typeName == Self.packageType || url.pathExtension.lowercased() == "itspaint" {
            try Self.writePackage(snapshot, to: url)
            return
        }

        let format = ImageCodec.Format.inferred(from: url) ?? snapshot.sourceFormat ?? .png
        try ImageCodec.write(
            snapshot.canvas,
            to: url,
            as: format,
            matte: snapshot.background,
            // Saving a PDF puts the edited page back into the document it came
            // from. Only when it *is* the same document: Save As to a different
            // PDF gets the same treatment, which is what someone signing a copy
            // of a contract means by "save as signed.pdf".
            pdfSource: format == .pdf ? snapshot.pdfSource : nil
        )
    }

    /// The `.itspaint` package: a lossless PNG plus the editing state that a flat
    /// image cannot carry. Storing the pixels as PNG rather than a private blob
    /// means the artwork is recoverable with any image tool even if this app
    /// disappears — a document format should never hold work hostage.
    nonisolated private static func writePackage(_ snapshot: WriteSnapshot, to url: URL) throws {
        let fileManager = FileManager.default
        let temporary = fileManager.temporaryDirectory
            .appendingPathComponent("itspaint-write-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporary) }

        try ImageCodec.write(
            snapshot.canvas,
            to: temporary.appendingPathComponent(PackageEntry.image),
            as: .png
        )

        let metadata = DocumentMetadata(
            formatVersion: DocumentMetadata.currentVersion,
            width: snapshot.canvas.width,
            height: snapshot.canvas.height,
            foreground: snapshot.foreground,
            background: snapshot.background,
            palette: snapshot.palette
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(metadata)
            .write(to: temporary.appendingPathComponent(PackageEntry.metadata))

        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try fileManager.moveItem(at: temporary, to: url)
    }

    // MARK: - Types

    nonisolated static let packageType = "com.joshlin.itspaint-drawing"

    enum PackageEntry {
        nonisolated static let image = "canvas.png"
        nonisolated static let metadata = "document.json"
    }

    enum PackagePolicy {
        /// Metadata written by the app is only a few kilobytes. A 256 KiB cap
        /// leaves ample format-growth room without exposing JSON decoding to an
        /// attacker-controlled allocation.
        nonisolated static let maximumMetadataBytes = 256 * 1024

        /// A maximum-size decoded canvas can produce a roughly 128 MiB PNG in
        /// the incompressible case. Twice that size preserves legitimate work
        /// while bounding the encoded-data copy used by the package reader.
        nonisolated static let maximumCanvasBytes = 256 * 1024 * 1024
    }

    override class var readableTypes: [String] {
        [packageType] + ImageCodec.Format.allCases.map(\.utType.identifier)
    }

    override class var writableTypes: [String] {
        [packageType] + ImageCodec.Format.allCases.map(\.utType.identifier)
    }

    override func fileNameExtension(
        forType typeName: String, saveOperation: NSDocument.SaveOperationType
    ) -> String? {
        if typeName == Self.packageType { return "itspaint" }
        return ImageCodec.Format.allCases
            .first { $0.utType.identifier == typeName }?
            .fileExtension
    }

    // MARK: - Undo bridge

    /// The engine owns the pixel history; `NSUndoManager` owns the user-facing
    /// sequencing, menu titles, autosave coordination and Versions. Registering
    /// the inverse from inside each replay is what keeps the two in lockstep
    /// instead of drifting into two independent stacks.
    private func registerUndoAction(named name: String) {
        guard let undoManager else { return }
        // `registerUndo`'s handler is nonisolated, and AppKit runs it on the
        // main thread. Swift 6.1 requires that to be said out loud; 6.2 infers
        // it, which is how this compiled locally and failed on CI.
        undoManager.registerUndo(withTarget: self) { document in
            MainActor.assumeIsolated { document.replayUndo() }
        }
        undoManager.setActionName(name)
    }

    private func replayUndo() {
        let name = model.engine.undoStack.undoActionName ?? "Edit"
        model.undo()
        undoManager?.registerUndo(withTarget: self) { document in
            MainActor.assumeIsolated { document.replayRedo() }
        }
        undoManager?.setActionName(name)
    }

    private func replayRedo() {
        let name = model.engine.undoStack.redoActionName ?? "Edit"
        model.redo()
        undoManager?.registerUndo(withTarget: self) { document in
            MainActor.assumeIsolated { document.replayUndo() }
        }
        undoManager?.setActionName(name)
    }

    // MARK: - Export

    @IBAction func exportImage(_ sender: Any?) {
        guard let window = windowControllers.first?.window else { return }

        let options = ExportOptions()
        // A document that came from a PDF exports as one by default. Offering
        // PNG first to someone who has just signed a contract is offering to
        // throw the other pages away.
        if pdfSource != nil { options.format = .pdf }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [options.format.utType]
        panel.nameFieldStringValue = (displayName as NSString).deletingPathExtension
        panel.canCreateDirectories = true
        panel.message = "Choose a format and a size."

        // A real accessory view rather than trusting the typed extension: the
        // format list is checked against the encoders this machine actually
        // has, and the scale is applied before encoding, so "export at 2×"
        // does not mean "resize the document and undo it afterwards".
        let accessory = NSHostingView(
            rootView: ExportAccessory(options: options, canvas: (canvas: model.canvas.width, model.canvas.height)) { format in
                panel.allowedContentTypes = [format.utType]
            }
        )
        accessory.frame = NSRect(x: 0, y: 0, width: 380, height: 84)
        panel.accessoryView = accessory

        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            let job = options.job(
                canvas: self.model.canvas,
                matte: self.model.background,
                pdfSource: self.pdfSource
            )
            Task { @MainActor [weak self] in
                let failure = await Task.detached(priority: .userInitiated) {
                    do {
                        try job.write(to: url)
                        return nil as ExportFailure?
                    } catch {
                        return ExportFailure(
                            message: error.localizedDescription,
                            // Any `LocalizedError`, not just the image codec's:
                            // PDF failures carry their own next step, and
                            // dropping it left the alert as a dead end.
                            recovery: (error as? LocalizedError)?.recoverySuggestion
                        )
                    }
                }.value
                if let failure {
                    self?.model.present(
                        message: failure.message,
                        recovery: failure.recovery
                    )
                }
            }
        }
    }
}

/// Actionable package failures shown by NSDocument. Optional metadata errors
/// are absorbed by `readPackage`; these messages therefore describe failures
/// that prevent the artwork itself from opening.
private enum PackageReadError: LocalizedError {
    case unreadablePackage(URL)
    case invalidEntry(String)
    case entryTooLarge(String, maximumBytes: Int)
    case unreadableEntry(String)

    var errorDescription: String? {
        switch self {
        case .unreadablePackage(let url):
            "Couldn't open \(url.lastPathComponent)."
        case .invalidEntry(let name):
            "The drawing's \(name) isn't a regular file inside the package."
        case .entryTooLarge(let name, _):
            "The drawing's \(name) is too large to open safely."
        case .unreadableEntry(let name):
            "Couldn't read the drawing's \(name)."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .unreadablePackage:
            "Check that the drawing still exists and you have permission to open it."
        case .invalidEntry, .unreadableEntry:
            "Open the package in Finder and make sure canvas.png is a regular PNG file."
        case .entryTooLarge(_, let maximumBytes):
            "Use a canvas.png smaller than \(ByteCountFormatter.string(fromByteCount: Int64(maximumBytes), countStyle: .file))."
        }
    }
}

/// Editing state stored alongside the pixels in a `.itspaint` package.
struct DocumentMetadata: Codable {
    static let currentVersion = 1

    let formatVersion: Int
    let width: Int
    let height: Int
    let foreground: PaintColour
    let background: PaintColour
    let palette: Palette
}

/// Everything an export needs, captured when the save panel closes.
///
/// Value semantics make this an immutable snapshot of the pixels and settings,
/// so the encoder can leave the main actor without racing a later edit.
struct ExportJob: Sendable {
    let canvas: Bitmap
    let format: ImageCodec.Format
    let scale: Double
    let quality: Double
    let matte: PaintColour
    /// Set when the document was opened from a PDF, so exporting one keeps the
    /// document's other pages and its page size.
    var pdfSource: PDFCodec.Source?

    func scaledCanvas() throws -> Bitmap {
        guard scale != 1 else { return canvas }
        let rawWidth = (Double(canvas.width) * scale).rounded()
        let rawHeight = (Double(canvas.height) * scale).rounded()
        guard rawWidth.isFinite, rawHeight.isFinite,
              rawWidth >= 1, rawHeight >= 1,
              rawWidth <= Double(Int.max), rawHeight <= Double(Int.max)
        else {
            throw ImageCodec.CodecError.imageTooLarge(
                width: Bitmap.maximumDimension + 1,
                height: Bitmap.maximumDimension + 1
            )
        }
        let target = (width: Int(rawWidth), height: Int(rawHeight))
        guard Bitmap.isSizeSupported(width: target.width, height: target.height) else {
            throw ImageCodec.CodecError.imageTooLarge(
                width: target.width,
                height: target.height
            )
        }
        guard let scaled = ImageTransform.scaled(canvas, to: target, using: .smooth) else {
            throw ImageCodec.CodecError.encodeFailed(format)
        }
        return scaled
    }

    func write(to url: URL) throws {
        try ImageCodec.write(
            scaledCanvas(),
            to: url,
            as: format,
            quality: quality,
            matte: matte,
            pdfSource: format == .pdf ? pdfSource?.resampled(by: scale) : nil
        )
    }
}

private struct ExportFailure: Sendable {
    let message: String
    let recovery: String?
}

/// What the export panel collects.
///
/// Observable so the accessory view can drive the panel's own file type as the
/// format changes — a save panel that keeps offering `.png` while the popup
/// says JPEG is a trap, not a default.
@MainActor
@Observable
final class ExportOptions {
    var format: ImageCodec.Format = .png
    var scale: Double = 1
    var quality: Double = 0.9

    func job(
        canvas: Bitmap, matte: PaintColour, pdfSource: PDFCodec.Source? = nil
    ) -> ExportJob {
        ExportJob(
            canvas: canvas,
            format: format,
            scale: scale,
            quality: quality,
            matte: matte,
            pdfSource: pdfSource
        )
    }

    /// The artwork at the chosen scale, resampled smoothly.
    func scaled(_ bitmap: Bitmap) throws -> Bitmap {
        try job(canvas: bitmap, matte: .white).scaledCanvas()
    }
}

/// Format, scale and (for lossy formats) quality, inside the save panel.
private struct ExportAccessory: View {
    @Bindable var options: ExportOptions
    let canvas: (canvas: Int, Int)
    let onFormatChange: (ImageCodec.Format) -> Void

    private static let scales: [(label: String, value: Double)] = [
        ("25%", 0.25), ("50%", 0.5), ("100%", 1), ("200%", 2), ("400%", 4),
    ]

    var body: some View {
        Form {
            Picker("Format", selection: $options.format) {
                // Only what this machine can actually write.
                ForEach(ImageCodec.Format.exportable) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .onChange(of: options.format) { _, format in onFormatChange(format) }

            Picker("Size", selection: $options.scale) {
                ForEach(Self.scales, id: \.value) { scale in
                    let width = Int(Double(canvas.canvas) * scale.value)
                    let height = Int(Double(canvas.1) * scale.value)
                    Text("\(scale.label) · \(width) × \(height)")
                        .tag(scale.value)
                        .disabled(!Bitmap.isSizeSupported(width: width, height: height))
                }
            }

            if options.format.supportsQuality {
                Slider(value: $options.quality, in: 0.3...1) {
                    Text("Quality")
                } minimumValueLabel: {
                    Text("Small")
                } maximumValueLabel: {
                    Text("Best")
                }
            }
            if options.format.requiresIconSize {
                Text("Icons are square: the artwork is fitted and centred.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
    }
}
