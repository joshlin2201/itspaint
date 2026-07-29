import Foundation

/// Integer pixel coordinate. The canvas model is deliberately integral —
/// a Paint-style app promises "the pixel I clicked is the pixel that changed",
/// and floating-point canvas coordinates are how that promise gets broken.
/// Floating point lives only in the view layer (zoom, scroll, pressure).
public struct PixelPoint: Equatable, Hashable, Sendable {
    public var x: Int
    public var y: Int

    @inlinable
    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    public static let zero = PixelPoint(x: 0, y: 0)
}

/// Integer pixel rectangle, half-open: `minX..<maxX`, `minY..<maxY`.
extension PixelPoint {
    /// Within `distance` pixels on both axes — a square hit test, which is what
    /// "did the click land back on that corner" actually means on screen.
    public func isNear(_ other: PixelPoint, within distance: Int) -> Bool {
        abs(x - other.x) <= distance && abs(y - other.y) <= distance
    }
}

public struct PixelRect: Equatable, Hashable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    @inlinable
    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = max(0, width)
        self.height = max(0, height)
    }

    public static let empty = PixelRect(x: 0, y: 0, width: 0, height: 0)

    @inlinable public var isEmpty: Bool { width == 0 || height == 0 }
    @inlinable public var minX: Int { x }
    @inlinable public var minY: Int { y }
    @inlinable public var maxX: Int { x + width }
    @inlinable public var maxY: Int { y + height }
    @inlinable public var area: Int { width * height }

    /// Smallest rect containing both corners, inclusive of each.
    public init(corners a: PixelPoint, _ b: PixelPoint) {
        let minX = min(a.x, b.x), maxX = max(a.x, b.x)
        let minY = min(a.y, b.y), maxY = max(a.y, b.y)
        self.init(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    @inlinable
    public func contains(_ p: PixelPoint) -> Bool {
        p.x >= minX && p.x < maxX && p.y >= minY && p.y < maxY
    }

    public func intersection(_ other: PixelRect) -> PixelRect {
        let nx = max(minX, other.minX)
        let ny = max(minY, other.minY)
        let nmaxX = min(maxX, other.maxX)
        let nmaxY = min(maxY, other.maxY)
        guard nmaxX > nx, nmaxY > ny else { return .empty }
        return PixelRect(x: nx, y: ny, width: nmaxX - nx, height: nmaxY - ny)
    }

    public func union(_ other: PixelRect) -> PixelRect {
        if isEmpty { return other }
        if other.isEmpty { return self }
        let nx = min(minX, other.minX)
        let ny = min(minY, other.minY)
        return PixelRect(
            x: nx,
            y: ny,
            width: max(maxX, other.maxX) - nx,
            height: max(maxY, other.maxY) - ny
        )
    }

    /// Grow by `amount` on every side, clamped at zero size.
    public func insetBy(_ amount: Int) -> PixelRect {
        PixelRect(
            x: x + amount,
            y: y + amount,
            width: width - amount * 2,
            height: height - amount * 2
        )
    }
}
