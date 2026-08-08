import Foundation

/// Drives one canvas: gesture state machine, rasterisation, selection, undo.
///
/// Every mutating entry point returns the **dirty rect** so the view invalidates
/// only what changed. The engine is pure model — it knows nothing about AppKit,
/// SwiftUI, zoom, scroll or the pasteboard — which is what makes the whole tool
/// matrix unit-testable without launching an app.
public final class PaintEngine {

    public enum SelectionOperation: Sendable {
        case replace
        case add
        case subtract
    }

    // MARK: - State

    public private(set) var canvas: Bitmap
    public var settings: ToolSettings
    public var colours: ColourPair
    public private(set) var undoStack: UndoStack

    /// The selected region, if any — a bounding box plus an optional per-pixel
    /// mask. Rectangular marquees carry no mask; the lasso fills one in.
    public private(set) var selection: Selection?

    /// Bounding box of the selection, for callers that only need extents.
    public var selectionBounds: PixelRect? { selection?.bounds }

    /// Content lifted or pasted and not yet written down. The view draws this
    /// on top of `canvas`; the canvas itself does not contain it.
    public private(set) var floating: FloatingSelection?

    /// Set when a colour is sampled so the UI can reflect the new swatch.
    public private(set) var lastSampledColour: PaintColour?

    private var gesture: Gesture = .idle

    /// The brush resolved at gesture start.
    ///
    /// `settings.brush` builds a `Brush` — including its coverage mask — every
    /// time it is read, and it used to be read once per stroke segment. Caching
    /// it for the life of the gesture means the mask is built once per stroke
    /// rather than hundreds of times.
    private var activeBrush: Brush = .pencil

    private enum Gesture {
        case idle
        /// Continuously committed stroke (pencil, brush, eraser).
        case freehand(before: Bitmap, last: PixelPoint, dirty: PixelRect, button: PointerButton)
        /// Highlighter: accumulates coverage, recomposites from `before` so
        /// overlapping passes within one stroke never darken.
        case highlight(before: Bitmap, coverage: [UInt8], last: PixelPoint, dirty: PixelRect, colour: RGBA8)
        /// Live-previewed shape or redaction, committed on release.
        case shape(before: Bitmap, origin: PixelPoint, dirty: PixelRect, button: PointerButton)
        /// Dragging out a rectangular marquee.
        case region(origin: PixelPoint, current: PixelPoint)
        /// Tracing a freeform outline.
        case lasso(points: [PixelPoint])
        /// Dragging floating content around.
        case moveFloating(grab: PixelPoint, startOrigin: PixelPoint)
        /// Dragging one of the floating content's resize handles.
        case resizeFloating(handle: FloatingSelection.Handle)
        /// Bending a chord that has already been drawn — the curve's second step.
        case bend(before: Bitmap, a: PixelPoint, b: PixelPoint, dirty: PixelRect, button: PointerButton)
        /// A press inside an Instant Alpha selection, before it is known whether
        /// this is a click (re-select here) or a drag (move what is selected).
        case pointSelectPending(origin: PixelPoint, operation: SelectionOperation)
    }

    /// How far the pointer must travel before a press inside a point-select
    /// marquee counts as a drag rather than a click. Small enough that moving
    /// feels immediate, large enough to survive the hand-shake in a click.
    private static let dragSlop = 3

    // MARK: - Multi-step shapes

    /// A drawn chord waiting to be bent, and a polygon collecting its corners.
    ///
    /// Both are *pending*: their pixels are on the canvas as a live preview but
    /// no undo step exists yet, so abandoning them leaves no trace and
    /// finishing them records exactly one edit.
    private var pendingCurve: (before: Bitmap, a: PixelPoint, b: PixelPoint)?
    private var pendingPolygon: (before: Bitmap, points: [PixelPoint])?

    /// Whether a shape is mid-construction, so the UI can say so and the app
    /// knows to land it before doing anything else.
    public var hasPendingShape: Bool { pendingCurve != nil || pendingPolygon != nil }

    /// Corners placed so far, for the view's read-out.
    public var pendingPolygonCorners: Int { pendingPolygon?.points.count ?? 0 }

    /// The airbrush's own generator: seeded, so a spray is reproducible.
    private var spray = SprayRandom()

    /// The next step number the badge tool will drop.
    public private(set) var nextBadgeNumber = 1

    public func resetBadgeNumbering() { nextBadgeNumber = 1 }

    /// Size of the region currently being dragged out — marquee, shape or
    /// floating content — for the status bar. `nil` when nothing is in flight.
    public private(set) var activeRegionSize: (width: Int, height: Int)?

    /// How close, in canvas pixels, a click must be to grab a resize handle.
    /// The view sets this from the zoom so the target stays a constant
    /// on-screen size; at 25% a fixed canvas tolerance would be unusable.
    public var handleTolerance: Int = 5

    public init(
        canvas: Bitmap,
        settings: ToolSettings = ToolSettings(),
        colours: ColourPair = ColourPair(),
        // `nil` lets the history budget follow the canvas, which is what every
        // document wants; a number pins it, which is what a test wants.
        undoByteBudget: Int? = nil
    ) {
        self.canvas = canvas
        self.settings = settings
        self.colours = colours
        self.undoStack = UndoStack(byteBudget: undoByteBudget)
    }

    public convenience init(width: Int, height: Int) {
        self.init(canvas: Bitmap(width: width, height: height, fill: .white))
    }

    public var isDrawing: Bool {
        if case .idle = gesture { return false }
        return true
    }

    public var canUndo: Bool { undoStack.canUndo }
    public var canRedo: Bool { undoStack.canRedo }
    public var hasSelection: Bool { selection != nil || floating != nil }

    // MARK: - Gesture lifecycle

