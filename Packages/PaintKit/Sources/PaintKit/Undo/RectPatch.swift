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

    /// Whole-canvas snapshots, for the edits that change the canvas's **size**.
    ///
    /// A rect patch is addressed in canvas coordinates, so it cannot describe an
    /// edit that moves every coordinate — restoring one into a differently-sized
    /// canvas puts pixels in the wrong places. That is why a resize used to wipe
    /// the history outright.
    ///
    /// Pasting now grows the canvas, and paste is far too common an operation to
    /// leave `⌘Z` doing nothing. So a size change carries both canvases whole.
    /// The per-stroke cost this file exists to avoid is not incurred: this is
    /// only ever populated for resizes, which are rare, and the byte budget
    /// accounts for it like anything else.
    public let resize: Resize?

    public struct Resize: Equatable, Sendable {
        public let before: Bitmap
        public let after: Bitmap

        public init(before: Bitmap, after: Bitmap) {
            self.before = before
            self.after = after
        }

        var byteCount: Int {
            (before.width * before.height + after.width * after.height)
                * MemoryLayout<RGBA8>.stride
        }
    }

    /// The step number this edit consumed, if it was a badge.
    ///
    /// **The one piece of non-pixel state an edit carries.** The badge tool is a
    /// counter, and restoring pixels is not enough to reverse it: undoing a badge
    /// put the artwork back and left the counter advanced, so the next stamp
    /// skipped a number and the sequence you could see on the canvas stopped
    /// matching the one the tool was about to continue.
    ///
    /// Recorded here rather than recomputed from the stack because
    /// `trimToBudget` drops the oldest edits — a count of surviving badge edits
    /// would silently reset the sequence on a long session, renumbering badges
    /// that are still on screen.
    public let badgeNumber: Int?

    public init(
        name: String, before: RectPatch, after: RectPatch,
        resize: Resize? = nil, badgeNumber: Int? = nil
    ) {
        self.name = name
        self.before = before
        self.after = after
        self.resize = resize
        self.badgeNumber = badgeNumber
    }

    /// An edit that replaces the whole canvas, size and all.
    public static func resizing(_ name: String, from before: Bitmap, to after: Bitmap) -> PixelEdit {
        PixelEdit(
            name: name,
            before: RectPatch(rect: .empty, pixels: []),
            after: RectPatch(rect: .empty, pixels: []),
            resize: Resize(before: before, after: after)
        )
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

    public var byteCount: Int {
        before.byteCount + after.byteCount + (resize?.byteCount ?? 0)
    }

    /// The area a caller has to repaint after undoing or redoing this edit.
    ///
    /// **Not `before.rect`.** A resize edit carries whole canvases and leaves
    /// both patches empty, so reading the patch rect reported *nothing* dirty —
    /// which meant undoing a resize swapped the canvas underneath a view that
    /// never repainted, and never told anyone the size had changed either. The
    /// union of both canvases covers the shrink and the grow directions alike.
    public var dirtyRect: PixelRect {
        guard let resize else { return before.rect }
        return resize.before.bounds.union(resize.after.bounds)
    }

    public func undo(on bitmap: inout Bitmap) {
        if let resize { bitmap = resize.before } else { before.apply(to: &bitmap) }
    }

    public func redo(on bitmap: inout Bitmap) {
        if let resize { bitmap = resize.after } else { after.apply(to: &bitmap) }
    }
}
