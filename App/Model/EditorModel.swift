import AppKit
import PaintKit
import Observation
import SwiftUI

/// The observable bridge between `PaintEngine` (pure model) and SwiftUI.
///
/// The engine deliberately knows nothing about the UI or the pasteboard, so
/// this is where those concerns live: zoom, the pointer read-out, panel state,
/// clipboard translation, and the change counter the canvas view watches.
@MainActor
@Observable
final class EditorModel {

    // MARK: - Engine

    @ObservationIgnored let engine: PaintEngine

    /// Bumped whenever the canvas pixels or the selection change, so the view
    /// can invalidate without diffing a megabyte of pixels.
    private(set) var revision: Int = 0

    // MARK: - Tool state (mirrored for SwiftUI bindings)

    var tool: ToolKind {
        didSet {
            guard tool != oldValue else { return }
            engine.settings.tool = tool
            // A half-built curve or polygon belongs to the tool that started
            // it; landing it here is what stops it vanishing on a tool change.
            noteChange(engine.commitPendingShape())
            // Switching away from a selection tool lands anything floating,
            // so the pixels are never left in limbo.
            if !tool.isRegionDrag {
                noteChange(engine.commitFloating())
            }
            applySizeFloor(leaving: oldValue)
        }
    }

    /// The size chosen before a tool's floor raised it, or nil if none did.
    @ObservationIgnored private var sizeBeforeFloor: Int?

    /// Keep the size control honest without letting one tool's floor be permanent.
    ///
    /// Arming a tool has to move the size up to that tool's floor, or the panel goes
    /// back to showing a number the stroke will not honour. Doing only that, with a
    /// one-way `max`, meant a single visit to the highlighter took 1–3px away from
    /// the brush, the badge and every shape outline for the rest of the session, and
    /// nothing on screen explained why the small sizes had stopped existing.
    ///
    /// So the chosen size is kept and handed back the moment a tool can honour it.
    /// If it was changed while the floor was in force it is not handed back, because
    /// then the number on screen is one somebody picked on purpose.
    private func applySizeFloor(leaving previous: ToolKind) {
        let floor = ToolSettings.sizeRange(for: tool).lowerBound
        if brushSize < floor {
            if sizeBeforeFloor == nil { sizeBeforeFloor = brushSize }
            brushSize = floor
        } else if let remembered = sizeBeforeFloor {
            if brushSize == ToolSettings.sizeRange(for: previous).lowerBound {
                brushSize = remembered
            }
            sizeBeforeFloor = nil
        }
    }

    var shapeKind: ShapeKind {
        didSet {
            guard shapeKind != oldValue else { return }
            // A half-built curve or polygon belongs to the shape that was
            // active when it started, so land it before the kind changes under
            // it.
            noteChange(engine.commitPendingShape())
            engine.settings.shapeKind = shapeKind
        }
    }

    /// Which marquee the select tool drags out.
    var selectionKind: SelectionKind {
        didSet {
            engine.settings.selectionKind = selectionKind
            tool = .select
        }
    }

    /// Solid, dashed or dotted outlines.
    var strokeDash: Raster.Dash { didSet { engine.settings.strokeDash = strokeDash } }

    var sprayDensity: Double { didSet { engine.settings.sprayDensity = sprayDensity } }

    /// Whether the brush's current tip sprays. The canvas's hold-still timer and
    /// the Flow row both key off this, so neither can disagree with the engine
    /// about what the tip is doing.
    var isSpraying: Bool { engine.settings.isSpraying }

    /// Point size of the text tool, mirrored so the options panel can bind to
    /// it like every other setting.
    var textSize: Double {
        didSet { engine.settings.textStyle.pointSize = max(6, textSize) }
    }

    var textFont: String { didSet { engine.settings.textStyle.fontName = textFont } }

    var textAlignment: PaintKit.TextRenderer.Style.Alignment {
        didSet { engine.settings.textStyle.alignment = textAlignment }
    }

