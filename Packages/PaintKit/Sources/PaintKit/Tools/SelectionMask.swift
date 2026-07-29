import Foundation

/// A selected region: a bounding box, plus an optional per-pixel mask.
///
/// A rectangular marquee carries no mask — `nil` means "the whole bounds", which
/// keeps the common case free of a megabyte of coverage bytes. The lasso fills
/// one in. Everything downstream (cut, copy, delete, crop, invert, floating
/// content) reads through the same type, so a freeform selection is not a second
/// code path that can drift from the rectangular one.
public struct Selection: Equatable, Sendable {
    public let bounds: PixelRect
    /// Row-major coverage over `bounds`, or `nil` for a plain rectangle.
    public let mask: [UInt8]?

    public init(bounds: PixelRect, mask: [UInt8]? = nil) {
        self.bounds = bounds
        self.mask = mask?.count == bounds.area ? mask : nil
    }

    /// An elliptical marquee inscribed in `rect`.
    ///
    /// A mask rather than a second kind of bounds: everything downstream — cut,
    /// crop, invert, floating content — already reads coverage, so an ellipse
    /// costs one initialiser instead of a parallel code path.
    public init?(ellipseIn rect: PixelRect, clippedTo bounds: PixelRect) {
        let clipped = rect.intersection(bounds)
        guard clipped.width > 1, clipped.height > 1 else { return nil }

        let rx = Double(rect.width) / 2, ry = Double(rect.height) / 2
        let cx = Double(rect.minX) + rx, cy = Double(rect.minY) + ry
        var mask = [UInt8](repeating: 0, count: clipped.area)
        for y in 0..<clipped.height {
            let dy = (Double(clipped.minY + y) + 0.5 - cy) / ry
            for x in 0..<clipped.width {
                let dx = (Double(clipped.minX + x) + 0.5 - cx) / rx
                if dx * dx + dy * dy <= 1 { mask[y * clipped.width + x] = 255 }
            }
        }
        guard mask.contains(255) else { return nil }
        self.init(bounds: clipped, mask: mask)
    }

    public var isEmpty: Bool { bounds.isEmpty }
    public var isRectangular: Bool { mask == nil }

    /// Coverage at a canvas point: 0 outside, 255 fully inside.
    public func coverage(at point: PixelPoint) -> UInt8 {
        guard bounds.contains(point) else { return 0 }
        guard let mask else { return 255 }
        let index = (point.y - bounds.minY) * bounds.width + (point.x - bounds.minX)
        return mask[index]
    }

    public func contains(_ point: PixelPoint) -> Bool { coverage(at: point) > 0 }

