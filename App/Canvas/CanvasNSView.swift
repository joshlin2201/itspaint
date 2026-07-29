import AppKit
import PaintKit

/// The drawing surface.
///
/// AppKit rather than a SwiftUI `Canvas`: this view needs precise mouse-down /
/// dragged / up sequencing, separate right-button tracking, modifier flags
/// mid-drag, pressure, and rect-scoped invalidation. SwiftUI's gesture system
/// abstracts exactly the details a paint tool depends on.
final class CanvasNSView: NSView {

    var model: EditorModel? {
        didSet {
            guard model !== oldValue else { return }
            paintedRevision = -1
            invalidateCanvasSize()
        }
    }

    /// Cached snapshot of the canvas. Rebuilt only when the pixels change, not
    /// on every scroll or window resize.
    private var cachedImage: CGImage?
    private var cachedRevision: Int = -1

    /// Floating content is cached separately: dragging a pasted image changes
    /// its position every frame but never its pixels, so re-encoding it on each
    /// mouse-moved event would be pure waste.
    private var cachedFloatingImage: CGImage?
    private var cachedFloatingBitmap: Bitmap?

    /// Instant Alpha can expose thousands of pixel edges. Cache its path so the
    /// marching-ant timer only changes the dash phase, not the geometry.
    private var cachedSelectionOutline: CGPath?
    private var cachedOutlineSelection: Selection?
    private var cachedOutlineZoom: Double = -1

    private var activeButton: PointerButton?
    private var isShiftHeld: Bool = false
    private var marchingAntsPhase: CGFloat = 0
    private var antsTimer: Timer?
    private var isSpaceHeld = false
    private var panOrigin: NSPoint?
    private var panScroll: NSPoint?

    // MARK: - Geometry

    /// Canvas row 0 is the top row, so the view matches image coordinates and
    /// nothing downstream has to flip.
    override var isFlipped: Bool { true }

    /// A soft drop shadow and a hairline, so the artwork reads as a sheet
    /// resting on the window rather than a rectangle butted against it.
    ///
    /// Drawn by the layer rather than inside `draw(_:)` because a view cannot
    /// paint outside its own bounds — and the whole point is the falloff
    /// *around* the canvas edge.
    private func installSheetShadow() {
        wantsLayer = true
        guard let layer else { return }
        layer.masksToBounds = false
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.55
        layer.shadowRadius = 22
        layer.shadowOffset = CGSize(width: 0, height: -6)
        layer.borderWidth = 0.5
        layer.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
    }

    override var acceptsFirstResponder: Bool { true }

    var zoom: Double = 1 {
        didSet {
            guard zoom != oldValue else { return }
            // The text box is positioned in screen points, so a zoom underneath
            // it would leave it pointing at the wrong pixels. Land it instead.
            commitText()
            invalidateCanvasSize()
        }
    }

    func invalidateCanvasSize() {
        guard let model else { return }
        let size = NSSize(
            width: Double(model.canvas.width) * zoom,
            height: Double(model.canvas.height) * zoom
        )
        guard frame.size != size else { return }
        setFrameSize(size)
        // Re-run the clip view's centring. Without this the scroll view
        // keeps the origin it computed when the document view was still
        // zero-sized, and the artwork sits off to one side.
        if let scrollView = enclosingScrollView {
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        needsDisplay = true
    }

    /// Repaint for a change that did not come through this view — a menu
    /// command, an undo, a document revert.
    ///
    /// SwiftUI re-runs the representable on *every* observed change, including
    /// the pointer moving, so an unconditional repaint here would undo the
    /// rect-scoped invalidation the rest of this file is built around and cost
    /// a full-canvas redraw per mouse-moved event. Edits made through this view
    /// have already invalidated their own dirty rect and recorded the revision.
    @discardableResult
    func repaintIfChanged(revision: Int) -> Bool {
        guard revision != paintedRevision else { return false }
        paintedRevision = revision
        needsDisplay = true
        return true
    }

    /// Revision this view has already scheduled a repaint for.
    private var paintedRevision = -1

    /// Convert a view point to canvas pixel coordinates.
    private func pixelPoint(from viewPoint: NSPoint) -> PixelPoint {
        PixelPoint(
            x: Int((viewPoint.x / zoom).rounded(.down)),
            y: Int((viewPoint.y / zoom).rounded(.down))
        )
    }

    private func pixelPoint(for event: NSEvent) -> PixelPoint {
        pixelPoint(from: convert(event.locationInWindow, from: nil))
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let model,
              let context = NSGraphicsContext.current?.cgContext
        else { return }

        if cachedRevision != model.revision || cachedImage == nil {
            cachedImage = model.canvas.makeCGImage()
            cachedRevision = model.revision
        }
        guard let image = cachedImage else { return }

        drawTransparencyGrid(in: dirtyRect, context: context)

        context.saveGState()
        // Nearest-neighbour when magnified. A paint app that blurs its own
        // pixels at 800% is lying to the user about what they drew.
        context.interpolationQuality = zoom >= 1 ? .none : .high
        context.setShouldAntialias(false)

        // The view is flipped; CGImage draws bottom-up, so flip back for the blit.
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: bounds.size))
        context.restoreGState()

        drawFloatingContent(context: context, model: model)

        if model.showsGrid && zoom >= 4 {
            drawPixelGrid(in: dirtyRect, context: context)
        }