    @discardableResult
    public func beginStroke(
        at point: PixelPoint,
        button: PointerButton = .primary,
        selectionOperation: SelectionOperation = .replace
    ) -> PixelRect {
        // A new gesture starting while one is live means we lost a mouse-up
        // (window deactivation, a modal). Commit rather than dropping the work.
        if isDrawing { _ = endStroke(at: point) }

        let tool = settings.tool

        // A handle beats everything else, including the content underneath it.
        if let floating, let handle = floating.handle(at: point, tolerance: handleTolerance) {
            gesture = .resizeFloating(handle: handle)
            activeRegionSize = (floating.frame.width, floating.frame.height)
            return .empty
        }

        // Grabbing inside floating content moves it, whatever tool is active.
        // That is what makes a pasted image feel like an object rather than a
        // mode you have to remember you are in.
        if let floating, floating.contains(point) {
            gesture = .moveFloating(grab: point, startOrigin: floating.origin)
            activeRegionSize = (floating.frame.width, floating.frame.height)
            return .empty
        }

        // Dragging inside an existing marquee LIFTS it and moves it, with no
        // separate Cut step. Requiring Cut first is the classic reason people
        // conclude a selection "doesn't do anything".
        // Instant Alpha defers the choice. Its marquee is usually a *background*
        // and so covers most of the canvas, which is why this used to exclude it
        // outright — if every press inside moved the selection there would be
        // nowhere left to click to select something else. But excluding it means
        // the region you just selected can never be moved, which is the more
        // common complaint by far. So neither: a press waits, a drag past
        // `dragSlop` lifts and moves, a click in place re-selects.

        if settings.tool == .select, settings.selectionKind.isPointSelect,
           let current = selection, current.contains(point)
        {
            gesture = .pointSelectPending(origin: point, operation: selectionOperation)
            return .empty
        }

        if settings.tool == .select, !settings.selectionKind.isPointSelect,
           let current = selection, current.contains(point)
        {
            let lifted = cutSelection()
            if let floating {
                gesture = .moveFloating(grab: point, startOrigin: floating.origin)
                activeRegionSize = (floating.frame.width, floating.frame.height)
            }
            return lifted
        }

        // Anything else lands the floating content first.
        var dirty = commitFloating()

        if tool == .select, settings.selectionKind.isPointSelect {
            return dirty.union(selectInstantAlpha(at: point, operation: selectionOperation))
        }

        if tool.isReadOnly {
            return dirty.union(performReadOnly(tool, at: point))
        }

        if tool == .fill {
            dirty = dirty.union(commitSingleShot("Fill") { canvas in
                Raster.floodFill(
                    from: point,
                    with: self.colours.colour(for: button).rgba8,
                    tolerance: self.settings.fillTolerance,
                    into: &canvas
                )
            })
            return dirty
        }

        // Text has no stroke: the view drags the box and runs the editor, then
        // calls `drawText`. Without this the tool fell through to the shape
        // gesture below and quietly drew a rectangle instead.
        if tool == .text {
            gesture = .idle
            return dirty
        }

        if tool == .badge {
            return dirty.union(dropBadge(at: point, button: button))
        }

        // The curve's second step: a chord is already down, so this drag bends
        // it rather than starting a new one.
        if settings.shapeKind == .curve, tool == .shape, let pending = pendingCurve {
            gesture = .bend(
                before: pending.before, a: pending.a, b: pending.b,
                dirty: canvas.bounds, button: button
            )
            pendingCurve = nil
            return dirty.union(continueStroke(to: point))
        }
        // A polygon collects corners across clicks, so its own clicks must not
        // be treated as "something else happened" and land it early.
        if tool == .shape, settings.shapeKind == .polygon {
            return dirty.union(addPolygonCorner(at: point, button: button))
        }
        // Anything else lands a half-finished shape rather than losing it.
        dirty = dirty.union(commitPendingShape())

        if tool.isRegionDrag {
            let previous = selectionOverlayRect()
            selection = nil
            if tool == .pixelate {
                gesture = .shape(before: canvas, origin: snapped(point), dirty: .empty, button: button)
            } else if settings.selectionKind.isFreeform {
                gesture = .lasso(points: [point])
            } else {
                gesture = .region(origin: snapped(point), current: snapped(point))
            }
            return dirty.union(previous)
        }

        let before = canvas
        activeBrush = settings.brush

        if tool == .highlighter {
            let colour = highlighterColour(for: button)
            var coverage = [UInt8](repeating: 0, count: canvas.count)
            let stepDirty = stampHighlighter(
                at: point, into: &coverage, before: before, colour: colour
            )
            gesture = .highlight(
                before: before, coverage: coverage, last: point, dirty: stepDirty, colour: colour
            )
            return dirty.union(stepDirty)
        }

        if tool.isFreehand {
            let stepDirty = settings.isSpraying
                ? Raster.spray(
                    activeBrush,
                    colour: strokeColour(for: button).rgba8,
                    at: point,
                    density: settings.sprayDensity,
                    into: &canvas,
                    using: &spray
                  )
                : Raster.stamp(
                    activeBrush,
                    colour: strokeColour(for: button).rgba8,
                    at: point,
                    into: &canvas
                  )
            gesture = .freehand(before: before, last: point, dirty: stepDirty, button: button)
            return dirty.union(stepDirty)
        }

        gesture = .shape(before: before, origin: snapped(point), dirty: .empty, button: button)
        return dirty
    }

    @discardableResult
    public func continueStroke(to point: PixelPoint, constrained: Bool = false) -> PixelRect {
        switch gesture {
        case .idle:
            return .empty

        case let .freehand(before, last, dirty, button):
            // A spray tip keeps spraying where it is: repeating the same
            // point is how holding still builds density, so it must not
            // early-out.
            let stepDirty = settings.isSpraying
                ? Raster.sprayLine(
                    from: last,
                    to: point,
                    brush: activeBrush,
                    colour: strokeColour(for: button).rgba8,
                    density: settings.sprayDensity,
                    into: &canvas,
                    using: &spray
                  )
                : Raster.strokeLine(
                    from: last,
                    to: point,
                    brush: activeBrush,
                    colour: strokeColour(for: button).rgba8,
                    into: &canvas
                  )
            gesture = .freehand(
                before: before, last: point, dirty: dirty.union(stepDirty), button: button
            )
            return stepDirty

        case let .highlight(before, coverage, last, dirty, colour):
            var updated = coverage
            let stepDirty = strokeHighlighter(
                from: last, to: point, into: &updated, before: before, colour: colour
            )
            gesture = .highlight(
                before: before, coverage: updated, last: point,
                dirty: dirty.union(stepDirty), colour: colour
            )
            return stepDirty

        case let .shape(before, origin, previousDirty, button):
            // Roll back the previous preview, then draw the new one. Restoring
            // only the previously dirtied rect keeps a live preview cheap.
            if !previousDirty.isEmpty {
                let patch = before.extract(previousDirty)
                canvas.restore(patch.pixels, to: patch.rect)
            }
            let end = snappedEnd(constrained ? constrain(origin, to: point) : point, from: origin)
            let drawn = settings.tool == .pixelate
                ? Raster.pixelate(
                    PixelRect(corners: origin, end),
                    blockSize: settings.pixelateBlockSize,
                    into: &canvas
                  )
                : drawShape(from: origin, to: end, button: button)
            gesture = .shape(before: before, origin: origin, dirty: drawn, button: button)
            return previousDirty.union(drawn)

        case let .region(origin, _):
            let previous = selectionOverlayRect()
            let end = snappedEnd(constrained ? constrain(origin, to: point) : point, from: origin)
            gesture = .region(origin: origin, current: end)
            let box = PixelRect(corners: origin, end)
            let region = box.intersection(canvas.bounds)
            // An elliptical marquee is the same drag with a mask on it.
            selection = settings.selectionKind == .ellipse
                ? Selection(ellipseIn: box, clippedTo: canvas.bounds)
                : Selection(bounds: region)
            activeRegionSize = (region.width, region.height)
            return previous.union(selectionOverlayRect())

        case let .lasso(points):
            // Only record a point when it actually moves, so a slow drag does
            // not build a path of thousands of duplicates.
            guard points.last != point else { return .empty }
            let previous = selectionOverlayRect()
            var updated = points
            updated.append(point)
            gesture = .lasso(points: updated)
            lassoPath = updated
            if let live = Selection(freeform: updated, clippedTo: canvas.bounds) {
                selection = live
                activeRegionSize = (live.bounds.width, live.bounds.height)
            }
            return previous.union(selectionOverlayRect())

        case let .bend(before, a, b, previousDirty, button):
            if !previousDirty.isEmpty {
                let patch = before.extract(previousDirty)
                canvas.restore(patch.pixels, to: patch.rect)
            }
            let drawn = Raster.strokeCurve(
                from: a, through: point, to: b,
                brush: activeBrush,
                colour: colours.colour(for: button).rgba8,
                into: &canvas,
                dash: settings.strokeDash
            )
            gesture = .bend(before: before, a: a, b: b, dirty: drawn, button: button)
            return previousDirty.union(drawn)

        case let .pointSelectPending(origin, operation):
            guard abs(point.x - origin.x) > Self.dragSlop
                    || abs(point.y - origin.y) > Self.dragSlop
            else { return .empty }
            // Past the slop: this is a move. Lift the selection exactly as the
            // marquee kinds do, then hand the rest of the drag to moveFloating.
            _ = operation
            let lifted = cutSelection()
            guard let floating else { gesture = .idle; return lifted }
            gesture = .moveFloating(grab: origin, startOrigin: floating.origin)
            return lifted.union(continueStroke(to: point, constrained: constrained))

        case let .moveFloating(grab, startOrigin):
            guard var floating else { return .empty }
            let previous = floating.frame
            floating.move(to: snapped(PixelPoint(
                x: startOrigin.x + (point.x - grab.x),
                y: startOrigin.y + (point.y - grab.y)
            )))
            self.floating = floating
            activeRegionSize = (floating.frame.width, floating.frame.height)
            return previous.union(floating.frame).insetBy(-handleTolerance)

        case let .resizeFloating(handle):
            guard var floating else { return .empty }
            let previous = floating.frame
            floating.resize(to: floating.frame(draggingHandle: handle, to: point, uniform: constrained))
            self.floating = floating
            activeRegionSize = (floating.frame.width, floating.frame.height)
            return previous.union(floating.frame).insetBy(-handleTolerance)
        }
    }

