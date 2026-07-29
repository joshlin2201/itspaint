import Foundation

/// The swatch grid.
///
/// The classic 28-swatch two-row layout is kept because it is the single
/// strongest piece of spatial muscle memory the original app left people with —
/// the colours live in the same places. The *rendering* of the grid is modern;
/// the map is not rearranged for novelty.
public struct Palette: Equatable, Codable, Sendable {
    /// The editor is deliberately a two-row, 14-column palette. Keeping that
    /// product contract as a model invariant prevents a document from turning
    /// the eager toolbar grid into an unbounded view tree.
    public static let maximumSwatchCount = 28

    public private(set) var swatches: [PaintColour]

    public init(swatches: [PaintColour]) {
        self.swatches = Array(swatches.prefix(Self.maximumSwatchCount))
    }

    private enum CodingKeys: String, CodingKey {
        case swatches
    }

    /// Decode incrementally so an untrusted document is rejected before the
    /// twenty-ninth colour is materialised. The keyed shape intentionally
    /// matches the compiler-synthesised representation used by older packages.
    public init(from decoder: Decoder) throws {
        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        var encoded = try keyed.nestedUnkeyedContainer(forKey: .swatches)
        var decoded: [PaintColour] = []
        decoded.reserveCapacity(min(encoded.count ?? 0, Self.maximumSwatchCount))

        while !encoded.isAtEnd {
            guard decoded.count < Self.maximumSwatchCount else {
                throw DecodingError.dataCorruptedError(
                    in: encoded,
                    debugDescription: "A palette can contain at most \(Self.maximumSwatchCount) swatches."
                )
            }
            decoded.append(try encoded.decode(PaintColour.self))
        }
        swatches = decoded
    }

    public func encode(to encoder: Encoder) throws {
        var keyed = encoder.container(keyedBy: CodingKeys.self)
        try keyed.encode(swatches, forKey: .swatches)
    }

    /// The default two-row set: 14 saturated hues over 14 muted counterparts.
    public static let standard = Palette(swatches: [
        // Row 1
        PaintColour(hex: "000000")!, PaintColour(hex: "808080")!,
        PaintColour(hex: "800000")!, PaintColour(hex: "808000")!,
        PaintColour(hex: "008000")!, PaintColour(hex: "008080")!,
        PaintColour(hex: "000080")!, PaintColour(hex: "800080")!,
        PaintColour(hex: "808040")!, PaintColour(hex: "004040")!,
        PaintColour(hex: "0080FF")!, PaintColour(hex: "004080")!,
        PaintColour(hex: "8000FF")!, PaintColour(hex: "804000")!,
        // Row 2
        PaintColour(hex: "FFFFFF")!, PaintColour(hex: "C0C0C0")!,
        PaintColour(hex: "FF0000")!, PaintColour(hex: "FFFF00")!,
        PaintColour(hex: "00FF00")!, PaintColour(hex: "00FFFF")!,
        PaintColour(hex: "0000FF")!, PaintColour(hex: "FF00FF")!,
        PaintColour(hex: "FFFF80")!, PaintColour(hex: "00FF80")!,
        PaintColour(hex: "80FFFF")!, PaintColour(hex: "8080FF")!,
        PaintColour(hex: "FF0080")!, PaintColour(hex: "FF8040")!,
    ])

    public static let columns = 14
    public var rows: Int { Int((Double(swatches.count) / Double(Self.columns)).rounded(.up)) }

    public subscript(index: Int) -> PaintColour? {
        swatches.indices.contains(index) ? swatches[index] : nil
    }
}

/// The pair of colours a Paint-style app always has loaded.
///
/// Left-drag paints `foreground`, right-drag paints `background`. That two-
/// button binding is the other half of the muscle memory, and it is why the
/// canvas deliberately does **not** open a context menu on right-click.
public struct ColourPair: Equatable, Sendable {
    public var foreground: PaintColour
    public var background: PaintColour

    public init(foreground: PaintColour = .black, background: PaintColour = .white) {
        self.foreground = foreground
        self.background = background
    }

    public mutating func swap() {
        Swift.swap(&foreground, &background)
    }

    public func colour(for button: PointerButton) -> PaintColour {
        button == .primary ? foreground : background
    }

    /// The colour a stroke *erases to* for the given button. The eraser is the
    /// mirror of the pencil: it paints the background colour, and with the
    /// secondary button it paints the foreground.
    public func erasureColour(for button: PointerButton) -> PaintColour {
        button == .primary ? background : foreground
    }
}

public enum PointerButton: String, Codable, Sendable {
    case primary
    case secondary
}