        drawMarquee(context: context, model: model)
        // The text box while it is being dragged out; once the editor is up it
        // draws its own caret and the ants would only fight it.
        if let textBox, textEditor == nil {
            drawAnts(around: CGRect(
                x: Double(textBox.minX) * zoom, y: Double(textBox.minY) * zoom,
                width: Double(textBox.width) * zoom, height: Double(textBox.height) * zoom
            ), context: context)
        }
        drawBrushPreview(context: context, model: model)
        drawPixelCursor(context: context, model: model)
    }

    /// A quiet semantic checkerboard under alpha, clipped to the dirty rect.
    ///
    /// Transparency that renders as plain white is invisible feedback. Using
    /// system colours keeps the grid legible in both appearances without adding
    /// another accent to the canvas.
    private func drawTransparencyGrid(in dirtyRect: NSRect, context: CGContext) {
        let tile = Tokens.Size.transparencyTile
        context.saveGState()
        context.setFillColor(NSColor.controlBackgroundColor.cgColor)
        context.fill(dirtyRect)
        context.setFillColor(NSColor.separatorColor.withAlphaComponent(0.22).cgColor)

        let startColumn = Int(floor(dirtyRect.minX / tile))
        let endColumn = Int(ceil(dirtyRect.maxX / tile))
        let startRow = Int(floor(dirtyRect.minY / tile))
        let endRow = Int(ceil(dirtyRect.maxY / tile))
        for row in startRow..<endRow {
            for column in startColumn..<endColumn where (row + column).isMultiple(of: 2) {
                context.fill(CGRect(
                    x: CGFloat(column) * tile,
                    y: CGFloat(row) * tile,
                    width: tile,
                    height: tile
                ))
            }
        }
        context.restoreGState()
    }

    /// The exact footprint the next stroke will cover, followed under the
    /// pointer.
    ///
    /// This is the whole "raw pixel control" promise made visible: you can see
    /// which pixels you are about to change *before* you commit, at any zoom.
    /// Without it a 32px brush is a guess, and a 1px pencil at 800% is a guess
    /// about which cell the crosshair is really in.
    ///
    /// Drawn as a light casing under a dark ring for the same reason the
    /// marching ants are two-stroke: a single colour vanishes against whichever
    /// artwork it happens to cross.
    private func drawBrushPreview(context: CGContext, model: EditorModel) {
        guard !isSpaceHeld, panOrigin == nil,
              let point = model.pointerPosition,
              model.tool.showsBrushPreview
        else { return }

        // The nib, not the brush: this runs on every mouse-moved event and the
        // ring needs the footprint's outline, not its coverage mask.
        let nib = model.engine.settings.nib
        let extent = Brush.extent(size: nib.size)
        let rect = CGRect(
            x: Double(point.x + extent.minX) * zoom,
            y: Double(point.y + extent.minY) * zoom,
            width: Double(extent.width) * zoom,
            height: Double(extent.height) * zoom
        )
        // Below a couple of points on screen the ring is noise, not information;
        // the crosshair alone is more precise.
        guard rect.width >= 3 else { return }

        context.saveGState()
        context.setShouldAntialias(nib.shape != .square)

        let path: CGPath = nib.shape == .square
            ? CGPath(rect: rect.insetBy(dx: 0.5, dy: 0.5), transform: nil)
            : CGPath(ellipseIn: rect.insetBy(dx: 0.5, dy: 0.5), transform: nil)

        context.addPath(path)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        context.setLineWidth(2.5)
        context.strokePath()

        context.addPath(path)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.85).cgColor)
        context.setLineWidth(1)
        context.strokePath()
        context.restoreGState()
    }

    /// The single pixel under the pointer, once zoomed far enough that a pixel
    /// is a visible cell. Pixel art lives or dies on knowing exactly which cell
    /// you are on.
    private func drawPixelCursor(context: CGContext, model: EditorModel) {
        guard zoom >= 4, let point = model.pointerPosition else { return }
        let rect = CGRect(
            x: Double(point.x) * zoom, y: Double(point.y) * zoom,
            width: zoom, height: zoom
        ).insetBy(dx: 0.5, dy: 0.5)

        context.saveGState()
        context.setShouldAntialias(false)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.95).cgColor)
        context.setLineWidth(2)
        context.stroke(rect)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.9).cgColor)
        context.setLineWidth(1)
        context.stroke(rect)
        context.restoreGState()
    }

    /// Floating content is composited at draw time rather than written into the
    /// canvas. That is what makes moving a pasted image free and cancelling it
    /// leave no trace.
    private func drawFloatingContent(context: CGContext, model: EditorModel) {
        guard let floating = model.floating else {
            cachedFloatingImage = nil
            cachedFloatingBitmap = nil
            return
        }

        if cachedFloatingBitmap != floating.bitmap {
            cachedFloatingImage = floating.bitmap.makeCGImage()
            cachedFloatingBitmap = floating.bitmap
        }
        guard let image = cachedFloatingImage else { return }

        let frame = CGRect(
            x: Double(floating.origin.x) * zoom,
            y: Double(floating.origin.y) * zoom,
            width: Double(floating.bitmap.width) * zoom,
            height: Double(floating.bitmap.height) * zoom
        )

        context.saveGState()
        context.interpolationQuality = zoom >= 1 ? .none : .high
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        let flipped = CGRect(
            x: frame.minX, y: bounds.height - frame.maxY,
            width: frame.width, height: frame.height
        )
        context.draw(image, in: flipped)
        context.restoreGState()

        drawAnts(around: frame, context: context)
        drawHandles(around: frame, context: context, selection: floating)
    }

    /// Resize handles: white squares with a dark outline, drawn at a constant
    /// **screen** size so they stay grabbable at any zoom.
    private func drawHandles(
        around frame: CGRect, context: CGContext, selection: FloatingSelection
    ) {
        // Below this the handles would cover the content they resize; the
        // engine's hit-testing caps its tolerance the same way.
        guard frame.width > Self.handleScreenSize * 3,
              frame.height > Self.handleScreenSize * 3 else { return }

        context.saveGState()
        context.setShouldAntialias(true)
        let size = Self.handleScreenSize

        for (_, centre) in selection.handleCentres() {
            let rect = CGRect(
                x: Double(centre.x) * zoom - size / 2,
                y: Double(centre.y) * zoom - size / 2,
                width: size, height: size
            )
            let path = CGPath(
                roundedRect: rect, cornerWidth: 2, cornerHeight: 2, transform: nil
            )
            context.addPath(path)
            context.setFillColor(NSColor.white.cgColor)
            context.fillPath()
            context.addPath(path)
            context.setStrokeColor(NSColor.black.withAlphaComponent(0.65).cgColor)
            context.setLineWidth(1)
            context.strokePath()
        }
        context.restoreGState()
    }

    private static let handleScreenSize: CGFloat = 8

    private func drawMarquee(context: CGContext, model: EditorModel) {
        guard model.floating == nil, let selection = model.selection, !selection.isEmpty else { return }

        // A lasso's ants follow the outline the user actually traced. Drawing
        // its bounding box would tell them the selection is a rectangle, which
        // is exactly the lie the freeform tool exists to avoid.
        if !selection.isRectangular, model.lassoPath.count > 2 {
            let path = CGMutablePath()
            let points = model.lassoPath
            path.move(to: CGPoint(x: Double(points[0].x) * zoom, y: Double(points[0].y) * zoom))
            for point in points.dropFirst() {
                path.addLine(to: CGPoint(x: Double(point.x) * zoom, y: Double(point.y) * zoom))
            }
            path.closeSubpath()
            drawAnts(along: path, context: context)
            return
        }
        if !selection.isRectangular, let path = maskedOutline(for: selection) {
            drawAnts(along: path, context: context)
            return
        }

        let bounds = selection.bounds
        drawAnts(
            around: CGRect(
                x: Double(bounds.minX) * zoom,
                y: Double(bounds.minY) * zoom,
                width: Double(bounds.width) * zoom,
                height: Double(bounds.height) * zoom
            ),
            context: context
        )
    }

    /// Every exposed edge of a masked selection, in view coordinates.
    ///
    /// A bounding box would lie about what Instant Alpha selected. Horizontal
    /// and vertical runs are joined before drawing, which keeps the path compact
    /// on large flat backgrounds while still tracing holes and isolated detail.
    private func maskedOutline(for selection: Selection) -> CGPath? {
        guard selection.mask != nil else { return nil }
        if cachedOutlineSelection == selection, cachedOutlineZoom == zoom {
            return cachedSelectionOutline
        }

        let path = CGMutablePath()
        let bounds = selection.bounds

        @inline(__always)
        func selected(_ x: Int, _ y: Int) -> Bool {
            selection.coverage(at: PixelPoint(x: x, y: y)) > 0
        }

        func appendHorizontalRuns(y: Int, selectedSide: Int) {
            var runStart: Int?
            for x in bounds.minX...bounds.maxX {
                let hasEdge = x < bounds.maxX
                    && selected(x, y + selectedSide)
                    && !selected(x, y + selectedSide - (selectedSide == 0 ? 1 : -1))
                if hasEdge, runStart == nil { runStart = x }
                if !hasEdge, let start = runStart {
                    path.move(to: CGPoint(x: Double(start) * zoom, y: Double(y) * zoom))
                    path.addLine(to: CGPoint(x: Double(x) * zoom, y: Double(y) * zoom))
                    runStart = nil
                }
            }
        }

        func appendVerticalRuns(x: Int, selectedSide: Int) {
            var runStart: Int?
            for y in bounds.minY...bounds.maxY {
                let hasEdge = y < bounds.maxY
                    && selected(x + selectedSide, y)
                    && !selected(x + selectedSide - (selectedSide == 0 ? 1 : -1), y)
                if hasEdge, runStart == nil { runStart = y }
                if !hasEdge, let start = runStart {
                    path.move(to: CGPoint(x: Double(x) * zoom, y: Double(start) * zoom))
                    path.addLine(to: CGPoint(x: Double(x) * zoom, y: Double(y) * zoom))
                    runStart = nil
                }
            }
        }

        // Top and bottom edges of selected pixels.
        for y in bounds.minY...bounds.maxY {
            appendHorizontalRuns(y: y, selectedSide: 0)
            appendHorizontalRuns(y: y, selectedSide: -1)
        }
        // Left and right edges of selected pixels.
        for x in bounds.minX...bounds.maxX {
            appendVerticalRuns(x: x, selectedSide: 0)
            appendVerticalRuns(x: x, selectedSide: -1)
        }

        cachedOutlineSelection = selection
        cachedOutlineZoom = zoom
        cachedSelectionOutline = path
        return path
    }

    /// Marching ants: a white base line under a dashed black line.
    ///
    /// Two passes rather than one, because a single-colour marquee disappears
    /// against whichever tone it happens to cross — and a selection you cannot
    /// see is a selection you will accidentally act on.
    private func drawAnts(around rect: CGRect, context: CGContext) {
        drawAnts(
            along: CGPath(rect: rect.insetBy(dx: -0.5, dy: -0.5), transform: nil),
            context: context,
            antialiased: false
        )
    }

    /// Ants along an arbitrary path, so rectangular and freeform selections
    /// share one treatment instead of drifting apart.
    private func drawAnts(along path: CGPath, context: CGContext, antialiased: Bool = true) {
        context.saveGState()
        context.setShouldAntialias(antialiased)

        context.addPath(path)
        context.setLineWidth(1.6)
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineDash(phase: 0, lengths: [])
        context.strokePath()

        context.addPath(path)
        context.setLineWidth(1)
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineDash(phase: marchingAntsPhase, lengths: [4, 4])
        context.strokePath()
        context.restoreGState()
    }

    /// Animate the ants only while there is something to animate.
    ///
    /// Advances by a fraction of a dash on each tick at display cadence rather
    /// than a whole dash a few times a second. A coarse step reads as a strobe;
    /// this reads as motion. The timer is also scoped to the selection's own
    /// rect, so an idle canvas is never repainted for a marquee in one corner.
    private func updateAntsAnimation() {
        let needsAnts = model?.selection != nil || model?.floating != nil
        if needsAnts, antsTimer == nil {
            let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let model = self.model else { return }
                    self.marchingAntsPhase =
                        (self.marchingAntsPhase + 0.8).truncatingRemainder(dividingBy: 8)

                    let region = model.floating?.frame ?? model.selectionBounds
                    guard let region else { return }
                    let padded = region.insetBy(-Int(Self.handleScreenSize))
                    self.setNeedsDisplay(
                        NSRect(
                            x: Double(padded.minX) * self.zoom,
                            y: Double(padded.minY) * self.zoom,
                            width: Double(padded.width) * self.zoom,
                            height: Double(padded.height) * self.zoom
                        )
                    )
                }
            }
            // Common mode keeps the ants moving during a scroll or a resize,
            // where a default-mode timer would freeze.
            RunLoop.main.add(timer, forMode: .common)
            antsTimer = timer
        } else if !needsAnts, antsTimer != nil {
            antsTimer?.invalidate()
            antsTimer = nil
        }
    }

    // MARK: - Drag and drop

    /// Accept images dropped from Finder, a browser, or any app that offers a
    /// bitmap. Dropping an image is the fastest possible way into the app's
    /// main job, so it lands as movable floating content rather than being
    /// flattened straight into the canvas.
    private static let droppedTypes: [NSPasteboard.PasteboardType] = [
        .fileURL, .png, .tiff,
    ]

    func enableDropping() {
        registerForDraggedTypes(Self.droppedTypes)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        canAccept(sender) ? .copy : []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        canAccept(sender) ? .copy : []
    }

    private func canAccept(_ sender: any NSDraggingInfo) -> Bool {
        Bitmap.canDecode(pasteboard: sender.draggingPasteboard)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let model else { return false }
        let bitmap: Bitmap
        do {
            bitmap = try Bitmap(pasteboard: sender.draggingPasteboard)
        } catch {
            model.presentImageImportError(error)
            return false
        }

        // Drop where the pointer is, centred on it, so the image lands where
        // the user aimed rather than in the middle of the canvas.
        let drop = pixelPoint(from: convert(sender.draggingLocation, from: nil))
        model.dropImage(bitmap, centredOn: drop)
        window?.makeFirstResponder(self)
        needsDisplay = true
        return true
    }

    /// Stop the ants when the view leaves the window.
    ///
    /// The teardown lives here rather than in `deinit` because a nonisolated
    /// `deinit` cannot touch a main-actor, non-Sendable `Timer` under Swift 6 —
    /// and a repeating timer holding the view would keep it alive anyway, so
    /// the deinit would never run to release it.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            antsTimer?.invalidate()
            antsTimer = nil
        } else {
            installSheetShadow()
            updateAntsAnimation()
        }
    }

    /// A hairline grid, only once a pixel is comfortably larger than the line.
    private func drawPixelGrid(in dirtyRect: NSRect, context: CGContext) {
        guard let model else { return }
        context.saveGState()
        context.setShouldAntialias(false)
        context.setLineWidth(1 / (window?.backingScaleFactor ?? 2))
        context.setStrokeColor(NSColor.separatorColor.cgColor)

        let firstColumn = max(0, Int(dirtyRect.minX / zoom))
        let lastColumn = min(model.canvas.width, Int(dirtyRect.maxX / zoom) + 1)
        let firstRow = max(0, Int(dirtyRect.minY / zoom))
        let lastRow = min(model.canvas.height, Int(dirtyRect.maxY / zoom) + 1)

        context.beginPath()
        for column in firstColumn...max(firstColumn, lastColumn) {
            let x = Double(column) * zoom
            context.move(to: CGPoint(x: x, y: dirtyRect.minY))
            context.addLine(to: CGPoint(x: x, y: dirtyRect.maxY))
        }
        for row in firstRow...max(firstRow, lastRow) {
            let y = Double(row) * zoom
            context.move(to: CGPoint(x: dirtyRect.minX, y: y))
            context.addLine(to: CGPoint(x: dirtyRect.maxX, y: y))
        }
        context.strokePath()
        context.restoreGState()
    }

    /// Invalidate only the region that changed, expanded by one pixel so an
    /// antialiased edge is never left half-drawn.
    private func invalidate(_ rect: PixelRect) {
        guard !rect.isEmpty else { return }
        let padded = rect.insetBy(-1)
        setNeedsDisplay(
            NSRect(
                x: Double(padded.minX) * zoom,
                y: Double(padded.minY) * zoom,
                width: Double(padded.width) * zoom,
                height: Double(padded.height) * zoom
            )
        )
    }

    // MARK: - Pointer

    override func mouseDown(with event: NSEvent) { begin(event, button: .primary) }
    override func mouseDragged(with event: NSEvent) { extend(event) }
    override func mouseUp(with event: NSEvent) { finish(event) }

    // The right button does two jobs, told apart by whether it moves.
    //
    // A drag paints the background colour — the two-button binding this app is
    // built on. A click with no drag opens the context menu, which is what
    // every other Mac app does and what people reach for to copy or crop. The
    // stroke starts from the original press point, so nothing is lost by
    // waiting to see which one it was.
    override func rightMouseDown(with event: NSEvent) {
        rightPress = convert(event.locationInWindow, from: nil)
        isRightDragging = false
    }

    override func rightMouseDragged(with event: NSEvent) {
        guard let press = rightPress else { return extend(event) }
        if !isRightDragging {
            let here = convert(event.locationInWindow, from: nil)
            guard hypot(here.x - press.x, here.y - press.y) > 2 else { return }
            isRightDragging = true
            begin(at: press, button: .secondary, modifiers: event.modifierFlags)
        }
        extend(event)
    }

    override func rightMouseUp(with event: NSEvent) {
        defer { rightPress = nil }
        guard isRightDragging else {
            guard let menu = contextMenu(for: event) else { return }
            NSMenu.popUpContextMenu(menu, with: event, for: self)
            return
        }
        isRightDragging = false
        finish(event)
    }

    private var rightPress: NSPoint?
    private var isRightDragging = false

    /// The canvas's own menu, for a right-click that did not drag.
    ///
    /// Returns it rather than popping it so the click-versus-drag rule can be
    /// tested without a window server: a menu here means "this gesture was a
    /// click", and `nil` means "this was a stroke".
    func contextMenu(for event: NSEvent) -> NSMenu? {
        guard let model, !isRightDragging else { return nil }
        window?.makeFirstResponder(self)
        model.pointerPosition = pixelPoint(for: event)
        return MainMenuBuilder.canvasMenu()
    }

    /// Control-click, and the trackpad's two-finger tap when it is configured
    /// to send one: both arrive here rather than as a right-click.
    override func menu(for event: NSEvent) -> NSMenu? {
        event.modifierFlags.contains(.control) ? MainMenuBuilder.canvasMenu() : nil
    }

    private func begin(_ event: NSEvent, button: PointerButton) {
        begin(at: convert(event.locationInWindow, from: nil), button: button, modifiers: event.modifierFlags)
    }

    private func begin(at viewPoint: NSPoint, button: PointerButton, modifiers: NSEvent.ModifierFlags) {
        guard let model else { return }
        // Touching the canvas puts the options panel away.
        model.isOptionsExpanded = false
        // A click anywhere lands an open text box before doing anything else.
        commitText()
        window?.makeFirstResponder(self)

        if isSpaceHeld {
            beginPan(at: viewPoint)
            return
        }

        let point = pixelPoint(from: viewPoint)

        // Hold Option to sample a colour with any tool, the way every serious
        // paint app does — reaching for the eyedropper and back is three
        // actions for one decision.
        let usesInstantAlphaModifiers = model.tool == .select
            && model.selectionKind == .instantAlpha
        if modifiers.contains(.option), !model.tool.isReadOnly, !usesInstantAlphaModifiers {
            if let pixel = model.canvas.pixel(at: point) {
                model.applySwatch(PaintColour(pixel), to: button == .primary ? .foreground : .background)
            }
            return
        }

        // Left button only: right-drag means "paint the background colour",
        // and a text box on the right button would be a second, secret binding.
        if model.tool == .text, button == .primary {
            textOrigin = point
            textBox = nil
            return
        }
        activeButton = button
        isShiftHeld = modifiers.contains(.shift)
        model.pointerPosition = point
        // Keep the engine's handle radius in step with the current zoom.
        model.engine.handleTolerance = canvasHandleTolerance
        let selectionOperation: PaintEngine.SelectionOperation = if usesInstantAlphaModifiers {
            if modifiers.contains(.shift) {
                .add
            } else if modifiers.contains(.option) {
                .subtract
            } else {
                .replace
            }
        } else {
            .replace
        }
        let dirty = model.engine.beginStroke(
            at: point,
            button: button,
            selectionOperation: selectionOperation
        )
        if usesInstantAlphaModifiers {
            commitVisualChange(dirty)
        } else {
            commit(dirty)
        }
        // A double-click closes a polygon where it stands, which is the other
        // half of the gesture people already know from every vector tool.
        if NSApp.currentEvent?.clickCount ?? 1 > 1, model.tool == .shape, model.shapeKind == .polygon {
            commit(model.engine.closePolygon())
        }
        startSprayingIfNeeded(at: point, button: button)
    }

    // MARK: - Airbrush

    /// The airbrush keeps working while the button is held still.
    ///
    /// Coverage that only builds when the pointer *moves* is a brush with a
    /// noisy edge; the whole feel of an airbrush is that lingering darkens.
    private var sprayTimer: Timer?

    private func startSprayingIfNeeded(at point: PixelPoint, button: PointerButton) {
        guard let model, model.tool.isSpray else { return }
        sprayTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let model = self.model, let point = model.pointerPosition else { return }
                self.commit(model.engine.continueStroke(to: point))
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        sprayTimer = timer
    }

    private func stopSpraying() {
        sprayTimer?.invalidate()
        sprayTimer = nil
    }

    private func extend(_ event: NSEvent) {
        if panOrigin != nil {
            continuePan(to: convert(event.locationInWindow, from: nil))
            return
        }
        if let origin = textOrigin {
            let previous = textBox
            textBox = PixelRect(corners: origin, pixelPoint(for: event))
            if let previous { invalidate(previous.insetBy(-2)) }
            if let textBox { invalidate(textBox.insetBy(-2)) }
            return
        }
        guard let model, activeButton != nil else { return }
        isShiftHeld = event.modifierFlags.contains(.shift)

        let point = pixelPoint(for: event)
        model.pointerPosition = point
        commit(model.engine.continueStroke(to: point, constrained: isShiftHeld))
    }

    private func finish(_ event: NSEvent) {
        stopSpraying()
        if panOrigin != nil { return endPan() }
        if let origin = textOrigin {
            textOrigin = nil
            openTextEditor(in: textBox ?? PixelRect(corners: origin, origin))
            return
        }
        guard let model, activeButton != nil else { return }
        let point = pixelPoint(for: event)
        let dirty = model.engine.endStroke(at: point, constrained: isShiftHeld)
        activeButton = nil
        commit(dirty)
        model.syncFromEngine()
        updateAntsAnimation()
        needsDisplay = true
    }

    private func commit(_ dirty: PixelRect) {
        updateAntsAnimation()
        guard !dirty.isEmpty else { return }
        model?.noteChange(dirty)
        invalidate(dirty)
        // This view has painted the change; claim the revision so the SwiftUI
        // update it triggers does not repaint the whole canvas on top of it.
        paintedRevision = model?.revision ?? paintedRevision
    }

    private func commitVisualChange(_ dirty: PixelRect) {
        updateAntsAnimation()
        guard !dirty.isEmpty else { return }
        model?.noteVisualChange(dirty)
        invalidate(dirty)
        paintedRevision = model?.revision ?? paintedRevision
    }

    // MARK: - Text

    /// Anchor of the box being dragged out, the box itself, and the live editor.
    private var textOrigin: PixelPoint?
    private var textBox: PixelRect?
    private var textEditor: TextEntryView?

    /// Put a real editor in the box so what you type is what lands — same font,
    /// same size, same colour, positioned on the same pixels. Typing into a
    /// panel and hoping is how the classic tool got text wrong.
    private func openTextEditor(in box: PixelRect) {
        guard let model else { return }
        let style = model.engine.settings.textStyle

        // A click rather than a drag still gets a usable box: one line tall,
        // running to the right edge, which is what every paint app does.
        //
        // Pulled back inside the canvas if the click was near an edge — a box
        // shorter than the line it holds renders nothing at all, so clicking
        // near the bottom would look like the tool was broken.
        var rect = box
        if rect.width < 8 || rect.height < 8 {
            let lineHeight = max(1, Int((style.pointSize * 1.4).rounded()))
            let minWidth = min(model.canvas.width, Int((style.pointSize * 4).rounded()))
            let x = min(box.minX, max(0, model.canvas.width - minWidth))
            let y = min(box.minY, max(0, model.canvas.height - lineHeight))
            rect = PixelRect(x: x, y: y, width: model.canvas.width - x, height: lineHeight)
        }
        rect = rect.intersection(model.canvas.bounds)
        guard rect.width > 1, rect.height > 1 else { textBox = nil; return }
        textBox = rect

        let editor = TextEntryView(frame: NSRect(
            x: Double(rect.minX) * zoom, y: Double(rect.minY) * zoom,
            width: Double(rect.width) * zoom, height: Double(rect.height) * zoom
        ))
        let pointSize = style.pointSize * zoom
        editor.font = NSFont(name: style.fontName, size: pointSize)
            ?? .systemFont(ofSize: pointSize)
        editor.textColor = NSColor(cgColor: model.foreground.cgColor) ?? .textColor
        editor.alignment = switch style.alignment {
        case .left: .left
        case .centre: .center
        case .right: .right
        }
        editor.drawsBackground = false
        editor.isRichText = false
        editor.isVerticallyResizable = false
        editor.textContainerInset = .zero
        editor.textContainer?.lineFragmentPadding = 0
        editor.delegate = self
        editor.onCancel = { [weak self] in self?.cancelText() }
        editor.onCommit = { [weak self] in self?.commitText() }
        editor.onMove = { [weak self] delta in self?.moveTextBox(by: delta) }

        addSubview(editor)
        textEditor = editor
        window?.makeFirstResponder(editor)
        invalidate(rect.insetBy(-2))
    }

    /// Rasterise the open box. Called on ⌘↩, on a click elsewhere, on a tool or
    /// zoom change, and whenever the editor loses focus — text that vanished
    /// because you clicked the wrong thing would be the worst kind of loss.
    func commitText() {
        guard let editor = textEditor, let model, let box = textBox else { return }
        textEditor = nil
        textBox = nil
        let string = editor.string
        editor.removeFromSuperview()
        if window?.firstResponder === editor { window?.makeFirstResponder(self) }

        var style = model.engine.settings.textStyle
        style.colour = model.foreground
        commit(model.engine.drawText(string, in: box, style: style))
        invalidate(box.insetBy(-2))
    }

    /// Drag the box around while it is still being typed into.
    ///
    /// Text you have to delete and retype because it landed four pixels left is
    /// the reason every other markup tool lets you move it.
    private func moveTextBox(by delta: NSPoint) {
        guard let editor = textEditor, let box = textBox, let model else { return }
        let moved = PixelRect(
            x: box.minX + Int((delta.x / zoom).rounded()),
            y: box.minY + Int((delta.y / zoom).rounded()),
            width: box.width, height: box.height
        )
        // Kept reachable: a box dragged entirely off-canvas could never be
        // typed into again.
        guard moved.intersection(model.canvas.bounds).width > 4 else { return }
        textBox = moved
        editor.frame.origin = NSPoint(x: Double(moved.minX) * zoom, y: Double(moved.minY) * zoom)
    }

    /// Escape: throw the box away without marking the canvas.
    private func cancelText() {
        guard let editor = textEditor else { return }
        let box = textBox
        textEditor = nil
        textBox = nil
        editor.removeFromSuperview()
        window?.makeFirstResponder(self)
        if let box { invalidate(box.insetBy(-2)) }
    }

    /// Switching tools lands an open box rather than dropping it.
    func commitText(unless tool: ToolKind) {
        if tool != .text { commitText() }
    }

    // MARK: - Hover read-out

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self
            )
        )
    }

    override func mouseMoved(with event: NSEvent) {
        guard let model else { return }
        let previous = model.pointerPosition
        let point = pixelPoint(for: event)
        model.pointerPosition = point

        // A polygon in progress rubber-bands to the pointer between clicks.
        if model.engine.hasPendingShape, model.tool == .shape, model.shapeKind == .polygon {
            commit(model.engine.previewPolygon(to: point))
        }

        // Repaint the old and new footprint rects only — following the pointer
        // must not cost a full-canvas redraw on every mouse-moved event.
        if model.tool.showsBrushPreview || zoom >= 4 {
            let radius = max(model.engine.settings.nib.size, Int(4 / max(zoom, 0.01))) + 2
            for spot in [previous, point].compactMap({ $0 }) {
                invalidate(PixelRect(
                    x: spot.x - radius, y: spot.y - radius,
                    width: radius * 2 + 1, height: radius * 2 + 1
                ))
            }
        }

        // Refresh the cursor only when the pointer crosses into or out of the
        // floating content's handles, not on every mouse-moved event.
        if let floating = model.floating {
            let wasOver = previous.map { floating.contains($0) || floating.handle(at: $0, tolerance: canvasHandleTolerance) != nil } ?? false
            let isOver = floating.contains(point) || floating.handle(at: point, tolerance: canvasHandleTolerance) != nil
            if wasOver != isOver || isOver {
                window?.invalidateCursorRects(for: self)
            }
        }
    }

    override func mouseExited(with event: NSEvent) {
        model?.pointerPosition = nil
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        guard let model else { return super.keyDown(with: event) }

        if event.keyCode == 49 {  // Space
            isSpaceHeld = true
            NSCursor.openHand.set()
            return
        }

        switch event.keyCode {
        case 53:  // Escape — the one key that gets you out of anything.
            cancelText()
            if let box = textBox { textOrigin = nil; textBox = nil; invalidate(box.insetBy(-2)) }
            stopSpraying()
            var dirty = model.engine.cancelStroke()
            dirty = dirty.union(model.engine.discardFloating())
            dirty = dirty.union(model.engine.deselect())
            activeButton = nil
            model.isOptionsExpanded = false
            commit(dirty)
            needsDisplay = true
            return

        case 36, 76:  // Return / Enter — finish whatever is in flight.
            commit(model.engine.closePolygon())
            commit(model.engine.commitPendingShape())
            commit(model.engine.commitFloating())
            needsDisplay = true
            return

        case 51, 117:  // Delete / Forward delete
            if model.hasSelection {
                model.deleteSelection()
                needsDisplay = true
                return
            }

        default:
            break
        }

        guard let characters = event.charactersIgnoringModifiers?.lowercased(),
              let key = characters.first,
              !event.modifierFlags.contains(.command)
        else { return super.keyDown(with: event) }

        // Shape kind: ⌥1–5, matching the order in the options pill.
        if event.modifierFlags.contains(.option),
           let digit = Int(String(key)), (1...ShapeKind.allCases.count).contains(digit) {
            model.shapeKind = ShapeKind.allCases[digit - 1]
            model.selectTool(.shape)
            return
        }

        switch key {
        case "x":
            // Older than every paint app we are competing with.
            model.swapColours()
            return
        case "[":
            model.stepBrushSize(up: false)
            return
        case "]":
            model.stepBrushSize(up: true)
            return
        default:
            break
        }

        if let match = ToolKind.allCases.first(where: { $0.shortcut == key }) {
            model.selectTool(match)
            needsDisplay = true
            return
        }
        // Nudge floating content with the arrow keys — pixel-exact placement is
        // impossible with a mouse and essential for annotation.
        let nudge: (dx: Int, dy: Int)?
        switch event.keyCode {
        case 123: nudge = (-1, 0)
        case 124: nudge = (1, 0)
        case 125: nudge = (0, 1)
        case 126: nudge = (0, -1)
        default: nudge = nil
        }
        if let nudge, model.floating != nil {
            commit(model.engine.nudgeFloating(by: nudge))
            needsDisplay = true
            return
        }
        super.keyDown(with: event)
    }

    // MARK: - Zoom

    /// Pinch to zoom, anchored where the fingers are.
    ///
    /// The scroll view forwards these too: AppKit delivers a magnify to
    /// whichever view is under the pointer, and with overlay scrollers and a
    /// centring clip view that is not reliably this one.
    override func magnify(with event: NSEvent) {
        guard let model else { return }
        zoom(by: 1 + event.magnification, at: convert(event.locationInWindow, from: nil), model: model)
    }

    /// ⌘-scroll, the other zoom gesture every Mac app supports.
    override func scrollWheel(with event: NSEvent) {
        guard let model, event.modifierFlags.contains(.command) else {
            return super.scrollWheel(with: event)
        }
        // Trackpad deltas are fine-grained; a wheel's are coarse. Scaling by a
        // small factor makes both feel like the same gesture.
        let step = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.006 : event.scrollingDeltaY * 0.04
        zoom(by: 1 + step, at: convert(event.locationInWindow, from: nil), model: model)
    }

    /// Scale continuously, keeping the canvas pixel under the pointer under the
    /// pointer.
    ///
    /// Continuous rather than snapped: the discrete ramp is right for ⌘+ and ⌘−,
    /// where every step should be an honest power of two, and wrong for a
    /// gesture, where jumping 100% → 200% mid-pinch feels broken.
    private func zoom(by factor: Double, at viewPoint: NSPoint, model: EditorModel) {
        let before = zoom
        guard factor.isFinite, factor > 0 else { return }

        // Both anchors are measured *before* the zoom changes: which canvas
        // pixel is under the pointer, and where the pointer sits in the clip
        // view. Measuring either afterwards mixes two different geometries and
        // throws the canvas into a corner.
        let anchor = pixelPoint(from: viewPoint)
        let clip = enclosingScrollView?.contentView
        let pointerInClip = clip.map { $0.convert(viewPoint, from: self) }

        model.hasUserZoomed = true
        model.setZoomExact(before * factor)
        guard model.zoom != before else { return }
        zoom = model.zoom
        invalidateCanvasSize()

        guard let clip, let pointerInClip else { return }
        // Only chase the anchor on axes where the artwork is actually bigger
        // than the viewport. On the others the clip view centres the canvas,
        // and forcing an origin there is what pinned it to the corner.
        var origin = clip.bounds.origin
        if frame.width > clip.bounds.width {
            origin.x = Double(anchor.x) * zoom - pointerInClip.x
        }
        if frame.height > clip.bounds.height {
            origin.y = Double(anchor.y) * zoom - pointerInClip.y
        }
        clip.scroll(to: origin)
        enclosingScrollView?.reflectScrolledClipView(clip)
    }

    /// Pinch and ⌘-scroll both land here, wherever AppKit delivered them.
    func zoomFromGesture(by factor: Double, atWindowPoint point: NSPoint) {
        guard let model else { return }
        zoom(by: factor, at: convert(point, from: nil), model: model)
    }

    // MARK: - Space to pan

    /// Hold Space to drag the canvas with any tool.
    ///
    /// The alternative — a dedicated hand tool — costs a permanent cell in a
    /// cluster whose whole premise is that it stays small, and forces a mode
    /// switch in the middle of a stroke.
    private func beginPan(at point: NSPoint) {
        panOrigin = point
        panScroll = enclosingScrollView?.contentView.bounds.origin
        NSCursor.closedHand.push()
    }

    private func endPan() {
        guard panOrigin != nil else { return }
        panOrigin = nil
        panScroll = nil
        NSCursor.pop()
    }

    private func continuePan(to point: NSPoint) {
        guard let origin = panOrigin, let start = panScroll,
              let clip = enclosingScrollView?.contentView else { return }
        let delta = CGPoint(x: origin.x - point.x, y: origin.y - point.y)
        clip.scroll(to: NSPoint(x: start.x + delta.x, y: start.y + delta.y))
        enclosingScrollView?.reflectScrolledClipView(clip)
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 {
            isSpaceHeld = false
            endPan()
            window?.invalidateCursorRects(for: self)
            return
        }
        super.keyUp(with: event)
    }

    // MARK: - Cursor

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: cursorForCurrentTool())
    }

    private func cursorForCurrentTool() -> NSCursor {
        guard let model else { return .arrow }
        if model.engine.hasPendingShape { return .crosshair }

        // Over floating content the pointer means "resize" or "move", so it
        // must not keep claiming it is about to draw.
        if let floating = model.floating, let point = model.pointerPosition {
            if let handle = floating.handle(at: point, tolerance: canvasHandleTolerance) {
                return Self.cursor(for: handle)
            }
            if floating.contains(point) { return .openHand }
        }

        if isSpaceHeld { return .openHand }

        switch model.tool {
        case .text: return .iBeam
        case .select: return .crosshair
        case .eyedropper: return Self.toolCursor(.eyedropper)
        case .fill, .badge: return Self.toolCursor(model.tool)
        default:
            // Once the footprint ring is big enough to aim with, the cursor
            // only covers the pixels it is pointing at — so it gets out of the
            // way. Below that, the tool draws itself as the pointer.
            if model.engine.settings.nib.size * Int(max(zoom, 1)) >= 12 {
                return Self.emptyCursor
            }
            return model.tool.isFreehand || model.tool == .shape
                ? Self.toolCursor(model.tool)
                : .crosshair
        }
    }

    /// A cursor drawn from the tool's own glyph, hot-spotted where the tool
    /// actually marks.
    ///
    /// A pencil that points with a generic crosshair is the sort of detail that
    /// makes an app feel like a demo; the tip of the pencil *is* the pointer.
    private static func toolCursor(_ tool: ToolKind) -> NSCursor {
        if let cached = cursorCache[tool] { return cached }

        let side: CGFloat = 22
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return true }
            // White under black: the same two-tone treatment the marching ants
            // use, and for the same reason — one colour vanishes over artwork.
            context.setShadow(offset: .zero, blur: 2.5, color: NSColor.white.withAlphaComponent(0.95).cgColor)

            // The fill tool's pointer is a bucket, drawn here because SF
            // Symbols has none — the droplet the system offers reads as the
            // eyedropper's cousin, which is the one tool it must not be
            // confused with.
            if tool == .fill {
                NSColor.black.setFill()
                bucketPath(side: side).fill()
                return true
            }

            let glyph = NSImage(
                systemSymbolName: tool.symbolName, accessibilityDescription: tool.displayName
            )?.withSymbolConfiguration(.init(pointSize: 15, weight: .regular))
            glyph?.draw(
                in: NSRect(x: 2, y: 2, width: side - 4, height: side - 4),
                from: .zero, operation: .sourceOver, fraction: 1
            )
            return true
        }
        image.isTemplate = false

        // Freehand tools mark at their tip, which is drawn bottom-left; the
        // bucket pours from its lip.
        let hotSpot: NSPoint = switch tool {
        case .fill: NSPoint(x: 3, y: side - 5)
        case _ where tool.isFreehand || tool == .shape: NSPoint(x: 3, y: side - 3)
        default: NSPoint(x: side / 2, y: side / 2)
        }
        let cursor = NSCursor(image: image, hotSpot: hotSpot)
        cursorCache[tool] = cursor
        return cursor
    }

    private static var cursorCache: [ToolKind: NSCursor] = [:]

    /// A tipped pail with a drip — the same outline the rail draws.
    private static func bucketPath(side: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: side * 0.10, y: side * 0.70))
        path.line(to: NSPoint(x: side * 0.62, y: side * 0.94))
        path.line(to: NSPoint(x: side * 0.88, y: side * 0.38))
        path.line(to: NSPoint(x: side * 0.46, y: side * 0.14))
        path.close()
        path.appendOval(in: NSRect(x: side * 0.10, y: side * 0.14, width: side * 0.16, height: side * 0.24))
        return path
    }

    /// A fully transparent cursor. Used where the drawn footprint ring is a
    /// more precise pointer than any system cursor.
    private static let emptyCursor: NSCursor = {
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.lockFocus()
        NSColor.clear.set()
        NSRect(x: 0, y: 0, width: 1, height: 1).fill()
        image.unlockFocus()
        return NSCursor(image: image, hotSpot: .zero)
    }()

    private static func cursor(for handle: FloatingSelection.Handle) -> NSCursor {
        // AppKit ships no public diagonal resize cursors, so corners fall back
        // to the nearer axis rather than to a wrong-looking arrow.
        switch handle {
        case .left, .right: .resizeLeftRight
        case .top, .bottom: .resizeUpDown
        case .topLeft, .bottomRight, .topRight, .bottomLeft: .crosshair
        }
    }

    /// Handle grab radius expressed in canvas pixels, derived from zoom so the
    /// target stays a constant on-screen size.
    private var canvasHandleTolerance: Int {
        max(2, Int((Self.handleScreenSize / max(zoom, 0.01)).rounded()))
    }
}