    @discardableResult
    public func endStroke(at point: PixelPoint? = nil, constrained: Bool = false) -> PixelRect {
        var refreshed = PixelRect.empty
        if let point {
            refreshed = continueStroke(to: point, constrained: constrained)
        }

        switch gesture {
        case .idle:
            return refreshed

        case let .freehand(before, _, dirty, _):
            gesture = .idle
            // The variation names the edit, not the tool that owns it — the
            // same rule the shape case below follows, where a rectangle undoes
            // as "Rectangle" rather than as "Shape". A spray stroke is a spray.
            let name = settings.isSpraying ? "Spray" : settings.tool.displayName
            recordEdit(name: name, before: before, dirty: dirty)
            return refreshed.union(dirty)

        case let .highlight(before, _, _, dirty, _):
            gesture = .idle
            recordEdit(name: "Highlighter", before: before, dirty: dirty)
            return refreshed.union(dirty)

        case let .shape(before, origin, dirty, _):
            gesture = .idle
            // A curve's first drag only lays the chord: hold it as a pending
            // preview so the next drag can bend it, and record nothing yet.
            if settings.tool == .shape, settings.shapeKind == .curve, !dirty.isEmpty {
                pendingCurve = (before: before, a: origin, b: point ?? origin)
                return refreshed.union(dirty)
            }
            let name = settings.tool == .pixelate ? "Pixelate" : settings.shapeKind.displayName
            recordEdit(name: name, before: before, dirty: dirty)
            return refreshed.union(dirty)

        case let .bend(before, _, _, dirty, _):
            gesture = .idle
            recordEdit(name: "Curve", before: before, dirty: dirty)
            return refreshed.union(dirty)

        case .region:
            gesture = .idle
            activeRegionSize = nil
            // A click with no drag clears the marquee rather than leaving a
            // 1px selection nobody asked for.
            if let current = selection, current.bounds.width <= 1, current.bounds.height <= 1 {
                let previous = selectionOverlayRect()
                selection = nil
                return refreshed.union(previous)
            }
            return refreshed

        case let .lasso(points):
            gesture = .idle
            activeRegionSize = nil
            let previous = selectionOverlayRect()
            // A traced outline is closed automatically — nobody lands exactly
            // back on their own start pixel, and refusing to close would make
            // the tool feel broken rather than precise.
            selection = Selection(freeform: points, clippedTo: canvas.bounds)
            lassoPath = selection == nil ? [] : points
            return refreshed.union(previous).union(selectionOverlayRect())

        case let .pointSelectPending(origin, operation):
            // The pointer never left the slop, so this was a click: select at
            // the point pressed, which is what Instant Alpha has always done.
            gesture = .idle
            return refreshed.union(selectInstantAlpha(at: origin, operation: operation))

        case .moveFloating, .resizeFloating:
            gesture = .idle
            activeRegionSize = nil
            return refreshed
        }
    }

    /// Abandon the active gesture. Bound to Escape.
    @discardableResult
    public func cancelStroke() -> PixelRect {
        // A half-built curve or polygon is only a preview, so Escape wipes it
        // back to the pixels that were there before it started.
        if let before = pendingCurve?.before ?? pendingPolygon?.before {
            pendingCurve = nil
            pendingPolygon = nil
            canvas = before
            gesture = .idle
            return canvas.bounds
        }

        switch gesture {
        case .idle:
            // A pending point-select has not touched the canvas or the
            // selection yet, so cancelling it is exactly going idle.
            return .empty

        case .pointSelectPending:
            gesture = .idle
            return .empty

        case let .freehand(before, _, dirty, _),
             let .shape(before, _, dirty, _),
             let .bend(before, _, _, dirty, _):
            gesture = .idle
            guard !dirty.isEmpty else { return .empty }
            let patch = before.extract(dirty)
            canvas.restore(patch.pixels, to: patch.rect)
            return dirty

        case let .highlight(before, _, _, dirty, _):
            gesture = .idle
            guard !dirty.isEmpty else { return .empty }
            let patch = before.extract(dirty)
            canvas.restore(patch.pixels, to: patch.rect)
            return dirty

        case .region, .lasso:
            gesture = .idle
            activeRegionSize = nil
            lassoPath = []
            let previous = selectionOverlayRect()
            selection = nil
            return previous

        case .moveFloating, .resizeFloating:
            gesture = .idle
            activeRegionSize = nil
            return .empty
        }
    }

    // MARK: - Selection

    /// Select the connected colour region under `point` without changing it.
    ///
    /// This is the read-only half of flood fill: the same span walk produces a
    /// mask, then every existing selection command consumes that mask.
    @discardableResult
    public func selectInstantAlpha(
        at point: PixelPoint,
        operation: SelectionOperation = .replace
    ) -> PixelRect {
        var dirty = commitFloating().union(selectionOverlayRect())
        let incoming = Raster.floodSelection(
            from: point,
            tolerance: settings.selectionTolerance,
            in: canvas
        )
        selection = combinedSelection(with: incoming, operation: operation)
        lassoPath = []
        gesture = .idle
        activeRegionSize = nil
        dirty = dirty.union(selectionOverlayRect())
        return dirty
    }

    /// Combine a new colour region with the current selection.
    ///
    /// Shift-add and Option-subtract avoid Preview's repeat-delete loop while
    /// keeping one selection mask as the currency for every downstream action.
    private func combinedSelection(
        with incoming: Selection?,
        operation: SelectionOperation
    ) -> Selection? {
        switch operation {
        case .replace:
            return incoming
        case .add where selection == nil:
            return incoming
        case .subtract where selection == nil:
            return nil
        default:
            break
        }

        guard let current = selection else { return incoming }
        let bounds: PixelRect
        switch operation {
        case .replace:
            return incoming
        case .add:
            bounds = incoming.map { current.bounds.union($0.bounds) } ?? current.bounds
        case .subtract:
            bounds = current.bounds
        }

        var mask = [UInt8](repeating: 0, count: bounds.area)
        for y in bounds.minY..<bounds.maxY {
            for x in bounds.minX..<bounds.maxX {
                let point = PixelPoint(x: x, y: y)
                let wasSelected = current.contains(point)
                let isIncoming = incoming?.contains(point) == true
                let selected = switch operation {
                case .replace: isIncoming
                case .add: wasSelected || isIncoming
                case .subtract: wasSelected && !isIncoming
                }
                if selected {
                    mask[(y - bounds.minY) * bounds.width + (x - bounds.minX)] = 255
                }
            }
        }
        guard mask.contains(255) else { return nil }
        return Selection(bounds: bounds, mask: mask).tightened()
    }

    /// Swap the marquee for everything outside it.
    ///
    /// Falls back to the bounding box of the inverse, because the selection
    /// model is rectangular — an L-shaped region would need a mask, and
    /// pretending otherwise would silently act on the wrong pixels.
    @discardableResult
    public func invertSelection() -> PixelRect {
        _ = commitFloating()
        guard let current = selection, !current.isEmpty else {
            selectAll()
            return canvas.bounds
        }
        let previous = selectionOverlayRect()

        if current.isRectangular && current.bounds == canvas.bounds {
            selection = nil
            lassoPath = []
            return previous.union(canvas.bounds)
        }

        // Inverting a shape produces a mask over the whole canvas: everything
        // the old selection did not cover. A bounding-box answer here would
        // select the very pixels the user just excluded.
        var inverted = [UInt8](repeating: 255, count: canvas.count)
        for y in current.bounds.minY..<current.bounds.maxY {
            for x in current.bounds.minX..<current.bounds.maxX {
                let point = PixelPoint(x: x, y: y)
                guard canvas.isInBounds(point), current.coverage(at: point) > 0 else { continue }
                inverted[canvas.index(point)] = 0
            }
        }
        selection = Selection(bounds: canvas.bounds, mask: inverted).tightened()
        lassoPath = []
        return previous.union(canvas.bounds)
    }

    public func selectAll() {
        _ = commitFloating()
        lassoPath = []
        selection = Selection(bounds: canvas.bounds)
    }

    /// The traced outline of the current lasso, for drawing its ants.
    public private(set) var lassoPath: [PixelPoint] = []

    @discardableResult
    public func deselect() -> PixelRect {
        let dirty = commitFloating().union(selectionOverlayRect())
        selection = nil
        lassoPath = []
        return dirty
    }

    /// The pixels inside the marquee, or the floating content.
    public func selectedContent() -> Bitmap? {
        if let floating { return floating.bitmap }
        guard let selection, !selection.isEmpty else { return nil }
        // Goes through the masked extract, so a lasso yields its actual shape
        // with everything outside it transparent — not its bounding box.
        return canvas.extract(selection)
    }

