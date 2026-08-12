import Foundation

/// The airbrush's randomness, seeded and owned by the engine.
///
/// Its own generator rather than `SystemRandomNumberGenerator` so a spray is
/// reproducible: an engine seeded the same way sprays the same dots, which is
/// what makes the tool testable at all.
public struct SprayRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64 = 0x5EED_1234_ABCD_0F0F) { state = seed }

    /// SplitMix64 — small, fast, and good enough for scattering paint.
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unitInterval() -> Double {
        Double(next() >> 11) * (1.0 / 9007199254740992.0)
    }
}

/// Pure rasterisation primitives. Every entry point returns the **dirty rect**
/// it touched so callers can scope both redraw and undo capture to it — this is
/// the single reason a large canvas stays responsive.
public enum Raster {

    // MARK: - Stamping

    /// Stamp `brush` centred at `point`.
    ///
    /// Clips once against the canvas up front and then walks the mask and the
    /// destination rows linearly. The previous version tested bounds and
    /// evaluated brush coverage per pixel; both are now hoisted out of the
    /// inner loop, which is the difference between a stroke that keeps up with
    /// the pointer and one that lags behind it.
    @discardableResult
    public static func stamp(
        _ brush: Brush,
        colour: RGBA8,
        at point: PixelPoint,
        into bitmap: inout Bitmap,
        blend: Bool = true
    ) -> PixelRect {
        let extent = brush.extent
        let target = PixelRect(
            x: point.x + extent.minX,
            y: point.y + extent.minY,
            width: extent.width,
            height: extent.height
        ).intersection(bitmap.bounds)
        guard !target.isEmpty else { return .empty }

        let maskOriginX = target.minX - (point.x + extent.minX)
        let maskOriginY = target.minY - (point.y + extent.minY)
        let maskWidth = extent.width
        let canvasWidth = bitmap.width
        let opaque = colour.a == 255

        brush.mask.withUnsafeBufferPointer { mask in
            bitmap.pixels.withUnsafeMutableBufferPointer { pixels in
                for row in 0..<target.height {
                    let maskRow = (maskOriginY + row) * maskWidth + maskOriginX
                    let pixelRow = (target.minY + row) * canvasWidth + target.minX
                    for column in 0..<target.width {
                        let coverage = mask[maskRow + column]
                        guard coverage > 0 else { continue }
                        let index = pixelRow + column
                        if coverage == 255 && opaque && !blend {
                            pixels[index] = colour
                        } else {
                            pixels[index] = colour.withCoverage(coverage)
                                .overCompositing(pixels[index])
                        }
                    }
                }
            }
        }
        return target
    }