    var isTextBold: Bool { didSet { engine.settings.textStyle.isBold = isTextBold } }
    var isTextItalic: Bool { didSet { engine.settings.textStyle.isItalic = isTextItalic } }
    var isTextUnderlined: Bool {
        didSet { engine.settings.textStyle.isUnderlined = isTextUnderlined }
    }
    var brushSize: Int { didSet { engine.settings.brushSize = brushSize } }
    var brushShape: Brush.Shape { didSet { engine.settings.brushShape = brushShape } }
    var shapeStyle: PaintKit.ShapeStyle { didSet { engine.settings.shapeStyle = shapeStyle } }
    var fillTolerance: Int { didSet { engine.settings.fillTolerance = fillTolerance } }
    var selectionTolerance: Int { didSet { engine.settings.selectionTolerance = selectionTolerance } }
    var cornerRadius: Int { didSet { engine.settings.cornerRadius = cornerRadius } }
    var highlighterOpacity: Double { didSet { engine.settings.highlighterOpacity = highlighterOpacity } }
    var highlighterColour: PaintColour? { didSet { engine.settings.highlighterColour = highlighterColour } }
    var pixelateBlockSize: Int { didSet { engine.settings.pixelateBlockSize = pixelateBlockSize } }
    var spotlightDim: Double { didSet { engine.settings.spotlightDim = spotlightDim } }
    var smoothEdges: Bool { didSet { engine.settings.smoothEdges = smoothEdges } }
    var cloneMode: CloneMode { didSet { engine.settings.cloneMode = cloneMode } }
    var cloneOpacity: Double { didSet { engine.settings.cloneOpacity = cloneOpacity } }
    var softenStrength: Double { didSet { engine.settings.softenStrength = softenStrength } }
    var cloneSoftTip: Bool { didSet { engine.settings.cloneSoftTip = cloneSoftTip } }

    /// Whether a source has been picked, so the panel can say what the next click does.
    var hasCloneSource: Bool { engine.cloneSource != nil }

    /// Arm the clone cell in a specific mode.
    ///
    /// Not `selectTool`, which toggles the options panel when the tool is already
    /// armed — pressing `F` while on Clone would collapse the panel and leave you in
    /// Soften with nothing on screen saying so.
    func selectCloneMode(_ mode: CloneMode) {
        cloneMode = mode
        tool = .clone
        isOptionsExpanded = true
    }

    var foreground: PaintColour {
        didSet {
            engine.colours.foreground = foreground
            rememberColour(foreground)
        }
    }

    var background: PaintColour { didSet { engine.colours.background = background } }

    var palette: Palette = .standard

    /// Colours used recently that are not already in the fixed palette.
    ///
    /// The 28 swatches are muscle memory and must not move, so custom colours
    /// get their own short row in the popover instead of displacing them. Kept
    /// out of the rail deliberately: they arrive unpredictably, and a toolbar
    /// that changes size while you work moves the button you were reaching for.
    /// Most recent first.
    private(set) var recentColours: [PaintColour] = []

    private func rememberColour(_ colour: PaintColour) {
        guard !palette.swatches.contains(colour) else { return }
        recentColours.removeAll { $0 == colour }
        recentColours.insert(colour, at: 0)
        if recentColours.count > 8 { recentColours.removeLast() }
    }

    /// A stable identity for this model, so the shared colour panel knows which
    /// document currently owns it.
    let colourPanelOwner = UUID().uuidString

    // MARK: - View state

    /// Canvas zoom, snapped to a discrete step. An arbitrary 137% zoom makes a
    /// paint app's pixels shimmer.
    ///
    /// A computed property over private storage rather than a `didSet` that
    /// reassigns itself: under `@Observable` a stored property becomes
    /// computed, and Swift's "assignment inside `didSet` does not re-enter"
    /// rule only holds for *true* stored properties — so the obvious
    /// `didSet { zoom = snapped }` recurses until the stack overflows.
    var zoom: Double {
        get { storedZoom }
        set { storedZoom = Self.nearestZoomStep(to: newValue) }
    }

    private var storedZoom: Double = 1

    static let zoomSteps: [Double] = [0.25, 0.5, 1, 2, 4, 8, 16]

    static func nearestZoomStep(to value: Double) -> Double {
        zoomSteps.min(by: { abs($0 - value) < abs($1 - value) }) ?? 1
    }

    /// Pointer position in canvas pixels, or nil when outside.
    var pointerPosition: PixelPoint?

    /// Which edge the toolbar lives on.
    ///
    /// Left by default — a vertical rail is how every paint tool since 1985 has
    /// been laid out, and it leaves the full width of the window to the
    /// artwork. Remembered across launches because it is a preference, not a
    /// per-document choice.
    var chromeEdge: ChromeEdge = ChromeEdge.remembered {
        didSet { chromeEdge.remember() }
    }

    enum ChromeEdge: String, CaseIterable, Sendable {
        case left, bottom

        var isVertical: Bool { self == .left }
        var displayName: String { self == .left ? "Left" : "Bottom" }
        var symbolName: String {
            self == .left ? "sidebar.leading" : "rectangle.bottomthird.inset.filled"
        }
        var toggled: ChromeEdge { self == .left ? .bottom : .left }

        private static let defaultsKey = "chromeEdge"