    /// Shrink `bounds` to the mask's actual extent.
    ///
    /// An inverted selection starts as a full-canvas mask; without this its
    /// reported size is the whole canvas no matter how small the selected
    /// region really is, and the status bar lies.
    public func tightened() -> Selection {
        guard let mask else { return self }
        var minX = bounds.maxX, maxX = bounds.minX
        var minY = bounds.maxY, maxY = bounds.minY

        for y in 0..<bounds.height {
            let row = y * bounds.width
            for x in 0..<bounds.width where mask[row + x] > 0 {
                if x < minX - bounds.minX { minX = bounds.minX + x }
                if x > maxX - bounds.minX { maxX = bounds.minX + x }
                if y < minY - bounds.minY { minY = bounds.minY + y }
                if y > maxY - bounds.minY { maxY = bounds.minY + y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return self }

        let tight = PixelRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        guard tight != bounds else { return self }

        var trimmed = [UInt8](repeating: 0, count: tight.area)
        for y in 0..<tight.height {
            let source = (tight.minY - bounds.minY + y) * bounds.width + (tight.minX - bounds.minX)
            let destination = y * tight.width
            for x in 0..<tight.width {
                trimmed[destination + x] = mask[source + x]
            }
        }
        // A mask that turned out to be a solid rectangle is just a rectangle.
        return Selection(bounds: tight, mask: trimmed.allSatisfy { $0 == 255 } ? nil : trimmed)
    }

    /// Build a freeform selection from a closed polyline.
    ///
    /// Uses the same even-odd scanline solver as `Raster.fillPolygon`, so the
    /// pixels a lasso selects are exactly the pixels a filled polygon of the
    /// same outline would cover. Two different answers to "what is inside this
    /// shape" is how selection and fill drift apart.
    public init?(freeform points: [PixelPoint], clippedTo canvas: PixelRect) {
        guard points.count >= 3 else { return nil }
        let minX = max(canvas.minX, points.map(\.x).min() ?? 0)
        let maxX = min(canvas.maxX - 1, points.map(\.x).max() ?? 0)
        let minY = max(canvas.minY, points.map(\.y).min() ?? 0)
        let maxY = min(canvas.maxY - 1, points.map(\.y).max() ?? 0)
        guard maxX >= minX, maxY >= minY else { return nil }

        let box = PixelRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        var coverage = [UInt8](repeating: 0, count: box.area)

        for y in box.minY..<box.maxY {
            let scan = Double(y) + 0.5
            var crossings: [Double] = []
            for i in 0..<points.count {
                let a = points[i]
                let b = points[(i + 1) % points.count]
                let ay = Double(a.y), by = Double(b.y)
                guard (ay <= scan && by > scan) || (by <= scan && ay > scan) else { continue }
                let t = (scan - ay) / (by - ay)
                crossings.append(Double(a.x) + t * Double(b.x - a.x))
            }
            crossings.sort()

            var i = 0
            while i + 1 < crossings.count {
                let from = max(box.minX, Int(crossings[i].rounded()))
                let to = min(box.maxX, Int(crossings[i + 1].rounded()))
                if to > from {
                    let row = (y - box.minY) * box.width
                    for x in from..<to {
                        coverage[row + (x - box.minX)] = 255
                    }
                }
                i += 2
            }
        }

        guard coverage.contains(255) else { return nil }
        self.init(bounds: box, mask: coverage)
    }
}

public extension Bitmap {
    /// Copy the selected pixels, leaving anything outside the mask transparent.
    func extract(_ selection: Selection) -> Bitmap? {
        let extracted = extract(selection.bounds)
        guard !extracted.rect.isEmpty,
              var out = Bitmap(
                width: extracted.rect.width,
                height: extracted.rect.height,
                pixels: extracted.pixels
              )
        else { return nil }

        if let mask = selection.mask {
            // The extract is clipped to the canvas but the mask is addressed in
            // the selection's own space, so a selection hanging off an edge
            // needs the offset — without it every row after the first is read
            // from the wrong place and the wrong pixels are cleared.
            let offsetX = extracted.rect.minX - selection.bounds.minX
            let offsetY = extracted.rect.minY - selection.bounds.minY
            for row in 0..<out.height {
                let maskRow = (row + offsetY) * selection.bounds.width + offsetX
                for column in 0..<out.width where mask[maskRow + column] == 0 {
                    out.pixels[row * out.width + column] = .clear
                }
            }
        }
        return out
    }

    /// Fill the selected pixels, respecting the mask.
    mutating func fill(_ selection: Selection, with colour: RGBA8) {
        guard let mask = selection.mask else {
            return fill(selection.bounds, with: colour)
        }
        let clipped = selection.bounds.intersection(bounds)
        guard !clipped.isEmpty else { return }

        for y in clipped.minY..<clipped.maxY {
            let maskRow = (y - selection.bounds.minY) * selection.bounds.width
            for x in clipped.minX..<clipped.maxX {
                guard mask[maskRow + (x - selection.bounds.minX)] > 0 else { continue }
                pixels[y * width + x] = colour
            }
        }
    }

    /// Per-pixel transform limited to the selection.
    mutating func map(_ selection: Selection, _ transform: (RGBA8) -> RGBA8) {
        guard let mask = selection.mask else {
            return map(selection.bounds, transform)
        }
        let clipped = selection.bounds.intersection(bounds)
        guard !clipped.isEmpty else { return }

        for y in clipped.minY..<clipped.maxY {
            let maskRow = (y - selection.bounds.minY) * selection.bounds.width
            for x in clipped.minX..<clipped.maxX {
                guard mask[maskRow + (x - selection.bounds.minX)] > 0 else { continue }
                let index = y * width + x
                pixels[index] = transform(pixels[index])
            }
        }
    }
}
