import Foundation

/// The pixels of one rectangular region, captured before an edit.
///
/// This is the whole undo strategy, and the choice is deliberate. The obvious
/// implementation — snapshot the entire canvas per operation — costs
/// `width × height × 4` bytes *every stroke*: 64 MB per undo step on a
/// 4000×4000 canvas, which exhausts memory after a few dozen strokes and stalls
/// on each one. A rect patch costs only the area the tool actually touched, so
/// a small stroke on a huge canvas is a few kilobytes. Tiling the canvas would
/// shave a little more off pathological cases; it is not worth the complexity
/// until a profile says otherwise.
public struct RectPatch: Equatable, Sendable {
    public let rect: PixelRect
    public let pixels: [RGBA8]

    public init(rect: PixelRect, pixels: [RGBA8]) {
        self.rect = rect
        self.pixels = pixels
    }

    /// Capture the current contents of `rect`.
    public init(capturing rect: PixelRect, from bitmap: Bitmap) {
        let extracted = bitmap.extract(rect)
        self.rect = extracted.rect
        self.pixels = extracted.pixels
    }

    public var isEmpty: Bool { rect.isEmpty }

    /// Approximate heap cost, used to bound the undo stack.
    public var byteCount: Int { pixels.count * MemoryLayout<RGBA8>.stride }

    public func apply(to bitmap: inout Bitmap) {
        guard !isEmpty else { return }
        bitmap.restore(pixels, to: rect)
    }
}

/// One reversible edit: what the canvas looked like before, and after.
public struct PixelEdit: Equatable, Sendable {
    public let name: String
    public let before: RectPatch
    public let after: RectPatch

    public init(name: String, before: RectPatch, after: RectPatch) {
        self.name = name
        self.before = before
        self.after = after
    }

    /// Capture an edit by running `body` and diffing only the rect it reports
    /// as dirty. The tool tells us what it touched; we never scan the canvas.
    public static func record(
        _ name: String,
        on bitmap: inout Bitmap,
        _ body: (inout Bitmap) -> PixelRect
    ) -> PixelEdit? {
        // Snapshot lazily: capture a generous region only once the operation
        // has told us where it landed. Bitmap is copy-on-write, so holding
        // `original` costs nothing until `body` writes.
        let original = bitmap
        let dirty = body(&bitmap)
        guard !dirty.isEmpty else { return nil }
        return PixelEdit(
            name: name,
            before: RectPatch(capturing: dirty, from: original),
            after: RectPatch(capturing: dirty, from: bitmap)
        )
    }

    public var byteCount: Int { before.byteCount + after.byteCount }

    public func undo(on bitmap: inout Bitmap) { before.apply(to: &bitmap) }
    public func redo(on bitmap: inout Bitmap) { after.apply(to: &bitmap) }
}