    /// How a stroke is broken up along its length.
    ///
    /// Applied by *skipping stamps* rather than by a path dash: the stroke is
    /// still the same Bresenham walk, so a dashed line lands on exactly the
    /// pixels a solid one would have used, minus the gaps.
    public enum Dash: String, CaseIterable, Sendable, Identifiable {
        case solid, dashed, dotted

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .solid: "Solid"
            case .dashed: "Dashed"
            case .dotted: "Dotted"
            }
        }

        public var symbolName: String {
            switch self {
            case .solid: "minus"
            case .dashed: "line.diagonal"
            case .dotted: "ellipsis"
            }
        }

        /// On/off run lengths, scaled to the stroke weight so a heavy dashed
        /// line does not read as a solid one.
        func runs(weight: Int) -> (on: Int, off: Int)? {
            let unit = max(2, weight)
            switch self {
            case .solid: return nil
            case .dashed: return (on: unit * 3, off: unit * 2)
            case .dotted: return (on: max(1, unit / 2), off: unit * 2)
            }
        }
    }

    // MARK: - Lines

    /// Bresenham line, stamping `brush` at every step.
    ///
    /// Integer Bresenham (rather than a Core Graphics stroke) is what makes a
    /// 1px pencil land exactly on the pixels the user dragged over, with no
    /// half-covered antialiased neighbours.
    ///
    /// The endpoints are sorted into a canonical order before rasterising.
    /// Textbook Bresenham resolves an exact half-step tie in favour of whatever
    /// direction it happens to be walking, so A→B and B→A can light different
    /// pixels on the same geometric line. That asymmetry shows up as a stroke
    /// that thickens unevenly when the user scrubs back and forth over it.
    /// Sorting first makes the output a function of the *segment*, not of the
    /// direction it was drawn in.
    @discardableResult
    public static func strokeLine(
        from a: PixelPoint,
        to b: PixelPoint,
        brush: Brush,
        colour: RGBA8,
        into bitmap: inout Bitmap,
        blend: Bool = true,
        dash: Dash = .solid
    ) -> PixelRect {
        let reversed = (b.y, b.x) < (a.y, a.x)
        let start = reversed ? b : a
        let end = reversed ? a : b

        var dirty = PixelRect.empty
        var x = start.x, y = start.y
        let dx = abs(end.x - start.x)
        let dy = -abs(end.y - start.y)
        let sx = start.x < end.x ? 1 : -1
        let sy = start.y < end.y ? 1 : -1
        var err = dx + dy

        let runs = dash.runs(weight: brush.size)
        var step = 0

        while true {
            let inGap = runs.map { step % ($0.on + $0.off) >= $0.on } ?? false
            step += 1
            if !inGap {
                dirty = dirty.union(
                    stamp(brush, colour: colour, at: PixelPoint(x: x, y: y), into: &bitmap, blend: blend)
                )
            }
            if x == end.x && y == end.y { break }
            let e2 = 2 * err
            if e2 >= dy {
                err += dy
                x += sx
            }
            if e2 <= dx {
                err += dx
                y += sy
            }
        }
        return dirty
    }

    // MARK: - Rectangles

    @discardableResult
    public static func strokeRect(
        _ rect: PixelRect,
        brush: Brush,
        colour: RGBA8,
        into bitmap: inout Bitmap,
        dash: Dash = .solid
    ) -> PixelRect {
        guard !rect.isEmpty else { return .empty }
        let tl = PixelPoint(x: rect.minX, y: rect.minY)
        let tr = PixelPoint(x: rect.maxX - 1, y: rect.minY)
        let bl = PixelPoint(x: rect.minX, y: rect.maxY - 1)
        let br = PixelPoint(x: rect.maxX - 1, y: rect.maxY - 1)
        return strokePolyline(
            [tl, tr, br, bl], brush: brush, colour: colour, closed: true, into: &bitmap, dash: dash
        )
    }

    @discardableResult
    public static func fillRect(
        _ rect: PixelRect,
        colour: RGBA8,
        into bitmap: inout Bitmap
    ) -> PixelRect {
        let clipped = rect.intersection(bitmap.bounds)
        guard !clipped.isEmpty else { return .empty }
        bitmap.blend(clipped, with: colour)
        return clipped
    }

    // MARK: - Ellipses

    /// Filled ellipse inscribed in `rect`, using a per-scanline solve of the
    /// ellipse equation. Scanline (rather than midpoint + seed fill) keeps
    /// even-diameter ellipses symmetric and never leaks through a seam.
    ///
    /// `clip` restricts output to a sub-rect, which is how the rounded
    /// rectangle borrows a single corner quadrant from a whole ellipse instead
    /// of needing a second arc rasteriser.
    @discardableResult
    public static func fillEllipse(
        in rect: PixelRect,
        colour: RGBA8,
        into bitmap: inout Bitmap,
        clip: PixelRect? = nil
    ) -> PixelRect {
        var dirty = PixelRect.empty
        for (row, span) in ellipseMask(in: rect).enumerated() {
            guard let span else { continue }
            dirty = dirty.union(
                fillRow(
                    x0: span.0, x1: span.1, y: rect.minY + row,
                    colour: colour, into: &bitmap, clip: clip
                )
            )
        }
        return dirty
    }

    /// Ellipse outline: the filled ellipse minus the filled ellipse inset by
    /// the brush size. Deriving the outline from the same solver the fill uses
    /// guarantees outline and fill agree pixel-for-pixel, which is what makes
    /// the "outline + fill" shape style look like one shape rather than two.
    @discardableResult
    public static func strokeEllipse(
        in rect: PixelRect,
        brush: Brush,
        colour: RGBA8,
        into bitmap: inout Bitmap,
        clip: PixelRect? = nil,
        dash: Dash = .solid
    ) -> PixelRect {
        guard !rect.isEmpty else { return .empty }

        // A dashed ellipse is walked as a polyline instead: the span solver
        // draws whole rows at a time, which has no notion of distance *along*
        // the outline and would dash it into horizontal stripes.
        if dash != .solid {
            let steps = max(24, (rect.width + rect.height) / 2)
            let rx = Double(rect.width - 1) / 2, ry = Double(rect.height - 1) / 2
            let cx = Double(rect.minX) + rx, cy = Double(rect.minY) + ry
            let points = (0..<steps).map { step -> PixelPoint in
                let angle = 2 * Double.pi * Double(step) / Double(steps)
                return PixelPoint(
                    x: Int((cx + cos(angle) * rx).rounded()),
                    y: Int((cy + sin(angle) * ry).rounded())
                )
            }
            return strokePolyline(
                points, brush: brush, colour: colour, closed: true, into: &bitmap, dash: dash
            )
        }
        let thickness = max(1, brush.size)
        let outer = ellipseMask(in: rect)
        let innerRect = rect.insetBy(thickness)
        let inner = innerRect.isEmpty ? [] : ellipseMask(in: innerRect)

        var dirty = PixelRect.empty
        for (index, span) in outer.enumerated() {
            guard let span else { continue }
            let y = rect.minY + index
            let innerIndex = y - innerRect.minY
            let innerSpan = (innerIndex >= 0 && innerIndex < inner.count) ? inner[innerIndex] : nil

            if let innerSpan {
                dirty = dirty.union(fillRow(x0: span.0, x1: innerSpan.0, y: y, colour: colour, into: &bitmap, clip: clip))
                dirty = dirty.union(fillRow(x0: innerSpan.1, x1: span.1, y: y, colour: colour, into: &bitmap, clip: clip))
            } else {
                dirty = dirty.union(fillRow(x0: span.0, x1: span.1, y: y, colour: colour, into: &bitmap, clip: clip))
            }
        }
        return dirty
    }

    /// Per-row `[x0, x1)` spans of the ellipse inscribed in `rect`.
    private static func ellipseMask(in rect: PixelRect) -> [(Int, Int)?] {
        guard !rect.isEmpty else { return [] }
        let rx = Double(rect.width) / 2.0
        let ry = Double(rect.height) / 2.0
        let cx = Double(rect.minX) + rx
        let cy = Double(rect.minY) + ry
        return (rect.minY..<rect.maxY).map { y in
            let dy = (Double(y) + 0.5 - cy) / ry
            let inside = 1.0 - dy * dy
            guard inside >= 0 else { return nil }
            let halfSpan = rx * inside.squareRoot()
            let x0 = Int((cx - halfSpan).rounded())
            let x1 = Int((cx + halfSpan).rounded())
            return x1 > x0 ? (x0, x1) : nil
        }
    }

    private static func fillRow(
        x0: Int, x1: Int, y: Int, colour: RGBA8, into bitmap: inout Bitmap,
        clip: PixelRect? = nil
    ) -> PixelRect {
        guard x1 > x0 else { return .empty }
        var clipped = PixelRect(x: x0, y: y, width: x1 - x0, height: 1)
            .intersection(bitmap.bounds)
        if let clip { clipped = clipped.intersection(clip) }
        guard !clipped.isEmpty else { return .empty }
        bitmap.blend(clipped, with: colour)
        return clipped
    }

    // MARK: - Arrow

    /// A line with a solid head at `to`.
    ///
    /// The head is proportional to the stroke weight rather than a fixed size,
    /// so a thin arrow reads as thin and a heavy one stays balanced. The shaft
    /// stops short of the tip so the two never overlap into a lump.
    @discardableResult
    public static func strokeArrow(
        from a: PixelPoint,
        to b: PixelPoint,
        brush: Brush,
        colour: RGBA8,
        into bitmap: inout Bitmap
    ) -> PixelRect {
        let dx = Double(b.x - a.x)
        let dy = Double(b.y - a.y)
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0.5 else {
            return stamp(brush, colour: colour, at: b, into: &bitmap)
        }

        let weight = Double(max(1, brush.size))
        // Head length scales with weight but is capped at a third of the arrow
        // so short arrows stay arrows instead of becoming triangles.
        let headLength = min(length / 3, max(8, weight * 3.5))
        let headHalfWidth = max(4, weight * 1.9)

        let ux = dx / length
        let uy = dy / length
        let baseX = Double(b.x) - ux * headLength
        let baseY = Double(b.y) - uy * headLength
        // Perpendicular.
        let px = -uy
        let py = ux

        var dirty = strokeLine(
            from: a,
            to: PixelPoint(x: Int(baseX.rounded()), y: Int(baseY.rounded())),
            brush: brush,
            colour: colour,
            into: &bitmap
        )

        let head = [
            b,
            PixelPoint(
                x: Int((baseX + px * headHalfWidth).rounded()),
                y: Int((baseY + py * headHalfWidth).rounded())
            ),
            PixelPoint(
                x: Int((baseX - px * headHalfWidth).rounded()),
                y: Int((baseY - py * headHalfWidth).rounded())
            ),
        ]
        dirty = dirty.union(fillPolygon(head, colour: colour, into: &bitmap))
        // Outline the head too, so its edges match the shaft's weight and it
        // does not look softer than the line it terminates.
        dirty = dirty.union(
            strokePolyline(head, brush: Brush(shape: .round, size: 1), colour: colour, closed: true, into: &bitmap)
        )
        return dirty
    }

    // MARK: - Curves

    /// Quadratic Bézier from `a` to `b`, bent towards `through`.
    ///
    /// `through` is a point the curve actually passes at its midpoint, not the
    /// off-curve control point — dragging a handle that the line never touches
    /// is the reason Bézier editors need explaining and Paint's curve tool
    /// never did.
    @discardableResult
    public static func strokeCurve(
        from a: PixelPoint,
        through: PixelPoint,
        to b: PixelPoint,
        brush: Brush,
        colour: RGBA8,
        into bitmap: inout Bitmap,
        dash: Dash = .solid
    ) -> PixelRect {
        // Solve the control point that puts the curve through `through` at t=½.
        let control = PixelPoint(
            x: 2 * through.x - (a.x + b.x) / 2,
            y: 2 * through.y - (a.y + b.y) / 2
        )
        // One segment per ~3px of chord: fine enough that the joins vanish,
        // coarse enough that a long curve is not thousands of stamps.
        let span = max(abs(b.x - a.x), abs(b.y - a.y), abs(control.x - a.x), abs(control.y - a.y))
        let steps = max(8, min(240, span / 3))
        var points: [PixelPoint] = []
        points.reserveCapacity(steps + 1)
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            let u = 1 - t
            points.append(PixelPoint(
                x: Int((u * u * Double(a.x) + 2 * u * t * Double(control.x) + t * t * Double(b.x)).rounded()),
                y: Int((u * u * Double(a.y) + 2 * u * t * Double(control.y) + t * t * Double(b.y)).rounded())
            ))
        }
        return strokePolyline(points, brush: brush, colour: colour, closed: false, into: &bitmap, dash: dash)
    }

    // MARK: - Spray

    /// Scatter `density` fraction of the brush footprint, weighted to the
    /// centre — the airbrush.
    ///
    /// Coverage builds where the pointer lingers, which is the whole feel of
    /// the tool: a stamp that lands the same every time is a brush.
    @discardableResult
    public static func spray(
        _ brush: Brush,
        colour: RGBA8,
        at point: PixelPoint,
        density: Double,
        into bitmap: inout Bitmap,
        using generator: inout SprayRandom
    ) -> PixelRect {
        let radius = Double(max(1, brush.size)) / 2
        let dots = max(1, Int((radius * radius * .pi * max(0.005, min(1, density))).rounded()))
        var dirty = PixelRect.empty

        for _ in 0..<dots {
            // Uniform over the disc: the square root is what stops every dot
            // piling into the middle.
            let angle = generator.unitInterval() * 2 * .pi
            let distance = generator.unitInterval().squareRoot() * radius
            let target = PixelPoint(
                x: point.x + Int((cos(angle) * distance).rounded()),
                y: point.y + Int((sin(angle) * distance).rounded())
            )
            guard bitmap.isInBounds(target) else { continue }
            let index = bitmap.index(target)
            bitmap.pixels[index] = colour.overCompositing(bitmap.pixels[index])
            dirty = dirty.union(PixelRect(x: target.x, y: target.y, width: 1, height: 1))
        }
        return dirty
    }

    /// Spray along a segment, so a fast drag lays a continuous band instead of
    /// a dotted trail of wherever the mouse happened to report.
    @discardableResult
    public static func sprayLine(
        from a: PixelPoint,
        to b: PixelPoint,
        brush: Brush,
        colour: RGBA8,
        density: Double,
        into bitmap: inout Bitmap,
        using generator: inout SprayRandom
    ) -> PixelRect {
        let distance = max(abs(b.x - a.x), abs(b.y - a.y))
        // One puff every half-radius keeps the band even without spraying the
        // same pixels dozens of times on a slow drag.
        let step = max(1, brush.size / 2)
        let puffs = max(1, distance / step)
        var dirty = PixelRect.empty
        for index in 0...puffs {
            let t = Double(index) / Double(puffs)
            let point = PixelPoint(
                x: a.x + Int((Double(b.x - a.x) * t).rounded()),
                y: a.y + Int((Double(b.y - a.y) * t).rounded())
            )
            dirty = dirty.union(
                spray(brush, colour: colour, at: point, density: density, into: &bitmap, using: &generator)
            )
        }
        return dirty
    }

    // MARK: - Region effects

    /// Dim everything *outside* `rect`, so the eye lands where you dragged.
    ///
    /// The opposite shape to `pixelate`: that one changes the region you drew, this
    /// one changes everything else. It is the "look here" mark on a busy screenshot,
    /// where another rectangle or arrow is just more ink on a page that already has
    /// plenty of both.
    ///
    /// **Darkens rather than veiling.** Compositing black at `dim` over the outside
    /// would also fill transparent pixels, so a spotlight on a logo whose background
    /// had been removed would paint black across the checkerboard. Scaling the colour
    /// channels and leaving alpha alone darkens what is there and leaves what is not
    /// there alone. The premultiplied invariant survives because every channel only
    /// gets smaller while alpha holds.
    ///
    /// **Dragging a second one darkens the first.** There is no light here, only a
    /// multiply, so a second spotlight dims everything outside it again including the
    /// region the first one lit. That is inherent to an app that flattens every edit
    /// and has no layers. Undo is the way back, and the tool's own copy says so
    /// rather than letting someone discover it on a screenshot they are about to send.
    ///
    /// The default dim is 0.45, chosen by rendering 0.35, 0.45 and 0.55 over both a
    /// dark and a light screenshot and looking at them. At 0.55 a dark interface goes
    /// almost black, and the context around the point of a bug report is still
    /// evidence even when it is not the point.
    @discardableResult
    public static func spotlight(
        _ rect: PixelRect,
        dim: Double = 0.45,
        radius: Int = 10,
        into bitmap: inout Bitmap
    ) -> PixelRect {
        let lit = rect.intersection(bitmap.bounds)
        let canvas = bitmap.bounds
        guard !canvas.isEmpty else { return .empty }

        // A stray click must not dim the whole image.
        //
        // `PixelRect(corners:)` is inclusive, so clicking without dragging produces a
        // 1x1 rect rather than an empty one. An `isEmpty` guard therefore never fired,
        // and a click left exactly one pixel lit and darkened everything else. The
        // first version of this had a test for the empty case that passed `width: 0`,
        // which is an input the engine cannot produce, so the guard was checking a
        // shape no user could make while the shape they *could* make went through.
        let minimumSide = 8
        guard lit.width >= minimumSide, lit.height >= minimumSide else { return .empty }

        let keep = min(max(dim, 0), 1)
        let scale = 1.0 - keep

        // Clamped so the straight part of each edge is at least one pixel long. At
        // exactly half the shorter side the two corner zones meet, every pixel counts
        // as a corner, and the midpoint of each edge falls outside the arc and goes
        // dark — a rounded rectangle pinched into a lens.
        let r = min(max(radius, 0), (min(lit.width, lit.height) - 1) / 2)

        // Distance to the nearest point of the inner rectangle, which is zero along
        // the straight edges and grows only inside a corner. Symmetric by
        // construction, unlike hand-rolled per-edge arithmetic.
        let innerMinX = lit.minX + r, innerMaxX = lit.maxX - 1 - r
        let innerMinY = lit.minY + r, innerMaxY = lit.maxY - 1 - r
        let rr = r * r

        var scaled = [UInt8](repeating: 0, count: 256)
        for i in 0..<256 { scaled[i] = UInt8((Double(i) * scale).rounded()) }

        let width = canvas.width
        bitmap.pixels.withUnsafeMutableBufferPointer { buffer in
            for y in canvas.minY..<canvas.maxY {
                let row = (y - canvas.minY) * width
                let insideRows = y >= lit.minY && y < lit.maxY
                let dy = y < innerMinY ? innerMinY - y : y > innerMaxY ? y - innerMaxY : 0
                for x in canvas.minX..<canvas.maxX {
                    if insideRows && x >= lit.minX && x < lit.maxX {
                        let dx = x < innerMinX ? innerMinX - x : x > innerMaxX ? x - innerMaxX : 0
                        if dx * dx + dy * dy <= rr { continue }
                    }
                    let i = row + (x - canvas.minX)
                    let c = buffer[i]
                    buffer[i] = RGBA8(r: scaled[Int(c.r)], g: scaled[Int(c.g)], b: scaled[Int(c.b)], a: c.a)
                }
            }
        }
        return canvas
    }

    /// Mosaic `rect` by averaging each `blockSize` cell.
    ///
    /// This is a presentation effect, not secure redaction. Averaging removes
    /// detail from each block, but callers must not promise that it protects
    /// secrets or personal data.
    @discardableResult
    public static func pixelate(
        _ rect: PixelRect,
        blockSize: Int,
        into bitmap: inout Bitmap
    ) -> PixelRect {
        let region = rect.intersection(bitmap.bounds)
        let block = max(2, blockSize)
        guard !region.isEmpty else { return .empty }

        var y = region.minY
        while y < region.maxY {
            let rowEnd = min(y + block, region.maxY)
            var x = region.minX
            while x < region.maxX {
                let columnEnd = min(x + block, region.maxX)

                var r = 0, g = 0, b = 0, a = 0, count = 0
                for sy in y..<rowEnd {
                    for sx in x..<columnEnd {
                        let pixel = bitmap.unsafePixel(at: PixelPoint(x: sx, y: sy))
                        r += Int(pixel.r); g += Int(pixel.g)
                        b += Int(pixel.b); a += Int(pixel.a)
                        count += 1
                    }
                }
                guard count > 0 else { x = columnEnd; continue }
                let average = RGBA8(
                    r: UInt8(r / count), g: UInt8(g / count),
                    b: UInt8(b / count), a: UInt8(a / count)
                )
                bitmap.fill(
                    PixelRect(x: x, y: y, width: columnEnd - x, height: rowEnd - y),
                    with: average
                )
                x = columnEnd
            }
            y = rowEnd
        }
        return region
    }

    // MARK: - Polygons

    @discardableResult
    public static func strokePolyline(
        _ points: [PixelPoint],
        brush: Brush,
        colour: RGBA8,
        closed: Bool,
        into bitmap: inout Bitmap,
        dash: Dash = .solid
    ) -> PixelRect {
        guard points.count > 1 else {
            guard let only = points.first else { return .empty }
            return stamp(brush, colour: colour, at: only, into: &bitmap)
        }
        var dirty = PixelRect.empty
        for i in 0..<(points.count - 1) {
            dirty = dirty.union(
                strokeLine(from: points[i], to: points[i + 1], brush: brush, colour: colour, into: &bitmap, dash: dash)
            )
        }
        if closed, let first = points.first, let last = points.last, first != last {
            dirty = dirty.union(
                strokeLine(from: last, to: first, brush: brush, colour: colour, into: &bitmap, dash: dash)
            )
        }
        return dirty
    }

    /// Even-odd scanline polygon fill.
    @discardableResult
    public static func fillPolygon(
        _ points: [PixelPoint],
        colour: RGBA8,
        into bitmap: inout Bitmap
    ) -> PixelRect {
        guard points.count >= 3 else { return .empty }
        let minY = max(0, points.map(\.y).min() ?? 0)
        let maxY = min(bitmap.height - 1, points.map(\.y).max() ?? 0)
        guard maxY >= minY else { return .empty }
        var dirty = PixelRect.empty

        for y in minY...maxY {
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
                let x0 = Int(crossings[i].rounded())
                let x1 = Int(crossings[i + 1].rounded())
                dirty = dirty.union(fillRow(x0: x0, x1: x1, y: y, colour: colour, into: &bitmap))
                i += 2
            }
        }
        return dirty
    }

    // MARK: - Flood fill

    /// Scanline flood fill (the paint bucket).
    ///
    /// Explicitly iterative with an span stack. A recursive four-way fill
    /// overflows the stack on any realistically sized canvas — a 4000×4000
    /// region would recurse 16M deep — so recursion is not an option here even
    /// though it reads more nicely.
    @discardableResult
    public static func floodFill(
        from origin: PixelPoint,
        with colour: RGBA8,
        tolerance: Int = 0,
        contiguous: Bool = true,
        into bitmap: inout Bitmap
    ) -> PixelRect {
        guard bitmap.isInBounds(origin) else { return .empty }
        let target = bitmap.unsafePixel(at: origin)
        if matches(colour, target, tolerance: 0) { return .empty }
        guard let selection = floodSelection(
            from: origin, tolerance: tolerance, contiguous: contiguous, in: bitmap
        ) else { return .empty }
        bitmap.fill(selection, with: colour)
        return selection.bounds
    }

    /// Select the pixels a flood fill would change, without changing them.
    ///
    /// Instant Alpha and the paint bucket share this span walk so they cannot
    /// disagree about where a colour region ends. A mask is the output because
    /// connected regions can contain holes and need not be rectangular.
    public static func floodSelection(
        from origin: PixelPoint,
        tolerance: Int = 0,
        contiguous: Bool = true,
        in bitmap: Bitmap
    ) -> Selection? {
        guard bitmap.isInBounds(origin) else { return nil }
        let target = bitmap.unsafePixel(at: origin)
        var coverage = [UInt8](repeating: 0, count: bitmap.count)

        if !contiguous {
            for index in bitmap.pixels.indices
                where matches(bitmap.pixels[index], target, tolerance: tolerance)
            {
                coverage[index] = 255
            }
            return Selection(bounds: bitmap.bounds, mask: coverage).tightened()
        }

        var stack: [(x0: Int, x1: Int, y: Int)] = []

        @inline(__always)
        func fillable(_ x: Int, _ y: Int) -> Bool {
            guard x >= 0, x < bitmap.width, y >= 0, y < bitmap.height else { return false }
            let i = y * bitmap.width + x
            guard coverage[i] == 0 else { return false }
            return matches(bitmap.pixels[i], target, tolerance: tolerance)
        }

        func scan(_ x0: Int, _ x1: Int, _ y: Int) {
            guard y >= 0, y < bitmap.height else { return }
            var x = x0
            while x <= x1 {
                guard fillable(x, y) else { x += 1; continue }
                var start = x
                while fillable(start - 1, y) { start -= 1 }
                var end = x
                while fillable(end + 1, y) { end += 1 }
                stack.append((start, end, y))
                x = end + 1
            }
        }

        scan(origin.x, origin.x, origin.y)

        while let span = stack.popLast() {
            for x in span.x0...span.x1 {
                let i = span.y * bitmap.width + x
                guard coverage[i] == 0 else { continue }
                coverage[i] = 255
            }
            scan(span.x0, span.x1, span.y - 1)
            scan(span.x0, span.x1, span.y + 1)
        }
        guard coverage.contains(255) else { return nil }
        return Selection(bounds: bitmap.bounds, mask: coverage).tightened()
    }

    /// Channel-wise tolerance comparison. `tolerance` is 0...255 and applies to
    /// the largest single-channel difference, which is the behaviour users
    /// expect from a "tolerance" slider (rather than a Euclidean distance that
    /// makes the slider feel non-linear).
    @inlinable
    public static func matches(_ a: RGBA8, _ b: RGBA8, tolerance: Int) -> Bool {
        if tolerance <= 0 { return a == b }
        let dr = abs(Int(a.r) - Int(b.r))
        let dg = abs(Int(a.g) - Int(b.g))
        let db = abs(Int(a.b) - Int(b.b))
        let da = abs(Int(a.a) - Int(b.a))
        return max(max(dr, dg), max(db, da)) <= tolerance
    }
}
