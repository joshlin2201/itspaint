import Foundation

/// Content lifted off the canvas, or pasted onto it, that is not yet committed.
///
/// A floating selection is the mechanism behind cut, copy, paste, move and
/// resize. It deliberately lives *beside* the canvas rather than inside it:
/// while it floats, the pixels underneath are untouched, so moving it around
/// costs nothing and cancelling leaves no trace. Only `commit` writes it down.
///
/// It keeps the **original** pixels and re-renders when resized, so scaling
/// down and back up again does not accumulate resampling loss the way
/// repeatedly scaling the displayed copy would.
public struct FloatingSelection: Equatable, Sendable {
    /// The source pixels at their original resolution.
    public let original: Bitmap
    /// Where the content sits and how big it currently is.
    public private(set) var frame: PixelRect
    /// `original` rendered at `frame`'s size. Cached — moving does not rebuild it.
    public private(set) var rendered: Bitmap
    /// Resampling used when the frame is resized.
    public var scaling: ImageTransform.Scaling

    public init(
        bitmap: Bitmap,
        origin: PixelPoint,
        scaling: ImageTransform.Scaling = .smooth
    ) {
        self.original = bitmap
        self.rendered = bitmap
        self.frame = PixelRect(
            x: origin.x, y: origin.y, width: bitmap.width, height: bitmap.height
        )
        self.scaling = scaling
    }

    public var origin: PixelPoint { PixelPoint(x: frame.minX, y: frame.minY) }

    /// The pixels to draw and to commit.
    public var bitmap: Bitmap { rendered }

    public func contains(_ point: PixelPoint) -> Bool { frame.contains(point) }

    /// Move without resizing — never re-renders.
    public mutating func move(to origin: PixelPoint) {
        frame = PixelRect(x: origin.x, y: origin.y, width: frame.width, height: frame.height)
    }

    public mutating func offset(by delta: (dx: Int, dy: Int)) {
        move(to: PixelPoint(x: frame.minX + delta.dx, y: frame.minY + delta.dy))
    }

    public func moved(by delta: (dx: Int, dy: Int)) -> FloatingSelection {
        var copy = self
        copy.offset(by: delta)
        return copy
    }

    /// Resize, re-rendering from `original` only when the size actually changes.
    public mutating func resize(to newFrame: PixelRect) {
        let clamped = PixelRect(
            x: newFrame.minX, y: newFrame.minY,
            width: max(1, newFrame.width), height: max(1, newFrame.height)
        )
        guard clamped != frame else { return }
        let sizeChanged = clamped.width != frame.width || clamped.height != frame.height
        frame = clamped
        guard sizeChanged else { return }
        rendered = ImageTransform.scaled(
            original, to: (clamped.width, clamped.height), using: scaling
        ) ?? original
    }

    // MARK: - Resize handles

    /// Resize handles live on `PixelRect`, because a floating selection is not
    /// the only thing that gets dragged by its corners — the text box does too,
    /// and two implementations of "which handle is under this point" is two
    /// places for the grab tolerance to disagree.
    public typealias Handle = PixelRect.Handle

    public func handleCentres() -> [(handle: Handle, centre: PixelPoint)] {
        frame.handleCentres()
    }

    public func handle(at point: PixelPoint, tolerance: Int) -> Handle? {
        frame.handle(at: point, tolerance: tolerance)
    }

    public func frame(draggingHandle handle: Handle, to point: PixelPoint, uniform: Bool) -> PixelRect {
        frame.dragging(handle, to: point, uniform: uniform)
    }
}

// MARK: - Handles on any rectangle

extension PixelRect {

    public enum Handle: CaseIterable, Sendable {
        case topLeft, top, topRight
        case left, right
        case bottomLeft, bottom, bottomRight

        /// Which edges this handle moves.
        public var movesLeft: Bool { self == .topLeft || self == .left || self == .bottomLeft }
        public var movesRight: Bool { self == .topRight || self == .right || self == .bottomRight }
        public var movesTop: Bool { self == .topLeft || self == .top || self == .topRight }
        public var movesBottom: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }
    }

    /// Handle centres in canvas coordinates, in a fixed order.
    ///
    /// An array rather than a dictionary: this is walked on every hit test —
    /// twice per mouse-moved event — and a dictionary both allocated each time
    /// and left ties between two equidistant handles to hash order, so which
    /// one you grabbed could differ between runs.
    public func handleCentres() -> [(handle: Handle, centre: PixelPoint)] {
        let midX = minX + width / 2
        let midY = minY + height / 2
        let farX = maxX - 1
        let farY = maxY - 1
        return [
            (.topLeft, PixelPoint(x: minX, y: minY)),
            (.top, PixelPoint(x: midX, y: minY)),
            (.topRight, PixelPoint(x: farX, y: minY)),
            (.left, PixelPoint(x: minX, y: midY)),
            (.right, PixelPoint(x: farX, y: midY)),
            (.bottomLeft, PixelPoint(x: minX, y: farY)),
            (.bottom, PixelPoint(x: midX, y: farY)),
            (.bottomRight, PixelPoint(x: farX, y: farY)),
        ]
    }

    /// The handle under `point`, within `tolerance` canvas pixels.
    ///
    /// Tolerance is supplied by the view in canvas units so the grab area stays
    /// a constant *on-screen* size at any zoom — a handle that shrinks to a
    /// subpixel target at 25% would be unusable.
    ///
    /// It is then capped at a third of the shorter side. Without that cap the
    /// handles of a small rectangle overlap in the middle and swallow it
    /// entirely: every click lands on a handle, and the content can be resized
    /// but never moved.
    public func handle(at point: PixelPoint, tolerance: Int) -> Handle? {
        let limit = max(1, min(width, height) / 3)
        let effective = min(tolerance, limit)

        var best: (handle: Handle, distance: Int)?
        for (handle, centre) in handleCentres() {
            let dx = abs(centre.x - point.x)
            let dy = abs(centre.y - point.y)
            guard dx <= effective, dy <= effective else { continue }
            let distance = dx * dx + dy * dy
            if best == nil || distance < best!.distance {
                best = (handle, distance)
            }
        }
        return best?.handle
    }

    /// The rectangle produced by dragging `handle` to `point`.
    ///
    /// Edges are clamped so they can never cross: dragging the left edge past
    /// the right one keeps a 1px sliver rather than inverting the content.
    public func dragging(_ handle: Handle, to point: PixelPoint, uniform: Bool) -> PixelRect {
        var left = minX
        var top = minY
        var right = maxX
        var bottom = maxY

        if handle.movesLeft { left = min(point.x, right - 1) }
        if handle.movesRight { right = max(point.x + 1, left + 1) }
        if handle.movesTop { top = min(point.y, bottom - 1) }
        if handle.movesBottom { bottom = max(point.y + 1, top + 1) }

        var result = PixelRect(x: left, y: top, width: right - left, height: bottom - top)

        if uniform, width > 0, height > 0 {
            // Preserve the original aspect ratio, driven by whichever axis the
            // user pulled further.
            let aspect = Double(width) / Double(height)
            let byWidth = Double(result.width) / Double(width)
            let byHeight = Double(result.height) / Double(height)
            let scale = max(byWidth, byHeight)
            let newWidth = max(1, Int((Double(width) * scale).rounded()))
            let newHeight = max(1, Int((Double(newWidth) / aspect).rounded()))

            result = PixelRect(
                x: handle.movesLeft ? right - newWidth : left,
                y: handle.movesTop ? bottom - newHeight : top,
                width: newWidth,
                height: newHeight
            )
        }
        return result
    }
}