        static var remembered: ChromeEdge {
            UserDefaults.standard.string(forKey: defaultsKey).flatMap(ChromeEdge.init) ?? .left
        }

        func remember() {
            UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
        }
    }

    /// The next number the badge tool will drop.
    ///
    /// **Mirrored, not forwarded.** `PaintEngine` is deliberately UI-free and so
    /// not `@Observable`; a computed passthrough to it is invisible to SwiftUI,
    /// which is why the rail cell and the panel hint both sat on whatever number
    /// they had happened to render first and only moved when something *else*
    /// invalidated them.
    ///
    /// The obvious fix is to read `revision` in those views, the way the header
    /// strip does for undo's flags. It is the wrong one here: `revision` bumps on
    /// every dirty rect, which during a freehand stroke is every mouse-moved
    /// event, so the whole rail and panel would re-render sixty times a second to
    /// track a number that changes once per badge. Syncing the mirror only when
    /// the value genuinely differs makes the notification exact.
    private(set) var nextBadgeNumber: Int = 1

    /// Pull the counter across if the engine has moved it. Called from the same
    /// place every other post-edit bookkeeping happens, so a badge dropped by any
    /// route — pointer, menu, undo, redo — lands here.
    private func syncBadgeNumber() {
        if nextBadgeNumber != engine.nextBadgeNumber {
            nextBadgeNumber = engine.nextBadgeNumber
        }
    }

    func resetBadgeNumbering() {
        engine.resetBadgeNumbering()
        syncBadgeNumber()
    }

    /// Set the number the next badge carries, for a sequence continued across
    /// more than one screenshot.
    func setNextBadgeNumber(_ number: Int) {
        engine.setNextBadgeNumber(number)
        syncBadgeNumber()
    }

    /// True while a curve or polygon is half-built, so the chrome can say how
    /// to finish it.
    var hasPendingShape: Bool { engine.hasPendingShape }

    /// Whether the active tool's options panel is showing.
    ///
    /// Expanded when you pick a tool, dismissed the moment you touch the
    /// canvas — the panel is a step in choosing how to draw, not a permanent
    /// inspector, and leaving it over the artwork while you draw is exactly
    /// what makes floating panels annoying.
    var isOptionsExpanded: Bool = true

    var showsGrid: Bool = false
    /// Alignment-grid spacing in pixels, 0 for off. Mirrors `settings.snapGrid`.
    ///
    /// Turning it on draws the grid too. Snapping you cannot see is a drag that
    /// disobeys you for reasons you have to guess.
    var snapGrid: Int = 0 { didSet { engine.settings.snapGrid = snapGrid } }
    /// Set by ⇧⌘C; the cluster's colour well observes it and opens.
    var isColourPopoverRequested: Bool = false
    var isSizeSheetPresented: Bool = false

    var presentedError: PresentableError?

    struct PresentableError: Identifiable {
        let id = UUID()
        let message: String
        let recovery: String?
    }

    // MARK: - Lifecycle

    init(engine: PaintEngine) {
        self.engine = engine
        self.lastKnownCanvasSize = (engine.canvas.width, engine.canvas.height)
        self.tool = engine.settings.tool
        self.shapeKind = engine.settings.shapeKind
        self.brushSize = engine.settings.brushSize
        self.brushShape = engine.settings.brushShape
        self.shapeStyle = engine.settings.shapeStyle
        self.fillTolerance = engine.settings.fillTolerance
        self.selectionTolerance = engine.settings.selectionTolerance
        self.cornerRadius = engine.settings.cornerRadius
        self.highlighterOpacity = engine.settings.highlighterOpacity
        self.highlighterColour = engine.settings.highlighterColour
        self.pixelateBlockSize = engine.settings.pixelateBlockSize
        self.spotlightDim = engine.settings.spotlightDim
        self.smoothEdges = engine.settings.smoothEdges
        self.cloneMode = engine.settings.cloneMode
        self.cloneOpacity = engine.settings.cloneOpacity
        self.softenStrength = engine.settings.softenStrength
        self.cloneSoftTip = engine.settings.cloneSoftTip
        self.selectionKind = engine.settings.selectionKind
        self.strokeDash = engine.settings.strokeDash
        self.sprayDensity = engine.settings.sprayDensity
        self.textSize = engine.settings.textStyle.pointSize
        self.textFont = engine.settings.textStyle.fontName
        self.textAlignment = engine.settings.textStyle.alignment
        self.isTextBold = engine.settings.textStyle.isBold
        self.isTextItalic = engine.settings.textStyle.isItalic
        self.isTextUnderlined = engine.settings.textStyle.isUnderlined
        self.foreground = engine.colours.foreground
        self.background = engine.colours.background
        // Seed rather than leave the cache empty. A document opened while the
        // clipboard already holds a screenshot is the most common way this app
        // gets used, and it would have shown Paste disabled until something else
        // happened to refresh it.
        refreshClipboardState()
    }