extension CanvasNSView: NSTextViewDelegate {
    /// Losing focus lands the text — clicking the chrome must not silently
    /// discard what was typed.
    func textDidEndEditing(_ notification: Notification) {
        commitText()
    }
}

/// The in-canvas text box.
///
/// A subclass only because `NSTextView` swallows both keys that need to mean
/// something here: Escape (throw the box away) and ⌘↩ (land it). Everything
/// else — selection, editing, dictation, the emoji palette — comes for free by
/// using the real text view rather than drawing a fake caret.
private final class TextEntryView: NSTextView {
    var onCancel: (() -> Void)?
    var onCommit: (() -> Void)?
    var onMove: ((NSPoint) -> Void)?

    override func cancelOperation(_ sender: Any?) { onCancel?() }

    /// ⌘-drag moves the box. The modifier rather than a grab handle: a handle
    /// would sit over the artwork you are annotating, and ⌘-drag is already
    /// what moves an object in half the apps on the machine.
    override func mouseDown(with event: NSEvent) {
        guard event.modifierFlags.contains(.command) else { return super.mouseDown(with: event) }
        var last = event.locationInWindow
        // Track the drag here rather than through the responder chain: the text
        // view would otherwise be selecting text with the same gesture.
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { break }
            let here = next.locationInWindow
            onMove?(NSPoint(x: here.x - last.x, y: last.y - here.y))
            last = here
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .iBeam)
    }

    override func keyDown(with event: NSEvent) {
        // 36 = Return.
        if event.keyCode == 36, event.modifierFlags.contains(.command) {
            onCommit?()
            return
        }
        super.keyDown(with: event)
    }
}
