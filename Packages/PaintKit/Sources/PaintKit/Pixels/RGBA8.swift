import Foundation

/// One pixel in the canonical canvas format: 8 bits per component, RGBA,
/// **premultiplied** alpha, sRGB.
///
/// Premultiplied is chosen deliberately. It is the format `CGBitmapContext`
/// wants (`.premultipliedLast`), so the exact same byte buffer can be handed to
/// Core Graphics for antialiased work (text, curves, stroked shapes) *and*
/// mutated directly by our own scanline rasterizers (pencil, flood fill) with
/// no conversion step between them. For fully opaque paint — which is most of
/// what a Paint-style app does — premultiplied and straight alpha are
/// byte-identical, so pixel-art precision is unaffected.
public struct RGBA8: Equatable, Hashable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public var a: UInt8

    @inlinable
    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public static let clear = RGBA8(r: 0, g: 0, b: 0, a: 0)
    public static let black = RGBA8(r: 0, g: 0, b: 0, a: 255)
    public static let white = RGBA8(r: 255, g: 255, b: 255, a: 255)

    /// True when the pixel carries no coverage at all.

    /// Composite `self` over `dst` using source-over in premultiplied space.
    ///
    /// Both operands are premultiplied, so the standard Porter-Duff form
    /// `out = src + dst * (1 - srcAlpha)` applies per channel with no
    /// un-premultiply round trip.
    @inlinable
    public func overCompositing(_ dst: RGBA8) -> RGBA8 {
        if a == 255 { return self }
        if a == 0 { return dst }
        let inv = UInt32(255 - a)
        @inline(__always) func blend(_ s: UInt8, _ d: UInt8) -> UInt8 {
            // +127 rounds to nearest instead of truncating, which keeps long
            // stroke chains from drifting darker over repeated compositing.
            let v = UInt32(s) * 255 + UInt32(d) * inv
            return UInt8(min(255, (v + 127) / 255))
        }
        return RGBA8(r: blend(r, dst.r), g: blend(g, dst.g), b: blend(b, dst.b), a: blend(a, dst.a))
    }

    /// Multiply every component by `coverage` (0...255), staying premultiplied.
    @inlinable
    public func withCoverage(_ coverage: UInt8) -> RGBA8 {
        if coverage == 255 { return self }
        if coverage == 0 { return .clear }
        let c = UInt32(coverage)
        @inline(__always) func scale(_ v: UInt8) -> UInt8 {
            UInt8(min(255, (UInt32(v) * c + 127) / 255))
        }
        return RGBA8(r: scale(r), g: scale(g), b: scale(b), a: scale(a))
    }

    /// Straight (un-premultiplied) components, for display and colour picking.
    public var unpremultiplied: (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        guard a > 0, a < 255 else { return (r, g, b, a) }
        let alpha = UInt32(a)
        @inline(__always) func un(_ v: UInt8) -> UInt8 {
            UInt8(min(255, (UInt32(v) * 255 + alpha / 2) / alpha))
        }
        return (un(r), un(g), un(b), a)
    }
}