    convenience init(canvas: Bitmap) {
        self.init(engine: PaintEngine(canvas: canvas))
    }

    /// Load a document's contents in place — Open reads into a fresh document,
    /// but Revert to Saved reuses this one, and its window captured this object
    /// when it opened.
    ///
    /// Deliberately does not go through `noteChange`: a read is not an edit,
    /// and marking the document dirty for it would offer to save a file back
    /// over itself the moment it opened.
    func load(canvas: Bitmap, metadata: DocumentMetadata?) {
        engine.reset(to: canvas)
        if let metadata {
            foreground = metadata.foreground
            background = metadata.background
            palette = metadata.palette
        }
        lastKnownUndoCount = 0
        // Re-seed: an open or a revert is not a resize, and comparing against
        // the previous document's size would announce one.
        lastKnownCanvasSize = (canvas.width, canvas.height)
        pointerPosition = nil
        syncBadgeNumber()
        revision &+= 1
    }

    // MARK: - Canvas access

    var canvas: Bitmap { engine.canvas }
    var canvasSize: (width: Int, height: Int) { (engine.canvas.width, engine.canvas.height) }
    var canUndo: Bool { engine.canUndo }
    var canRedo: Bool { engine.canRedo }
    var selection: Selection? { engine.selection }
    var selectionBounds: PixelRect? { engine.selectionBounds }
    /// The traced lasso outline, for drawing its ants along the real shape.
    var lassoPath: [PixelPoint] { engine.lassoPath }
    var floating: FloatingSelection? { engine.floating }
    var hasSelection: Bool { engine.hasSelection }

    func noteChange(_ dirty: PixelRect) {
        guard !dirty.isEmpty else { return }
        noteVisualChange(dirty)
        syncBadgeNumber()
        noteCanvasSizeIfChanged()
        onCanvasChanged?(dirty)

        // Distinguish a *new* edit from an undo/redo replay. Only the former
        // registers an undo action, otherwise undoing would push another undo
        // and ⌘Z would never reach the beginning.
        let count = engine.undoStack.undoCount
        if count > lastKnownUndoCount {
            onEditCommitted?(engine.undoStack.undoActionName ?? "Edit")
        }
        lastKnownUndoCount = count
    }

    /// Invalidates canvas chrome without marking the document edited.
    ///
    /// Selections change what the user sees, but not the artwork they would
    /// save. Keeping that distinction here prevents a read-only marquee from
    /// lighting the document's dirty dot.
    func noteVisualChange(_ dirty: PixelRect) {
        guard !dirty.isEmpty else { return }
        revision &+= 1
        syncFloatingState()
    }

    @ObservationIgnored private var lastKnownUndoCount: Int = 0
    @ObservationIgnored var onCanvasChanged: ((PixelRect) -> Void)?
    @ObservationIgnored var onEditCommitted: ((String) -> Void)?
    /// Fires when the canvas changes *size*, so the window can follow it.
    ///
    /// The window is sized to the artwork at open and then never again, which
    /// was fine while the canvas was fixed — but pasting now grows it, and a
    /// document that silently becomes larger than its window is one you have to
    /// go and resize by hand before you can see what you just pasted.
    @ObservationIgnored var onCanvasResized: ((_ width: Int, _ height: Int) -> Void)?

    /// Seeded at init, **not** lazily on first use.
    ///
    /// Lazy seeding swallowed the first resize: the initial `noteChange` found
    /// no baseline, recorded the already-grown size and returned without
    /// announcing anything. Pasting an oversized image as the very first action
    /// in a document therefore grew the canvas and left the window alone — the
    /// exact case the hook exists for.
    @ObservationIgnored private var lastKnownCanvasSize: (width: Int, height: Int) = (0, 0)

    /// Notice a size change and tell whoever is listening. Called from the one
    /// place every pixel change already funnels through.
    private func noteCanvasSizeIfChanged() {
        let size = (width: canvas.width, height: canvas.height)
        guard lastKnownCanvasSize != size else { return }
        lastKnownCanvasSize = size
        onCanvasResized?(size.width, size.height)
    }

    /// Pulls engine-side changes (eyedropper, paste's tool switch) back to the UI.
    func syncFromEngine() {
        if engine.colours.foreground != foreground { foreground = engine.colours.foreground }
        if engine.colours.background != background { background = engine.colours.background }
        if engine.settings.tool != tool { tool = engine.settings.tool }
    }

