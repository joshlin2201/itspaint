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

    public enum Handle: CaseIterable, Sendable {
        case topLeft, top, topRight
        case left, right
        case bottomLeft, bottom, bottomRight

        /// Which edges this handle moves.
        var movesLeft: Bool { self == .topLeft || self == .left || self == .bottomLeft }
        var movesRight: Bool { self == .topRight || self == .right || self == .bottomRight }
        var movesTop: Bool { self == .topLeft || self == .top || self == .topRight }
        var movesBottom: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }
    }

    /// Handle centres in canvas coordinates, in a fixed order.
    ///
    /// An array rather than a dictionary: this is walked on every hit test —
    /// twice per mouse-moved event — and a dictionary both allocated each time
    /// and left ties between two equidistant handles to hash order, so which
    /// one you grabbed could differ between runs.
    public func handleCentres() -> [(handle: Handle, centre: PixelPoint)] {
        let midX = frame.minX + frame.width / 2
        let midY = frame.minY + frame.height / 2
        let maxX = frame.maxX - 1
        let maxY = frame.maxY - 1
        return [
            (.topLeft, PixelPoint(x: frame.minX, y: frame.minY)),
            (.top, PixelPoint(x: midX, y: frame.minY)),
            (.topRight, PixelPoint(x: maxX, y: frame.minY)),
            (.left, PixelPoint(x: frame.minX, y: midY)),
            (.right, PixelPoint(x: maxX, y: midY)),
            (.bottomLeft, PixelPoint(x: frame.minX, y: maxY)),
            (.bottom, PixelPoint(x: midX, y: maxY)),
            (.bottomRight, PixelPoint(x: maxX, y: maxY)),
        ]
    }

    /// The handle under `point`, within `tolerance` canvas pixels.
    ///
    /// Tolerance is supplied by the view in canvas units so the grab area stays
    /// a constant *on-screen* size at any zoom — a handle that shrinks to a
    /// subpixel target at 25% would be unusable.
    ///
    /// It is then capped at a third of the shorter side. Without that cap the
    /// handles of a small selection overlap in the middle and swallow it
    /// entirely: every click lands on a handle, and the content can be resized
    /// but never moved.
    public func handle(at point: PixelPoint, tolerance: Int) -> Handle? {
        let limit = max(1, min(frame.width, frame.height) / 3)
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

    /// Frame produced by dragging `handle` to `point`.
    ///
    /// Edges are clamped so they can never cross: dragging the left edge past
    /// the right one keeps a 1px sliver rather than inverting the content.
    public func frame(draggingHandle handle: Handle, to point: PixelPoint, uniform: Bool) -> PixelRect {
        var minX = frame.minX
        var minY = frame.minY
        var maxX = frame.maxX
        var maxY = frame.maxY

        if handle.movesLeft { minX = min(point.x, maxX - 1) }
        if handle.movesRight { maxX = max(point.x + 1, minX + 1) }
        if handle.movesTop { minY = min(point.y, maxY - 1) }
        if handle.movesBottom { maxY = max(point.y + 1, minY + 1) }

        var result = PixelRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

        if uniform, frame.width > 0, frame.height > 0 {
            // Preserve the original aspect ratio, driven by whichever axis the
            // user pulled further.
            let aspect = Double(frame.width) / Double(frame.height)
            let byWidth = Double(result.width) / Double(frame.width)
            let byHeight = Double(result.height) / Double(frame.height)
            let scale = max(byWidth, byHeight)
            let width = max(1, Int((Double(frame.width) * scale).rounded()))
            let height = max(1, Int((Double(width) / aspect).rounded()))

            result = PixelRect(
                x: handle.movesLeft ? maxX - width : minX,
                y: handle.movesTop ? maxY - height : minY,
                width: width,
                height: height
            )
        }
        return result
    }
}
