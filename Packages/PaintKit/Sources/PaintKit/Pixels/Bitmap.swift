import Foundation

/// A mutable RGBA8 premultiplied sRGB raster.
///
/// This is a `struct` backed by a Swift `Array`, which buys copy-on-write for
/// free: taking an undo snapshot is O(1) until something actually writes. Tools
/// still capture *rect-scoped* patches rather than whole frames (see
/// `RectPatch`), because a full-frame copy on every stroke is what makes naive
/// paint apps stutter on large canvases.
public struct Bitmap: Equatable, Sendable {
    /// Largest single image dimension accepted by the editor.
    ///
    /// This is intentionally a little above 8K so current high-resolution
    /// screenshots remain useful, while malformed headers cannot ask the app
    /// to reserve an effectively unbounded raster.
    public static let maximumDimension = 20_000

    /// Largest decoded or generated raster accepted by the editor.
    ///
    /// 33,554,432 RGBA8 pixels are 128 MiB before undo or rendering overhead.
    /// The limit includes a full 8K UHD frame (7,680 × 4,320).
    public static let maximumPixelCount = 33_554_432

    /// The single size gate for imported, generated, and transformed rasters.
    ///
    /// In addition to the public limits, this checks every storage
    /// multiplication so callers can reject hostile dimensions without
    /// triggering an integer trap.
    public static func isSizeSupported(width: Int, height: Int) -> Bool {
        guard width > 0, height > 0,
              width <= maximumDimension, height <= maximumDimension
        else { return false }

        let (pixelCount, pixelOverflow) = width.multipliedReportingOverflow(by: height)
        guard !pixelOverflow, pixelCount <= maximumPixelCount else { return false }

        let stride = MemoryLayout<RGBA8>.stride
        let (rowBytes, rowOverflow) = width.multipliedReportingOverflow(by: stride)
        guard !rowOverflow else { return false }
        let (_, byteOverflow) = rowBytes.multipliedReportingOverflow(by: height)
        return !byteOverflow
    }

    public let width: Int
    public let height: Int
    /// Writable inside PaintKit (rasterisers need raw index access) but
    /// read-only to consumers, who must go through the mutating methods below.
    public internal(set) var pixels: [RGBA8]

    public init(width: Int, height: Int, fill: RGBA8 = .white) {
        precondition(
            Self.isSizeSupported(width: width, height: height),
            "Bitmap dimensions exceed the supported storage budget"
        )
        let (pixelCount, overflow) = width.multipliedReportingOverflow(by: height)
        precondition(!overflow, "Bitmap pixel count overflowed")
        self.width = width
        self.height = height
        self.pixels = [RGBA8](repeating: fill, count: pixelCount)
    }