    // MARK: - Commands

    /// Pick a tool, or toggle its options when it is already active.
    func selectTool(_ kind: ToolKind) {
        if tool == kind {
            isOptionsExpanded.toggle()
        } else {
            tool = kind
            isOptionsExpanded = true
        }
    }

    /// Pick a shape and arm the shape tool in one move — the shape grid in the
    /// options panel is also how you *reach* the shape tool.
    func selectShape(_ kind: ShapeKind) {
        shapeKind = kind
        tool = .shape
        isOptionsExpanded = true
    }

    /// Step the brush proportionally, so one press is a useful change at both
    /// 2px and 64px. A flat ±1 would take sixty presses to cross the range.
    /// Shared by `[`/`]` on the canvas and the Tools menu, so the two can never
    /// disagree about what a step is.
    func stepBrushSize(up: Bool) {
        let step = switch brushSize {
        case ..<8: 1
        case ..<24: 2
        case ..<48: 4
        default: 8
        }
        let allowed = ToolSettings.sizeRange(for: tool)
        brushSize = min(allowed.upperBound, max(allowed.lowerBound, brushSize + (up ? step : -step)))
    }

    /// Flip a text trait, arming the text tool with it.
    ///
    /// Pressing ⌘B while holding the brush means "I am about to write something
    /// bold", not nothing at all — the same reasoning that makes the shape
    /// gallery a way *into* the shape tool.
    func toggleTextTrait(_ trait: ReferenceWritableKeyPath<EditorModel, Bool>) {
        self[keyPath: trait].toggle()
        if tool != .text {
            tool = .text
            isOptionsExpanded = true
        }
    }

    func swapColours() {
        engine.colours.swap()
        foreground = engine.colours.foreground
        background = engine.colours.background
    }

    func applySwatch(_ colour: PaintColour, to role: ColourRole) {
        switch role {
        case .foreground: foreground = colour
        case .background: background = colour
        }
    }

    enum ColourRole { case foreground, background }

    func undo() { noteChange(engine.undo()); syncFromEngine() }
    func redo() { noteChange(engine.redo()) }

    /// True once the user has chosen a zoom themselves. Until then the view is
    /// free to shrink-to-fit as the window settles.
    @ObservationIgnored var hasUserZoomed = false

    func zoomIn() {
        hasUserZoomed = true
        guard let next = Self.zoomSteps.first(where: { $0 > zoom }) else { return }
        zoom = next
    }

    func zoomOut() {
        hasUserZoomed = true
        guard let previous = Self.zoomSteps.last(where: { $0 < zoom }) else { return }
        zoom = previous
    }

    /// Fit the whole canvas inside `viewport`.
    ///
    /// Uses the **exact** scale rather than snapping to the zoom ramp. The ramp
    /// is deliberately coarse (0.5 → 1) so stepping through it keeps pixels
    /// honest, but snapping a *fit* is wrong: a canvas that wants 98% drops to
    /// 50% and wastes half the window, which defeats a canvas-first layout
    /// where the artwork should own ~96% of it. At fit you are looking at the
    /// whole picture, not editing individual pixels.
    ///
    /// Never magnifies past 100% — "fit" on a small image should not blow it up.
    func zoomToFit(_ viewport: CGSize) {
        guard viewport.width > 16, viewport.height > 16 else { return }
        let margin: Double = 2
        let scale = min(
            (viewport.width - margin) / Double(canvas.width),
            (viewport.height - margin) / Double(canvas.height)
        )
        setZoomExact(min(scale, 1))
    }

    /// Set a zoom that bypasses the discrete ramp. Only fit uses this.
    func setZoomExact(_ value: Double) {
        storedZoom = max(0.02, min(32, value))
    }

    // MARK: - Selection and clipboard

    func selectAll() {
        engine.selectAll()
        tool = .select
        noteChange(canvas.bounds)
    }

    func deselect() { noteChange(engine.deselect()) }

    func deleteSelection() { noteChange(engine.deleteSelection()) }

    func makeSelectionTransparent() { noteChange(engine.makeSelectionTransparent()) }

    /// Copy the entire canvas, selection or not — the "send me that" case.
    func copyWholeImage() { writeToPasteboard(canvas) }