    /// Lift the selection into floating content, backfilling with the
    /// background colour.
    @discardableResult
    public func cutSelection() -> PixelRect {
        guard floating == nil, let selection, !selection.isEmpty,
              let content = selectedContent()
        else { return .empty }

        let before = canvas
        canvas.fill(selection, with: colours.background.rgba8)
        recordEdit(name: "Cut", before: before, dirty: selection.bounds)

        floating = FloatingSelection(
            bitmap: content,
            origin: PixelPoint(x: selection.bounds.minX, y: selection.bounds.minY)
        )
        self.selection = nil
        lassoPath = []
        return selection.bounds
    }

    @discardableResult
    public func deleteSelection() -> PixelRect {
        if floating != nil {
            let dirty = floating?.frame ?? .empty
            floating = nil
            return dirty
        }
        guard let selection, !selection.isEmpty else { return .empty }
        let dirty = commitSingleShot("Delete") { canvas in
            canvas.fill(selection, with: self.colours.background.rgba8)
            return selection.bounds
        }
        self.selection = nil
        lassoPath = []
        return dirty
    }

    /// Clear the selected pixels to alpha rather than painting the background
    /// colour over them. Instant Alpha exposes this as its direct outcome while
    /// Delete keeps the classic Paint behaviour.
    /// - Parameter named: the undo action name. Remove Background clears the same
    ///   pixels the same way, and naming it "Make transparent" in the Edit menu
    ///   would describe the mechanism rather than the command the user chose.
    @discardableResult
    public func makeSelectionTransparent(named: String = "Make transparent") -> PixelRect {
        guard floating == nil, let selection, !selection.isEmpty else { return .empty }
        let dirty = commitSingleShot(named) { canvas in
            canvas.fill(selection, with: .clear)
            return selection.bounds
        }
        self.selection = nil
        lassoPath = []
        return dirty
    }

    /// Key the page out from behind the subject, in one action.
    ///
    /// Instant Alpha already does this, but it costs a tool switch, a tolerance
    /// decision and a menu item, and the equivalent in Windows 11 Paint is one
    /// click. This is that one click, and it is not a new engine: the same span
    /// walk, seeded automatically at a tolerance that works on a real capture.
    ///
    /// **Seeded from the four corners, because that is where a background is.**
    /// A centre seed would key out whatever the subject is standing on. All four
    /// rather than one because a subject that touches an edge splits the page
    /// into regions, and a corner in a different region from the other three is
    /// the normal case, not the exotic one.
    ///
    /// Returns `false` and changes nothing when there is no background to speak
    /// of — a flat image is one region from any seed, and a Remove Background
    /// that erases the picture is far worse than one that declines.
    @discardableResult
    public func removeBackground(tolerance: Int = 24) -> Bool {
        _ = commitFloating()
        guard !canvas.bounds.isEmpty else { return false }

        let corners = [
            PixelPoint(x: 0, y: 0),
            PixelPoint(x: canvas.width - 1, y: 0),
            PixelPoint(x: 0, y: canvas.height - 1),
            PixelPoint(x: canvas.width - 1, y: canvas.height - 1)
        ]

        // Built up in `selection` itself, through the same combiner Shift-click
        // uses — one description of "add these regions together" serves both, and
        // the page *is* what the selection should end up being.
        let previous = selection
        selection = nil
        for corner in corners {
            selection = combinedSelection(
                with: Raster.floodSelection(from: corner, tolerance: tolerance, in: canvas),
                operation: .add
            )
        }

        guard let page = selection, !page.isEmpty else {
            selection = previous
            return false
        }
        let covered = page.mask?.count { $0 > 0 } ?? page.bounds.area
        guard Double(covered) / Double(canvas.count) < 0.92 else {
            selection = previous
            return false
        }

        makeSelectionTransparent(named: "Remove background")
        return true
    }

    /// Place `bitmap` as floating content, centred on the canvas (or at the
    /// current selection's origin when there is one).
    @discardableResult
    public func paste(_ bitmap: Bitmap) -> PixelRect {
        var dirty = commitFloating()

        // Grow first, so the pasted image is *entirely on the canvas* the
        // moment it arrives.
        //
        // Before this, an image larger than the canvas floated with its edges
        // outside the document — which meant they were not drawn, its top-left
        // resize handle sat off the visible area where no click could reach it,
        // and the window had no idea it should be any bigger. Every one of
        // those reads as a different bug; they were all this.
        if growsToFitFloating, bitmap.width > canvas.width || bitmap.height > canvas.height {
            let wanted = PixelRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height)
            if let grown = ImageTransform.canvasGrown(
                canvas, toInclude: wanted, fill: colours.background
            ) {
                let before = canvas
                canvas = grown.canvas
                recordResize(name: "Fit to pasted image", from: before)
                dirty = canvas.bounds
            }
        }

        let origin: PixelPoint
        if let selection, !selection.isEmpty {
            origin = PixelPoint(x: selection.bounds.minX, y: selection.bounds.minY)
        } else {
            origin = PixelPoint(
                x: max(0, (canvas.width - bitmap.width) / 2),
                y: max(0, (canvas.height - bitmap.height) / 2)
            )
        }