    public init?(width: Int, height: Int, pixels: [RGBA8]) {
        guard Self.isSizeSupported(width: width, height: height) else { return nil }
        let (pixelCount, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow, pixels.count == pixelCount else { return nil }
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    @inlinable public var bounds: PixelRect { PixelRect(x: 0, y: 0, width: width, height: height) }
    @inlinable public var count: Int { pixels.count }

    @inlinable
    public func isInBounds(_ p: PixelPoint) -> Bool {
        p.x >= 0 && p.x < width && p.y >= 0 && p.y < height
    }

    @inlinable
    public func index(_ p: PixelPoint) -> Int { p.y * width + p.x }

    // MARK: - Reading

    /// Pixel at `p`, or `nil` when out of bounds. Prefer this at tool
    /// boundaries; use `unsafePixel` only inside a bounds-checked loop.
    @inlinable
    public func pixel(at p: PixelPoint) -> RGBA8? {
        guard isInBounds(p) else { return nil }
        return pixels[index(p)]
    }

    @inlinable
    public func unsafePixel(at p: PixelPoint) -> RGBA8 { pixels[index(p)] }

    /// Copy the pixels inside `rect` (clipped to bounds) into a flat array.
    ///
    /// Row-wise bulk copies rather than element-wise appends. This sits in the
    /// live shape-preview loop — every preview frame captures and restores the
    /// region it is about to redraw — so a per-element copy here is felt
    /// directly as drag latency on a large shape.
    public func extract(_ rect: PixelRect) -> (rect: PixelRect, pixels: [RGBA8]) {
        let clipped = rect.intersection(bounds)
        guard !clipped.isEmpty else { return (.empty, []) }

        let (patchCount, overflow) = clipped.width.multipliedReportingOverflow(by: clipped.height)
        guard !overflow else { return (.empty, []) }
        let out = [RGBA8](unsafeUninitializedCapacity: patchCount) { buffer, count in
            pixels.withUnsafeBufferPointer { source in
                for row in 0..<clipped.height {
                    let sourceStart = (clipped.minY + row) * width + clipped.minX
                    buffer.baseAddress!.advanced(by: row * clipped.width)
                        .update(from: source.baseAddress! + sourceStart, count: clipped.width)
                }
            }
            count = patchCount
        }
        return (clipped, out)
    }

    // MARK: - Writing

    /// Replace the pixel at `p`, ignoring out-of-bounds writes.
    public mutating func setPixel(_ colour: RGBA8, at p: PixelPoint) {
        guard isInBounds(p) else { return }
        pixels[index(p)] = colour
    }

    /// Write a previously extracted patch back at `rect`'s origin. Used by undo
    /// and by every live shape-preview frame, so it copies whole rows.
    public mutating func restore(_ patch: [RGBA8], to rect: PixelRect) {
        let clipped = rect.intersection(bounds)
        guard !clipped.isEmpty, patch.count == rect.area else { return }
        let canvasWidth = width
        // Offsets into the patch when `rect` hangs off the canvas edge. Reading
        // from row 0 / column 0 in that case would shift the restored pixels.
        let patchColumnOffset = clipped.minX - rect.minX
        let patchRowOffset = clipped.minY - rect.minY

        patch.withUnsafeBufferPointer { source in
            pixels.withUnsafeMutableBufferPointer { destination in
                for row in 0..<clipped.height {
                    let sourceStart = (patchRowOffset + row) * rect.width + patchColumnOffset
                    let destinationStart = (clipped.minY + row) * canvasWidth + clipped.minX
                    destination.baseAddress!.advanced(by: destinationStart)
                        .update(from: source.baseAddress! + sourceStart, count: clipped.width)
                }
            }
        }
    }

    /// Fill `rect` with a solid colour, replacing (not blending).
    ///
    /// One `update(repeating:)` per row — a memset — rather than a bounds-checked
    /// write per pixel. Every solid shape, every marquee backfill and every
    /// Clear Image lands here.
    public mutating func fill(_ rect: PixelRect, with colour: RGBA8) {
        let clipped = rect.intersection(bounds)
        guard !clipped.isEmpty else { return }
        let canvasWidth = width
        pixels.withUnsafeMutableBufferPointer { buffer in
            for row in clipped.minY..<clipped.maxY {
                let start = row * canvasWidth + clipped.minX
                UnsafeMutableBufferPointer(rebasing: buffer[start..<(start + clipped.width)])
                    .update(repeating: colour)
            }
        }
    }

    /// Source-over composite a solid colour across `rect`.
    public mutating func blend(_ rect: PixelRect, with colour: RGBA8) {
        if colour.a == 255 { return fill(rect, with: colour) }
        let clipped = rect.intersection(bounds)
        guard !clipped.isEmpty, colour.a > 0 else { return }
        for row in clipped.minY..<clipped.maxY {
            let start = row * width + clipped.minX
            for i in start..<(start + clipped.width) {
                pixels[i] = colour.overCompositing(pixels[i])
            }
        }
    }

    public mutating func fillAll(with colour: RGBA8) {
        pixels = [RGBA8](repeating: colour, count: count)
    }

    /// In-place per-pixel transform over `rect`. The single entry point for
    /// Invert Colours and friends so they cannot each re-derive bounds logic.
    public mutating func map(_ rect: PixelRect, _ transform: (RGBA8) -> RGBA8) {
        let clipped = rect.intersection(bounds)
        guard !clipped.isEmpty else { return }
        for row in clipped.minY..<clipped.maxY {
            let start = row * width + clipped.minX
            for i in start..<(start + clipped.width) {
                pixels[i] = transform(pixels[i])
            }
        }
    }

    /// Draw `other` onto this bitmap at `origin` using source-over.
    public mutating func composite(_ other: Bitmap, at origin: PixelPoint) {
        let target = PixelRect(x: origin.x, y: origin.y, width: other.width, height: other.height)
            .intersection(bounds)
        guard !target.isEmpty else { return }
        for row in target.minY..<target.maxY {
            let srcRow = row - origin.y
            for col in target.minX..<target.maxX {
                let src = other.pixels[srcRow * other.width + (col - origin.x)]
                guard src.a > 0 else { continue }
                let i = row * width + col
                pixels[i] = src.overCompositing(pixels[i])
            }
        }
    }
}