    /// The current image as something another app can accept from a drag.
    ///
    /// The selection when there is one, the whole canvas otherwise — the same
    /// rule Copy follows, so the drag handle and `⌘C` never disagree about what
    /// "this image" means.
    ///
    /// Encoded eagerly rather than in the `Transferable` closure. A drag has to
    /// hand the receiving app data the moment it is dropped, and doing the PNG
    /// encode there put it on the main thread mid-gesture; the canvas is already
    /// in memory, so paying for it up front costs a copy and removes the stall.
    func draggableImage() -> DraggedImage? {
        let bitmap = engine.selectedContent() ?? canvas
        guard let data = try? ImageCodec.encode(bitmap, as: .png) else { return nil }
        return DraggedImage(data: data, name: "\(documentName).png")
    }

    func copySelection() {
        guard let content = engine.selectedContent() else { return }
        writeToPasteboard(content)
    }

    func cutSelection() {
        guard let content = engine.selectedContent() else { return }
        writeToPasteboard(content)
        noteChange(engine.deleteSelection())
    }

    /// Whether the clipboard is holding something this app can paste.
    ///
    /// **Cached against the pasteboard's change count.** Asking the pasteboard
    /// directly is cross-process IPC, and a header button that reads it would ask
    /// on every SwiftUI render pass — including every frame of a drag. The change
    /// count is the cheap way to know whether the answer could possibly have
    /// moved, which it only does when someone copies something.
    private(set) var canPaste: Bool = false

    @ObservationIgnored private var seenPasteboardChange = -1

    /// Re-read the clipboard if it has changed since the last look.
    ///
    /// Called when the app or this window becomes active, which is exactly when
    /// the answer can have changed without us: the whole point of this app is
    /// that you copy a screenshot *somewhere else* and come back here to mark it
    /// up, so the interesting transition always happens while we are not frontmost.
    func refreshClipboardState() {
        let change = NSPasteboard.general.changeCount
        guard change != seenPasteboardChange else { return }
        seenPasteboardChange = change
        let available = Bitmap.canDecode(pasteboard: .general)
        if canPaste != available { canPaste = available }
    }

    /// Drop a saved signature onto the artwork as floating content.
    ///
    /// Floating on purpose: a signature is almost never right first time — it wants
    /// nudging into the space on the form and sizing to the line. Arriving with the
    /// selection handles already on it means positioning it is the same gesture as
    /// positioning a paste, and clicking away commits it.
    func insertSignature(_ bitmap: Bitmap) {
        noteChange(engine.stamp(bitmap))
        syncFromEngine()
    }

    func paste() {
        do {
            let bitmap = try readPasteboardBitmap()
            noteChange(engine.paste(bitmap))
            syncFromEngine()
        } catch {
            presentImageImportError(error)
        }
    }

    /// Place a dropped or pasted image centred on `point`, growing the canvas
    /// first if it would not otherwise fit.
    ///
    /// Dropping a 3× retina screenshot onto a small canvas and silently losing
    /// three quarters of it is the failure this avoids.
    func dropImage(_ bitmap: Bitmap, centredOn point: PixelPoint) {
        if bitmap.width > canvas.width || bitmap.height > canvas.height {
            let target = (
                width: max(canvas.width, bitmap.width),
                height: max(canvas.height, bitmap.height)
            )
            guard Bitmap.isSizeSupported(width: target.width, height: target.height) else {
                presentUnsupportedImageSize(width: target.width, height: target.height)
                return
            }
            engine.replaceCanvas(
                with: ImageTransform.resizedCanvas(
                    canvas,
                    to: target,
                    fill: background
                ),
                actionName: "Fit to dropped image"
            )
        }
        noteChange(engine.paste(bitmap))

        // Re-centre on the drop point, clamped so it cannot land entirely
        // off-canvas where the user could not reach it again.
        let origin = PixelPoint(
            x: min(max(0, point.x - bitmap.width / 2), max(0, canvas.width - bitmap.width)),
            y: min(max(0, point.y - bitmap.height / 2), max(0, canvas.height - bitmap.height))
        )
        noteChange(engine.moveFloating(to: origin))
        syncFromEngine()
    }

    func invertSelection() { noteChange(engine.invertSelection()) }

    /// True while something pasted or lifted is still floating, so the chrome
    /// can offer what to do with it.
    ///
    /// **Mirrored, not forwarded**, for the same reason `nextBadgeNumber` is: a
    /// computed passthrough to the UI-free engine is invisible to SwiftUI, so
    /// the actions bar only appeared and vanished when something *else*
    /// invalidated the view around it. Placing a float and then undoing past it
    /// changes nothing else, which is how the bar outlived the content it acts
    /// on — still offering Place and Crop with nothing to place, and a blank
    /// size chip because that read-out *does* follow `revision`.
    private(set) var hasFloatingContent = false