        dirty = dirty.union(selectionOverlayRect())
        selection = nil
        floating = FloatingSelection(bitmap: bitmap, origin: origin)
        settings.tool = .select
        return dirty.union(floating?.frame ?? .empty)
    }

    /// Drop a prepared image onto the canvas as floating content, scaled to fit.
    ///
    /// **A stamp must never enlarge the document.** Paste grows the canvas, because
    /// a pasted screenshot is new content that deserves room. A signature is the
    /// opposite: it goes *onto* something that already exists, and a signature
    /// wider than the page it is signing should shrink, not push the page out. So
    /// this scales down to a fraction of the canvas rather than growing it.
    ///
    /// It arrives floating, so it can be positioned and resized before it lands —
    /// which is the entire reason it reuses the paste machinery instead of
    /// compositing straight in.
    @discardableResult
    public func stamp(_ bitmap: Bitmap, coveringAtMost fraction: Double = 0.4) -> PixelRect {
        var dirty = commitFloating()
        guard bitmap.width > 0, bitmap.height > 0, !canvas.bounds.isEmpty else { return dirty }

        var placed = bitmap
        let widthLimit = Double(canvas.width) * fraction
        let heightLimit = Double(canvas.height) * fraction
        let scale = min(1, min(widthLimit / Double(bitmap.width), heightLimit / Double(bitmap.height)))
        if scale < 1 {
            let target = (
                width: max(1, Int((Double(bitmap.width) * scale).rounded())),
                height: max(1, Int((Double(bitmap.height) * scale).rounded()))
            )
            // Smooth, not nearest: a signature is a curve, and nearest-neighbour
            // would stair-step exactly the strokes the ink keying went to trouble
            // to keep soft.
            if let scaled = ImageTransform.scaled(bitmap, to: target, using: .smooth) {
                placed = scaled
            }
        }

        // Lower right, inset — where a signature goes on a document, and clear of
        // the top-left where annotation usually starts.
        let inset = max(8, min(canvas.width, canvas.height) / 24)
        let origin = PixelPoint(
            x: max(0, canvas.width - placed.width - inset),
            y: max(0, canvas.height - placed.height - inset)
        )

        dirty = dirty.union(selectionOverlayRect())
        selection = nil
        floating = FloatingSelection(bitmap: placed, origin: origin)
        settings.tool = .select
        return dirty.union(floating?.frame ?? .empty)
    }

    /// Write floating content into the canvas as one undoable edit, growing the
    /// canvas if the content does not fit inside it.
    ///
    /// **Placing something must never destroy part of it.** This used to
    /// composite against `canvas.bounds` and silently drop whatever fell
    /// outside — so pasting an image larger than the canvas, or dragging one
    /// half off the edge, looked fine right up until you clicked away and the
    /// overhang was gone. The undo stack held the crop, not the original, so
    /// there was nothing to recover.
    ///
    /// Growing is the honest default for a markup app: the canvas is a sheet of
    /// paper you are annotating, not a fixed frame the content has to earn its
    /// way into. `growsToFitFloating` exists for the one caller that genuinely
    /// wants the old behaviour — a stamp clipped to the page.
    @discardableResult
    public func commitFloating() -> PixelRect {
        guard let floating else { return .empty }
        self.floating = nil

        let before = canvas
        var placement = floating.origin

        if growsToFitFloating, canvas.bounds.union(floating.frame) != canvas.bounds {
            guard let grown = ImageTransform.canvasGrown(
                canvas, toInclude: floating.frame, fill: colours.background
            ) else {
                // Too large to represent. Fall back to clipping rather than
                // losing the edit entirely.
                return compositeClipped(floating, before: before)
            }
            canvas = grown.canvas
            placement = PixelPoint(
                x: floating.origin.x + grown.offset.dx,
                y: floating.origin.y + grown.offset.dy
            )
            // Any surviving selection now names the wrong pixels — the artwork
            // moved underneath it. Dropping it is honest; silently leaving a
            // marquee pointing somewhere else is not.
            selection = nil
            lassoPath = []
            canvas.composite(floating.bitmap, at: placement)
            lastPlacedFloatingFrame = PixelRect(
                x: placement.x, y: placement.y,
                width: floating.frame.width, height: floating.frame.height
            )
            recordResize(name: "Paste", from: before)
            return canvas.bounds
        }

        return compositeClipped(floating, before: before)
    }

    /// Whether committing floating content may enlarge the canvas.
    public var growsToFitFloating = true

    /// Where the last committed float ended up, in the canvas it ended up in.
    ///
    /// Not the same as the frame it had before the commit: growing the canvas to
    /// hold content dragged off the top-left shifts everything, so a caller that
    /// wants to crop to what it just placed has to be told the post-growth rect.
    public private(set) var lastPlacedFloatingFrame: PixelRect?

    private func compositeClipped(_ floating: FloatingSelection, before: Bitmap) -> PixelRect {
        let target = floating.frame.intersection(canvas.bounds)
        guard !target.isEmpty else { return floating.frame.insetBy(-handleTolerance) }
        lastPlacedFloatingFrame = floating.frame
        canvas.composite(floating.bitmap, at: floating.origin)
        recordEdit(name: "Move", before: before, dirty: target)
        return floating.frame.union(target)
    }

    /// Shift floating content by whole pixels. Bound to the arrow keys, because
    /// pixel-exact placement is impossible with a mouse and essential when the
    /// thing you pasted has to line up with what is underneath it.
    @discardableResult
    public func nudgeFloating(by delta: (dx: Int, dy: Int)) -> PixelRect {
        guard let floating else { return .empty }
        let before = floating.frame
        self.floating = floating.moved(by: delta)
        return before.union(self.floating?.frame ?? .empty).insetBy(-handleTolerance)
    }

    /// Move floating content to an absolute origin. Used when dropping an
    /// image at the pointer, where the target is a position rather than a delta.
    @discardableResult
    public func moveFloating(to origin: PixelPoint) -> PixelRect {
        guard var floating else { return .empty }
        let before = floating.frame
        floating.move(to: origin)
        self.floating = floating
        return before.union(floating.frame).insetBy(-handleTolerance)
    }

    /// Discard floating content without writing it.
    @discardableResult
    public func discardFloating() -> PixelRect {
        guard let floating else { return .empty }
        self.floating = nil
        return floating.frame
    }

    /// Trim the canvas to the selection.
    ///
    /// For a lasso the canvas becomes the selection's bounding box and
    /// everything outside the traced shape is cleared to transparent — cropping
    /// to a freeform shape has to mean the shape, not the box around it, or the
    /// tool is a rectangle wearing a costume.
    @discardableResult
    /// Crop to the selection, or to whatever is floating.
    ///
    /// **Floating content defines the crop region.** This used to commit the
    /// float and *then* look for a selection — of which a paste leaves none — so
    /// cropping right after pasting placed the image and reported that nothing
    /// was selected. The work was done and the message said it had not been.
    ///
    /// Reading the frame after the commit rather than before is deliberate:
    /// committing can enlarge the canvas and shift the existing artwork, which
    /// moves the content's coordinates with it.
    public func cropToSelection() -> Bool {
        if floating != nil {
            _ = commitFloating()
            if let placed = lastPlacedFloatingFrame {
                let region = placed.intersection(canvas.bounds)
                if !region.isEmpty { selection = Selection(bounds: region) }
            }
        }

        guard let selection, !selection.isEmpty,
              selection.bounds != canvas.bounds || !selection.isRectangular,
              var cropped = ImageTransform.cropped(canvas, to: selection.bounds)
        else { return false }

        if let mask = selection.mask {
            for index in 0..<cropped.pixels.count where mask[index] == 0 {
                cropped.pixels[index] = .clear
            }
        }

        replaceCanvas(with: cropped, actionName: "Crop")
        self.selection = nil
        lassoPath = []
        return true
    }

    /// Trim uniform edges away, or trim to the selection's content.
    ///
    /// Tolerance matters here: a screenshot's "solid" border is rarely one
    /// exact colour once it has been through a lossy format or a shadow, and a
    /// zero-tolerance trim silently does nothing on exactly the images people
    /// most want to trim.
    @discardableResult
    public func trimBorders(tolerance: Int = 6) -> Bool {
        _ = commitFloating()
        guard let trimmed = ImageTransform.trimmingUniformBorder(canvas, tolerance: tolerance)
        else { return false }
        replaceCanvas(with: trimmed, actionName: "Trim borders")
        selection = nil
        lassoPath = []
        return true
    }

    /// Rect the view must repaint to erase or draw the marquee, padded for the
    /// ants themselves.
    private func selectionOverlayRect() -> PixelRect {
        guard let selection else { return .empty }
        return selection.bounds.insetBy(-2)
    }

    // MARK: - Multi-step shapes

    /// Land whatever half-built shape is on the canvas as one undoable edit.
    ///
    /// Called when anything else happens — another tool, a menu command, a
    /// save. A preview that silently disappears because you reached for the
    /// eraser is worse than one that commits.
    @discardableResult
    public func commitPendingShape() -> PixelRect {
        if let pending = pendingCurve {
            pendingCurve = nil
            let dirty = canvas.bounds
            recordEdit(name: "Curve", before: pending.before, dirty: dirty)
            return dirty
        }
        if let pending = pendingPolygon {
            pendingPolygon = nil
            // Fewer than three corners is a stray click, not a shape.
            guard pending.points.count > 2 else {
                canvas = pending.before
                return canvas.bounds
            }
            let dirty = canvas.bounds
            recordEdit(name: "Polygon", before: pending.before, dirty: dirty)
            return dirty
        }
        return .empty
    }

    /// Add a corner, or close the polygon when the click lands back on the
    /// first one.
    @discardableResult
    private func addPolygonCorner(at point: PixelPoint, button: PointerButton) -> PixelRect {
        let before = pendingPolygon?.before ?? canvas
        var points = pendingPolygon?.points ?? []

        // Clicking the first corner again closes the shape — the same gesture
        // the classic tool used, and the only one that needs no instruction.
        if let first = points.first, points.count > 2, first.isNear(point, within: closeTolerance) {
            pendingPolygon = (before: before, points: points)
            return commitPendingShape()
        }

        points.append(point)
        pendingPolygon = (before: before, points: points)
        return redrawPendingPolygon(preview: point, button: button)
    }

    /// Close the polygon where it stands. Bound to Return and a double-click.
    @discardableResult
    public func closePolygon() -> PixelRect {
        guard pendingPolygon != nil else { return .empty }
        return commitPendingShape()
    }

    /// Rubber-band the edge that follows the pointer between clicks.
    @discardableResult
    public func previewPolygon(to point: PixelPoint) -> PixelRect {
        guard pendingPolygon != nil else { return .empty }
        return redrawPendingPolygon(preview: point, button: .primary)
    }

    private func redrawPendingPolygon(preview: PixelPoint, button: PointerButton) -> PixelRect {
        guard let pending = pendingPolygon else { return .empty }
        canvas = pending.before
        let points = pending.points + (pending.points.last == preview ? [] : [preview])
        drawPolygonShape(
            points,
            stroke: colours.colour(for: button).rgba8,
            fill: colours.colour(for: button == .primary ? .secondary : .primary).rgba8,
            closed: points.count > 2
        )
        return canvas.bounds
    }

    /// How close a click has to land to count as "the first corner again".
    private var closeTolerance: Int { max(4, settings.brushSize) }

    // MARK: - Step badges

    /// Drop the next numbered circle. Click, click, click — the fastest way to
    /// turn a screenshot into a walkthrough, and the one markup job the classic
    /// tool never had an answer for.
    @discardableResult
    private func dropBadge(at point: PixelPoint, button: PointerButton) -> PixelRect {
        let diameter = max(18, settings.brushSize * 3)
        let rect = PixelRect(
            x: point.x - diameter / 2, y: point.y - diameter / 2,
            width: diameter, height: diameter
        )
        let disc = colours.colour(for: button)
        let number = "\(nextBadgeNumber)"

        let dirty = commitSingleShot("Badge \(number)", badgeNumber: nextBadgeNumber) { canvas in
            var touched = Raster.fillEllipse(in: rect, colour: disc.rgba8, into: &canvas)
            // The numeral takes the contrasting colour, so a badge stays
            // readable whatever colour is loaded.
            let ink: PaintColour = disc.prefersDarkContrast ? .black : .white
            let size = Double(diameter) * 0.58
            touched = touched.union(TextRenderer.draw(
                number,
                in: PixelRect(
                    x: rect.minX,
                    y: rect.minY + Int((Double(diameter) - size * 1.22) / 2),
                    width: rect.width,
                    height: Int(size * 1.4)
                ),
                style: TextRenderer.Style(
                    fontName: "Helvetica-Bold", pointSize: size, colour: ink, alignment: .centre
                ),
                into: &canvas
            ))
            return touched
        }
        if !dirty.isEmpty { nextBadgeNumber += 1 }
        return dirty
    }

    // MARK: - Text

    /// Rasterise `string` inside `rect` as one undoable edit.
    ///
    /// Text becomes pixels the moment it lands — see `TextRenderer` for why
    /// that is the honest model for a paint app rather than a live object the
    /// PNG export would flatten anyway.
    @discardableResult
    public func drawText(_ string: String, in rect: PixelRect, style: TextRenderer.Style) -> PixelRect {
        guard !string.isEmpty, !rect.isEmpty else { return .empty }
        let landed = commitFloating()
        return landed.union(
            commitSingleShot("Text") { canvas in
                TextRenderer.draw(string, in: rect, style: style, into: &canvas)
            }
        )
    }

    // MARK: - Whole-canvas operations

    @discardableResult
    public func clearCanvas() -> PixelRect {
        _ = discardFloating()
        return commitSingleShot("Clear image") { canvas in
            canvas.fillAll(with: self.colours.background.rgba8)
            return canvas.bounds
        }
    }

    @discardableResult
    public func invertColours() -> PixelRect {
        // Invert honours the marquee: on a screenshot markup, inverting one
        // region is far more often what you want than inverting everything.
        let region = selection ?? Selection(bounds: canvas.bounds)
        return commitSingleShot("Invert colours") { canvas in
            canvas.map(region) { pixel in
                let (r, g, b, a) = pixel.unpremultiplied
                return PaintColour(
                    red: 1 - Double(r) / 255,
                    green: 1 - Double(g) / 255,
                    blue: 1 - Double(b) / 255,
                    alpha: Double(a) / 255
                ).rgba8
            }
            return region.bounds
        }
    }

    /// Replace the canvas wholesale (resize, flip, rotate), as one undoable edit.
    ///
    /// A size change used to clear the history outright, because a rect patch is
    /// addressed in canvas coordinates and restoring one into a differently-sized
    /// canvas puts pixels in the wrong places. It now records both canvases whole
    /// instead — so resizing, rotating by an arbitrary angle or cropping is
    /// undoable like everything else, and the work before it survives.
    public func replaceCanvas(with newCanvas: Bitmap, actionName: String) {
        let before = canvas
        let resized = newCanvas.width != canvas.width || newCanvas.height != canvas.height
        canvas = newCanvas

        if resized {
            // A selection or lasso path names coordinates that no longer mean
            // what they did; keeping them would draw a marquee over unrelated
            // pixels.
            selection = nil
            lassoPath = []
            recordResize(name: actionName, from: before)
        } else {
            recordEdit(name: actionName, before: before, dirty: canvas.bounds)
        }

        floating = nil
        gesture = .idle
    }

    /// Load a canvas and discard everything tied to the old one.
    ///
    /// Opening or reverting a document lands here: history is addressed in
    /// canvas coordinates, so replaying it against a different image would
    /// restore pixels into the wrong places.
    public func reset(to newCanvas: Bitmap) {
        canvas = newCanvas
        undoStack.removeAll()
        selection = nil
        lassoPath = []
        floating = nil
        gesture = .idle
    }

    // MARK: - Undo

    @discardableResult
    public func undo() -> PixelRect {
        _ = cancelStroke()
        let floatingDirty = discardFloating()
        guard let edit = undoStack.undo(on: &canvas) else { return floatingDirty }
        // A badge is a counter as well as some pixels. Undoing one hands its
        // number back, so the next stamp reuses it instead of skipping it.
        if let number = edit.badgeNumber { nextBadgeNumber = number }
        return edit.dirtyRect.union(floatingDirty)
    }

    @discardableResult
    public func redo() -> PixelRect {
        _ = cancelStroke()
        guard let edit = undoStack.redo(on: &canvas) else { return .empty }
        if let number = edit.badgeNumber { nextBadgeNumber = number + 1 }
        return edit.dirtyRect
    }

    // MARK: - Internals

    private func recordEdit(
        name: String, before: Bitmap, dirty: PixelRect, badgeNumber: Int? = nil
    ) {
        guard !dirty.isEmpty else { return }
        undoStack.record(
            PixelEdit(
                name: name,
                before: RectPatch(capturing: dirty, from: before),
                after: RectPatch(capturing: dirty, from: canvas),
                badgeNumber: badgeNumber
            ),
            canvasBytes: canvas.byteCount
        )
    }

    /// Record an edit that changed the canvas's size.
    ///
    /// Whole-canvas rather than a patch, because a patch is addressed in canvas
    /// coordinates and cannot describe an edit that moved every coordinate.
    private func recordResize(name: String, from before: Bitmap) {
        undoStack.record(
            PixelEdit.resizing(name, from: before, to: canvas),
            // The larger of the two, so shrinking to a thumbnail cannot budget
            // the history that still holds the full-size canvas as if it were
            // thumbnail-sized.
            canvasBytes: max(before.byteCount, canvas.byteCount)
        )
    }

    private func commitSingleShot(
        _ name: String, badgeNumber: Int? = nil, _ body: (inout Bitmap) -> PixelRect
    ) -> PixelRect {
        let before = canvas
        let dirty = body(&canvas)
        guard !dirty.isEmpty else { return .empty }
        recordEdit(name: name, before: before, dirty: dirty, badgeNumber: badgeNumber)
        return dirty
    }

    private func performReadOnly(_ tool: ToolKind, at point: PixelPoint) -> PixelRect {
        if tool == .eyedropper, let pixel = canvas.pixel(at: point) {
            let sampled = PaintColour(pixel)
            lastSampledColour = sampled
            colours.foreground = sampled
        }
        gesture = .idle
        return .empty
    }

    /// The colour a marking tool paints with. The eraser inverts the pairing:
    /// it lays down the *background* colour, which is what makes it read as
    /// "removing paint" on a white canvas.
    private func strokeColour(for button: PointerButton) -> PaintColour {
        settings.tool == .eraser
            ? colours.erasureColour(for: button)
            : colours.colour(for: button)
    }

    private func highlighterColour(for button: PointerButton) -> RGBA8 {
        // The tool's own colour when it has one, the pair when it does not — and
        // the right button still means "the other colour", so a right-drag with a
        // dedicated highlighter colour falls back to the pair rather than
        // silently highlighting in the same shade as a left-drag.
        var colour = if let own = settings.highlighterColour, button == .primary {
            own
        } else {
            colours.colour(for: button)
        }
        colour.alpha = settings.highlighterOpacity
        return colour.rgba8
    }

    // MARK: - Highlighter

    /// Highlighter strokes accumulate **coverage**, then composite once per
    /// frame from the pre-stroke snapshot.
    ///
    /// Compositing each stamp directly would darken every place the stroke
    /// overlaps itself — and a freehand stroke overlaps itself constantly,
    /// because consecutive mouse samples are a few pixels apart with a 20px
    /// nib. The result would be a stroke that gets muddier the slower you
    /// drag. Real highlighters do not do that, so neither does this one.
    private func stampHighlighter(
        at point: PixelPoint, into coverage: inout [UInt8], before: Bitmap, colour: RGBA8
    ) -> PixelRect {
        let dirty = stampHighlighterCoverage(at: point, into: &coverage)
        recomposite(dirty, coverage: coverage, before: before, colour: colour)
        return dirty
    }

    private func strokeHighlighter(
        from a: PixelPoint, to b: PixelPoint,
        into coverage: inout [UInt8], before: Bitmap, colour: RGBA8
    ) -> PixelRect {
        var dirty = PixelRect.empty
        var x = a.x, y = a.y
        let dx = abs(b.x - a.x)
        let dy = -abs(b.y - a.y)
        let sx = a.x < b.x ? 1 : -1
        let sy = a.y < b.y ? 1 : -1
        var err = dx + dy

        while true {
            dirty = dirty.union(
                stampHighlighterCoverage(at: PixelPoint(x: x, y: y), into: &coverage)
            )
            if x == b.x && y == b.y { break }
            let e2 = 2 * err
            if e2 >= dy { err += dy; x += sx }
            if e2 <= dx { err += dx; y += sy }
        }

        recomposite(dirty, coverage: coverage, before: before, colour: colour)
        return dirty
    }

    private func stampHighlighterCoverage(
        at point: PixelPoint, into coverage: inout [UInt8]
    ) -> PixelRect {
        let brush = activeBrush
        let extent = brush.extent
        var dirty = PixelRect.empty
        for dy in extent.minY..<extent.maxY {
            for dx in extent.minX..<extent.maxX {
                let value = brush.coverage(dx: dx, dy: dy)
                guard value > 0 else { continue }
                let p = PixelPoint(x: point.x + dx, y: point.y + dy)
                guard canvas.isInBounds(p) else { continue }
                let index = canvas.index(p)
                guard coverage[index] < value else { continue }
                coverage[index] = value
                dirty = dirty.union(PixelRect(x: p.x, y: p.y, width: 1, height: 1))
            }
        }
        return dirty
    }

    private func recomposite(
        _ rect: PixelRect, coverage: [UInt8], before: Bitmap, colour: RGBA8
    ) {
        guard !rect.isEmpty else { return }
        let region = rect.intersection(canvas.bounds)
        guard !region.isEmpty else { return }

        for y in region.minY..<region.maxY {
            for x in region.minX..<region.maxX {
                let index = y * canvas.width + x
                let value = coverage[index]
                guard value > 0 else { continue }
                canvas.pixels[index] = colour.withCoverage(value)
                    .overCompositing(before.pixels[index])
            }
        }
    }

    // MARK: - Shapes

    private func drawShape(from origin: PixelPoint, to end: PixelPoint, button: PointerButton) -> PixelRect {
        let stroke = colours.colour(for: button).rgba8
        let fill = colours.colour(for: button == .primary ? .secondary : .primary).rgba8
        let brush = activeBrush
        let style = settings.shapeStyle
        var dirty = PixelRect.empty

        switch settings.shapeKind {
        // A curve lays its chord first; bending it is the second gesture.
        case .line, .curve:
            dirty = Raster.strokeLine(
                from: origin, to: end, brush: brush, colour: stroke,
                into: &canvas, dash: settings.strokeDash
            )

        case .arrow:
            dirty = Raster.strokeArrow(
                from: origin, to: end, brush: brush, colour: stroke, into: &canvas
            )

        case .polygon:
            // Click-driven, handled by `addPolygonCorner`.
            break

        case .callout:
            dirty = drawCallout(
                PixelRect(corners: origin, end), brush: brush, stroke: stroke, fill: fill, style: style
            )

        case .triangle, .rightTriangle, .diamond, .pentagon, .hexagon, .star5, .star6:
            dirty = drawPolygonShape(
                settings.shapeKind.points(in: PixelRect(corners: origin, end)),
                stroke: stroke, fill: fill, closed: true
            )

        case .rectangle:
            let rect = PixelRect(corners: origin, end)
            if style.drawsFill {
                dirty = dirty.union(Raster.fillRect(rect.insetBy(brush.size), colour: fill, into: &canvas))
            }
            if style.drawsOutline {
                dirty = dirty.union(Raster.strokeRect(
                    rect, brush: brush, colour: stroke, into: &canvas, dash: settings.strokeDash
                ))
            }

        case .roundedRectangle:
            dirty = drawRoundedRectangle(
                PixelRect(corners: origin, end), brush: brush, stroke: stroke, fill: fill, style: style
            )

        case .ellipse:
            let rect = PixelRect(corners: origin, end)
            if style.drawsFill {
                dirty = dirty.union(Raster.fillEllipse(in: rect.insetBy(brush.size), colour: fill, into: &canvas))
            }
            if style.drawsOutline {
                dirty = dirty.union(Raster.strokeEllipse(
                    in: rect, brush: brush, colour: stroke, into: &canvas, dash: settings.strokeDash
                ))
            }
        }
        return dirty
    }

    /// Fill then outline a point list. Every regular shape — triangle through
    /// six-point star — comes through here, so they all gain fill, outline and
    /// stroke weight without their own rasteriser.
    @discardableResult
    private func drawPolygonShape(
        _ points: [PixelPoint], stroke: RGBA8, fill: RGBA8, closed: Bool
    ) -> PixelRect {
        guard points.count > 1 else { return .empty }
        let style = settings.shapeStyle
        var dirty = PixelRect.empty
        if style.drawsFill, points.count > 2, closed {
            dirty = dirty.union(Raster.fillPolygon(points, colour: fill, into: &canvas))
        }
        if style.drawsOutline || !closed || points.count < 3 {
            dirty = dirty.union(Raster.strokePolyline(
                points, brush: activeBrush, colour: stroke, closed: closed,
                into: &canvas, dash: settings.strokeDash
            ))
        }
        return dirty
    }

    /// A rounded box with a tail: the annotation shape that carries a sentence.
    ///
    /// The tail's mouth is left out of the outline rather than drawn over, so
    /// the bubble reads as one shape instead of a box with a triangle stuck to
    /// it.
    private func drawCallout(
        _ rect: PixelRect, brush: Brush, stroke: RGBA8, fill: RGBA8, style: ShapeStyle
    ) -> PixelRect {
        guard rect.width > 8, rect.height > 8 else { return .empty }
        let bodyHeight = max(4, Int(Double(rect.height) * 0.74))
        let body = PixelRect(x: rect.minX, y: rect.minY, width: rect.width, height: bodyHeight)
        let radius = min(settings.cornerRadius, min(body.width, body.height) / 2)

        let mouthLeft = PixelPoint(x: body.minX + max(radius, body.width / 5), y: body.maxY - 1)
        let mouthRight = PixelPoint(x: mouthLeft.x + max(6, body.width / 6), y: body.maxY - 1)
        let tip = PixelPoint(x: body.minX + max(2, body.width / 12), y: rect.maxY - 1)

        var dirty = PixelRect.empty
        if style.drawsFill {
            dirty = dirty.union(fillRoundedRectangle(body.insetBy(brush.size), radius: radius, colour: fill))
            dirty = dirty.union(Raster.fillPolygon([mouthLeft, mouthRight, tip], colour: fill, into: &canvas))
        }
        if style.drawsOutline {
            dirty = dirty.union(strokeRoundedRectangle(
                body, radius: radius, brush: brush, colour: stroke,
                skippingBottomBetween: (mouthLeft.x, mouthRight.x)
            ))
            for (a, b) in [(mouthLeft, tip), (tip, mouthRight)] {
                dirty = dirty.union(
                    Raster.strokeLine(from: a, to: b, brush: brush, colour: stroke, into: &canvas)
                )
            }
        }
        return dirty
    }

    /// Four quarter-ellipse corners joined by four straight runs, so its
    /// corners come from the same solver the ellipse uses and the two agree at
    /// matching radii.
    private func drawRoundedRectangle(
        _ rect: PixelRect, brush: Brush, stroke: RGBA8, fill: RGBA8, style: ShapeStyle
    ) -> PixelRect {
        guard !rect.isEmpty else { return .empty }
        let radius = min(settings.cornerRadius, min(rect.width, rect.height) / 2)
        var dirty = PixelRect.empty
        if style.drawsFill {
            dirty = dirty.union(fillRoundedRectangle(rect.insetBy(brush.size), radius: radius, colour: fill))
        }
        if style.drawsOutline {
            dirty = dirty.union(strokeRoundedRectangle(rect, radius: radius, brush: brush, colour: stroke))
        }
        return dirty
    }

    /// A cross of two rectangles plus four filled quadrants — the shape a
    /// rounded rectangle actually is, without a path rasteriser.
    private func fillRoundedRectangle(_ rect: PixelRect, radius: Int, colour: RGBA8) -> PixelRect {
        guard !rect.isEmpty else { return .empty }
        guard radius > 0 else { return Raster.fillRect(rect, colour: colour, into: &canvas) }
        let d = radius * 2
        var dirty = Raster.fillRect(
            PixelRect(x: rect.minX + radius, y: rect.minY, width: max(0, rect.width - d), height: rect.height),
            colour: colour, into: &canvas
        )
        dirty = dirty.union(Raster.fillRect(
            PixelRect(x: rect.minX, y: rect.minY + radius, width: rect.width, height: max(0, rect.height - d)),
            colour: colour, into: &canvas
        ))
        for corner in cornerRects(of: rect, radius: radius) {
            dirty = dirty.union(Raster.fillEllipse(
                in: corner.ellipse, colour: colour, into: &canvas, clip: corner.quadrant
            ))
        }
        return dirty
    }

    /// Four straight runs and four quarter arcs.
    ///
    /// `skippingBottomBetween` leaves a gap in the bottom run, which is how the
    /// speech bubble opens its mouth for the tail instead of drawing a line
    /// across it.
    private func strokeRoundedRectangle(
        _ rect: PixelRect,
        radius: Int,
        brush: Brush,
        colour: RGBA8,
        skippingBottomBetween gap: (Int, Int)? = nil
    ) -> PixelRect {
        guard !rect.isEmpty else { return .empty }
        guard radius > 0, gap == nil else {
            guard let gap else {
                return Raster.strokeRect(
                    rect, brush: brush, colour: colour, into: &canvas, dash: settings.strokeDash
                )
            }
            return strokeRoundedRuns(rect, radius: radius, brush: brush, colour: colour, gap: gap)
        }
        return strokeRoundedRuns(rect, radius: radius, brush: brush, colour: colour, gap: nil)
    }

    private func strokeRoundedRuns(
        _ rect: PixelRect, radius: Int, brush: Brush, colour: RGBA8, gap: (Int, Int)?
    ) -> PixelRect {
        let left = rect.minX, right = rect.maxX - 1
        let top = rect.minY, bottom = rect.maxY - 1
        var runs: [(PixelPoint, PixelPoint)] = [
            (PixelPoint(x: left + radius, y: top), PixelPoint(x: right - radius, y: top)),
            (PixelPoint(x: left, y: top + radius), PixelPoint(x: left, y: bottom - radius)),
            (PixelPoint(x: right, y: top + radius), PixelPoint(x: right, y: bottom - radius)),
        ]
        if let gap {
            runs.append((PixelPoint(x: left + radius, y: bottom), PixelPoint(x: gap.0, y: bottom)))
            runs.append((PixelPoint(x: gap.1, y: bottom), PixelPoint(x: right - radius, y: bottom)))
        } else {
            runs.append((PixelPoint(x: left + radius, y: bottom), PixelPoint(x: right - radius, y: bottom)))
        }

        var dirty = PixelRect.empty
        for (a, b) in runs where b.x >= a.x && b.y >= a.y {
            dirty = dirty.union(Raster.strokeLine(
                from: a, to: b, brush: brush, colour: colour,
                into: &canvas, dash: settings.strokeDash
            ))
        }
        for corner in cornerRects(of: rect, radius: radius) {
            // Clip to the quadrant. Without this the full inscribed circle
            // is drawn at every corner, leaving three stray arcs inside.
            dirty = dirty.union(Raster.strokeEllipse(
                in: corner.ellipse, brush: brush, colour: colour,
                into: &canvas, clip: corner.quadrant
            ))
        }
        return dirty
    }

    private func cornerRects(of rect: PixelRect, radius: Int) -> [(ellipse: PixelRect, quadrant: PixelRect)] {
        let d = radius * 2
        guard rect.width >= d, rect.height >= d, radius > 0 else { return [] }
        let r = radius
        return [
            (PixelRect(x: rect.minX, y: rect.minY, width: d, height: d),
             PixelRect(x: rect.minX, y: rect.minY, width: r, height: r)),
            (PixelRect(x: rect.maxX - d, y: rect.minY, width: d, height: d),
             PixelRect(x: rect.maxX - r, y: rect.minY, width: r, height: r)),
            (PixelRect(x: rect.minX, y: rect.maxY - d, width: d, height: d),
             PixelRect(x: rect.minX, y: rect.maxY - r, width: r, height: r)),
            (PixelRect(x: rect.maxX - d, y: rect.maxY - d, width: d, height: d),
             PixelRect(x: rect.maxX - r, y: rect.maxY - r, width: r, height: r)),
        ]
    }

    /// Shift-constrain: lines snap to 45° increments, boxes and ellipses to
    /// squares and circles, marquees to squares.
    /// Round to the nearest intersection of the alignment grid.
    ///
    /// **Only where alignment is the point.** A shape's corners, a marquee's
    /// corners and floating content's origin snap; a brush, a pencil, a
    /// highlighter and an eraser never do — a freehand stroke that jumped to a
    /// grid would not be freehand, and there is no version of that anyone wants.
    ///
    /// Clamped to the canvas afterwards, so snapping near an edge cannot round a
    /// point off the picture.
    func snapped(_ point: PixelPoint) -> PixelPoint {
        let grid = settings.snapGrid
        guard grid > 1 else { return point }
        func round(_ v: Int, _ limit: Int) -> Int {
            let snapped = Int((Double(v) / Double(grid)).rounded()) * grid
            return min(max(0, snapped), limit)
        }
        return PixelPoint(x: round(point.x, canvas.width), y: round(point.y, canvas.height))
    }

    /// Snap the far corner of a drag so the region's **edges** land on grid
    /// lines, rather than its corner pixels.
    ///
    /// `PixelRect(corners:)` is inclusive — a box from 16 to 112 is 97 wide, not
    /// 96 — so snapping both corners to multiples of the grid produces sizes of
    /// `n x grid + 1`, and two boxes drawn one under the other overlap by a
    /// row. Alignment would look right and tiling would be quietly off by one,
    /// which is exactly the kind of nearly-correct that makes a snap feature
    /// feel broken.
    ///
    /// So the *exclusive* edge is what snaps: dragging right or down, the last
    /// included pixel is one short of the grid line, and the next box starting
    /// on that line abuts it exactly.
    func snappedEnd(_ point: PixelPoint, from origin: PixelPoint) -> PixelPoint {
        let grid = settings.snapGrid
        guard grid > 1 else { return point }
        func edge(_ value: Int, _ start: Int, _ limit: Int) -> Int {
            if value >= start {
                let line = Int((Double(value + 1) / Double(grid)).rounded()) * grid
                return min(max(start, line - 1), limit - 1)
            }
            let line = Int((Double(value) / Double(grid)).rounded()) * grid
            return min(max(0, line), start)
        }
        return PixelPoint(
            x: edge(point.x, origin.x, canvas.width),
            y: edge(point.y, origin.y, canvas.height)
        )
    }

    private func constrain(_ origin: PixelPoint, to point: PixelPoint) -> PixelPoint {
        let dx = point.x - origin.x
        let dy = point.y - origin.y

        if settings.tool == .shape, !settings.shapeKind.isClosed {
            let adx = abs(dx), ady = abs(dy)
            if ady * 5 < adx * 2 { return PixelPoint(x: point.x, y: origin.y) }
            if adx * 5 < ady * 2 { return PixelPoint(x: origin.x, y: point.y) }
            let side = max(adx, ady)
            return PixelPoint(
                x: origin.x + (dx < 0 ? -side : side),
                y: origin.y + (dy < 0 ? -side : side)
            )
        }

        let side = max(abs(dx), abs(dy))
        return PixelPoint(
            x: origin.x + (dx < 0 ? -side : side),
            y: origin.y + (dy < 0 ? -side : side)
        )
    }
}
