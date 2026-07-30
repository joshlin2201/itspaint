import Foundation

/// The stamp a stroking tool drags along its path.
///
/// A brush is a *mask*, not a colour: it stores per-offset coverage and the
/// tool multiplies its colour by that. Keeping coverage and colour separate is
/// what lets pencil (hard, size 1), brush (soft, antialiased) and highlighter
/// (chisel) share one stroke path.
///
/// **The mask is computed once, at construction, into a flat array.** It used
/// to be a `coverage(dx:dy:)` function evaluated per pixel per stamp, which put
/// a `sqrt` and a switch inside the innermost loop of every stroke. Precomputing
/// removes both: a stroke now reads bytes out of a small contiguous buffer.
public struct Brush: Equatable, Sendable {
    public enum Shape: String, CaseIterable, Codable, Sendable {
        /// Aliased square — the classic pixel-art nib. Every covered pixel is
        /// fully covered, so repeated passes never darken an edge.
        case square
        /// Aliased circle. Hard edge, round footprint.
        case round
        /// Antialiased circle with a soft falloff over the outer pixel ring.
        case soft
        /// A round footprint that lands *stochastically*: the mask is the area
        /// the spray can reach, and coverage builds inside it while the button
        /// is held. This is the airbrush.
        ///
        /// It lives here rather than as its own rail tool because it is a nib,
        /// not a job — the same size control, the same colour, the same drag.
        /// Round, square, soft and spray are four answers to "what does the
        /// brush leave behind", and the tool set already keeps variations inside
        /// the tool that owns them.
        case spray

        /// Builds coverage over time rather than stamping it once.
        public var isSpray: Bool { self == .spray }
    }

    public let shape: Shape
    /// Diameter in pixels. 1 means a single-pixel nib (pencil).
    public let size: Int

    /// Row-major coverage over `extent`, `extent.area` entries.
    public let mask: [UInt8]

    /// Offsets covered by the stamp, relative to its centre.
    public let extent: PixelRect

    public init(shape: Shape = .round, size: Int = 1) {
        let clamped = max(1, size)
        let extent = Self.extent(size: clamped)

        self.shape = shape
        self.size = clamped
        self.extent = extent
        self.mask = Self.buildMask(shape: shape, size: clamped, extent: extent)
    }

    /// The offsets a stamp of `size` covers — the geometry of a brush without
    /// the cost of building one, for drawing the footprint ring.
    public static func extent(size: Int) -> PixelRect {
        let clamped = max(1, size)
        let half = clamped / 2
        return PixelRect(x: -half, y: -half, width: clamped, height: clamped)
    }

    public static let pencil = Brush(shape: .square, size: 1)

    /// Coverage (0...255) at offset `(dx, dy)` from the stamp centre.
    @inlinable
    public func coverage(dx: Int, dy: Int) -> UInt8 {
        let column = dx - extent.minX
        let row = dy - extent.minY
        guard column >= 0, column < extent.width, row >= 0, row < extent.height else { return 0 }
        return mask[row * extent.width + column]
    }

    // MARK: - Mask construction

    private static func buildMask(shape: Shape, size: Int, extent: PixelRect) -> [UInt8] {
        var mask = [UInt8](repeating: 0, count: extent.area)
        guard size > 1 else { return [255] }

        // Sample from pixel centres so even and odd diameters both land
        // symmetrically around the stamp origin.
        let radius = Double(size) / 2.0
        let offset = size % 2 == 0 ? 0.5 : 0.0
        let inner = max(0, radius - 1.0)

        for row in 0..<extent.height {
            let dy = Double(extent.minY + row) + offset
            for column in 0..<extent.width {
                let dx = Double(extent.minX + column) + offset
                let index = row * extent.width + column

                switch shape {
                case .square:
                    mask[index] = 255

                // Spray reaches a round area; which pixels inside it actually
                // land is the spray raster's decision, per step, from density.
                case .round, .spray:
                    mask[index] = (dx * dx + dy * dy).squareRoot() <= radius - 0.25 ? 255 : 0

                case .soft:
                    let distance = (dx * dx + dy * dy).squareRoot()
                    if distance <= inner {
                        mask[index] = 255
                    } else if distance >= radius {
                        mask[index] = 0
                    } else {
                        let t = 1.0 - (distance - inner) / Swift.max(0.0001, radius - inner)
                        mask[index] = UInt8(Swift.max(0, Swift.min(255, (t * 255).rounded())))
                    }
                }
            }
        }
        return mask
    }

    // Equality and hashing ignore the derived mask: two brushes with the same
    // shape and size are the same brush, and comparing a 4 KB array to prove it
    // would be pure waste.
    public static func == (lhs: Brush, rhs: Brush) -> Bool {
        lhs.shape == rhs.shape && lhs.size == rhs.size
    }
}