    /// Pull the flag across whenever anything has been drawn or invalidated —
    /// which is every route that can lift, drop, place, discard or undo a float.
    ///
    /// An empty frame reads as nothing floating. The engine does not make those,
    /// but the bar exists to place and crop *to* something, and both are
    /// meaningless on a rect of no size.
    private func syncFloatingState() {
        let floats = engine.floating.map { !$0.frame.isEmpty } ?? false
        if hasFloatingContent != floats { hasFloatingContent = floats }
    }

    /// Write the floating content down where it sits.
    func placeFloating() {
        noteChange(engine.commitFloating())
        syncFromEngine()
    }

    /// Throw the floating content away without marking the canvas.
    func discardFloating() {
        noteChange(engine.discardFloating())
        syncFromEngine()
    }

    // MARK: - State the canvas-first chrome reads

    /// Document name and dirty flag, mirrored so the title chip does not have
    /// to reach for the window.
    var documentName: String = "Untitled"
    var isEdited: Bool = false

    /// True while a gesture is in flight. The cluster dims so the marching ants
    /// are never competing with chrome.
    var isDragging: Bool { engine.isDrawing }

    /// Size of the live selection or floating content, for the actions row.
    var selectionSize: (width: Int, height: Int)? {
        if let floating { return (floating.frame.width, floating.frame.height) }
        if let region = engine.activeRegionSize { return region }
        if let bounds = selectionBounds { return (bounds.width, bounds.height) }
        return nil
    }

    /// Open the system colour picker for one of the pair.
    func presentSystemColourPicker(for role: ColourRole) {
        let initial = role == .foreground ? foreground : background
        ColourPanelController.shared.present(
            owner: "\(colourPanelOwner)-\(role)",
            initial: initial
        ) { [weak self] picked in
            self?.applySwatch(picked, to: role)
        }
    }

    /// Hook the document installs so File ▸ Duplicate works from the chrome.
    @ObservationIgnored var onDuplicate: (() -> Void)?

    func duplicateDocument() { onDuplicate?() }

    /// Live size of whatever region is being dragged, for the status bar.
    var activeRegionSize: (width: Int, height: Int)? { engine.activeRegionSize }

    private func writeToPasteboard(_ bitmap: Bitmap) {
        guard let data = try? ImageCodec.encode(bitmap, as: .png),
              let image = NSImage(data: data)
        else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    private func readPasteboardBitmap() throws -> Bitmap {
        try Bitmap(pasteboard: .general)
    }

    func presentImageImportError(_ error: any Error) {
        if let codecError = error as? ImageCodec.CodecError {
            present(
                message: codecError.localizedDescription,
                recovery: codecError.recoverySuggestion
            )
        } else {
            present(
                message: error.localizedDescription,
                recovery: "Copy an image from another app, then try again."
            )
        }
    }

    private func presentUnsupportedImageSize(width: Int, height: Int) {
        let error = ImageCodec.CodecError.imageTooLarge(width: width, height: height)
        present(message: error.localizedDescription, recovery: error.recoverySuggestion)
    }

    func cropToSelection() {
        // Captured *before* the attempt, because cropping commits any floating
        // content and so changes the answer. Reading it afterwards is how this
        // ended up reporting "select an area first" immediately after pasting —
        // the paste had just been consumed.
        let hadRegion = hasSelection

        if engine.cropToSelection() {
            noteChange(canvas.bounds)
            return
        }

        // The float was still placed even when there was nothing to crop to, so
        // the canvas may have changed regardless.
        noteChange(canvas.bounds)

        guard !hadRegion else {
            // Already the whole canvas — which is the *normal* outcome of
            // pasting an image larger than the document, since the canvas grew
            // to fit it. Nothing to do is not an error, and an alert here was
            // the app telling people off for a reasonable thing to try.
            return
        }

        present(
            message: "Select an area to crop to first.",
            recovery: "Press M and drag a rectangle, or L to trace a shape."
        )
    }

    /// Trim uniform borders. The common case is a screenshot with a slab of
    /// desktop around it, where hand-selecting the edge is fiddly.
    /// Trim uniform edges away.
    ///
    /// Tolerant by default: a screenshot's "solid" border is rarely one exact
    /// colour once it has been through a lossy format or picked up a shadow,
    /// and a zero-tolerance trim silently does nothing on exactly the images
    /// people most want to trim.
    func trimBorders() {
        guard engine.trimBorders() else {
            present(
                message: "There's nothing to trim.",
                recovery: "This image has no solid border around its edges."
            )
            return
        }
        noteChange(canvas.bounds)
    }

    /// Key the page out from behind the subject in one command.
    ///
    /// It declines rather than guessing when the whole picture is one region —
    /// and says so, because the alternative is a command that appears to do
    /// nothing. Instant Alpha is the answer when it declines and you still want
    /// the region gone, so the message names it.
    func removeBackground() {
        guard engine.removeBackground() else {
            present(
                message: "There's no background to remove.",
                recovery: "The edges of this image are all one region, so removing "
                    + "it would erase the picture. Use the Select tool's Instant "
                    + "Alpha mode to choose the area yourself."
            )
            return
        }
        noteChange(canvas.bounds)
        syncFromEngine()
    }

    // MARK: - Image menu

    func clearImage() { noteChange(engine.clearCanvas()) }
    func invertColours() { noteChange(engine.invertColours()) }

    func flipHorizontally() {
        replace(ImageTransform.flippedHorizontally(canvas), named: "Flip horizontal")
    }

    func flipVertically() {
        replace(ImageTransform.flippedVertically(canvas), named: "Flip vertical")
    }

    func rotate(_ rotation: ImageTransform.Rotation) {
        replace(ImageTransform.rotated(canvas, by: rotation), named: rotation.displayName)
    }

    /// Straighten by an arbitrary angle, filling the exposed corners with the
    /// back colour.
    ///
    /// The canvas grows to the rotated bounding box rather than cropping,
    /// because cropping the picture someone asked to straighten is the one
    /// outcome nobody wants.
    func rotate(degrees: Double) {
        guard degrees.truncatingRemainder(dividingBy: 360) != 0 else { return }
        guard let rotated = ImageTransform.rotated(canvas, degrees: degrees, fill: background) else {
            present(
                message: "Couldn't rotate the image.",
                recovery: "Rotating by that angle would make the canvas too large."
            )
            return
        }
        replace(rotated, named: "Rotate")
    }

    var isRotateSheetPresented: Bool = false
    var isSignatureSheetPresented: Bool = false

    func resizeCanvas(width: Int, height: Int) {
        guard Bitmap.isSizeSupported(width: width, height: height) else {
            presentUnsupportedImageSize(width: width, height: height)
            return
        }
        replace(
            ImageTransform.resizedCanvas(canvas, to: (width, height), fill: background),
            named: "Canvas size"
        )
    }

    func scaleImage(width: Int, height: Int, using scaling: ImageTransform.Scaling) {
        guard Bitmap.isSizeSupported(width: width, height: height) else {
            presentUnsupportedImageSize(width: width, height: height)
            return
        }
        guard let scaled = ImageTransform.scaled(canvas, to: (width, height), using: scaling) else {
            present(message: "Couldn't resize the image.", recovery: "Try a different size.")
            return
        }
        replace(scaled, named: "Resize image")
    }

    private func replace(_ bitmap: Bitmap, named name: String) {
        engine.replaceCanvas(with: bitmap, actionName: name)
        noteChange(engine.canvas.bounds)
    }

    func present(message: String, recovery: String?) {
        presentedError = PresentableError(message: message, recovery: recovery)
    }
}

extension Bitmap {
    /// The best image on a pasteboard — the clipboard's and a drag's are the
    /// same type, so paste and drop read them the same way.
    ///
    /// A referenced file wins, then raw PNG/TIFF data. Both routes go through
    /// ImageIO's dimension preflight before any pixel buffer is allocated.
    /// Avoiding the generic `NSImage` fallback is intentional: asking AppKit
    /// for a CGImage can decode an unbounded representation before PaintKit has
    /// a chance to inspect its dimensions.
    init(pasteboard board: NSPasteboard) throws {
        if let url = Self.imageURL(on: board) {
            self = try ImageCodec.decode(contentsOf: url)
            return
        }

        for (type, fileName) in [
            (NSPasteboard.PasteboardType.png, "Clipboard.png"),
            (.tiff, "Clipboard.tiff"),
        ] {
            guard let data = board.data(forType: type) else { continue }
            self = try ImageCodec.decode(
                data: data,
                sourceURL: URL(fileURLWithPath: "/\(fileName)")
            )
            return
        }

        throw PasteboardImageError.noImage
    }

    static func canDecode(pasteboard board: NSPasteboard) -> Bool {
        imageURL(on: board) != nil
            || board.availableType(from: [.png, .tiff]) != nil
    }

    private static func imageURL(on board: NSPasteboard) -> URL? {
        board.readObjects(
            forClasses: [NSURL.self],
            options: [
                .urlReadingContentsConformToTypes:
                    ImageCodec.readableContentTypes.map(\.identifier),
            ]
        )?.first as? URL
    }
}

private enum PasteboardImageError: LocalizedError {
    case noImage

    var errorDescription: String? { "There's no image on the clipboard." }
}
