import Foundation

/// The tool set.
///
/// Eleven rail tools, grouped by job. Variations stay inside the tool that owns
/// them: fifteen shapes share one Shape button, four ways to select share one
/// Select button, and four nibs — including the airbrush — share one Brush
/// button. This keeps the whole set available without turning every variation
/// into another rail button.
///
/// **Airbrush used to be the twelfth.** It was a rail cell that differed from
/// Brush by one thing: whether coverage builds while you hold still. Same size
/// control, same colour, same drag. That is a nib, not a job, so it moved into
/// the Tip row where round, square and soft already live, and the rail got one
/// cell shorter on the axis a picture needs most.
///
/// The set covers screenshot markup directly: Highlighter, arrows, step badges,
/// crop, and Pixelate all sit one action away.
public enum ToolKind: String, CaseIterable, Codable, Sendable, Identifiable {
    // Draw
    case pencil
    case brush
    case highlighter
    case eraser
    // Insert
    case shape
    case text
    case badge
    case fill
    case eyedropper
    // Select
    case select
    case pixelate
    case spotlight

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .pencil: "Pencil"
        case .brush: "Brush"
        case .highlighter: "Highlighter"
        case .eraser: "Eraser"
        case .shape: "Shape"
        case .text: "Text"
        case .badge: "Step badge"
        case .fill: "Fill"
        case .eyedropper: "Eyedropper"
        case .select: "Select"
        case .pixelate: "Pixelate"
        case .spotlight: "Spotlight"
        }
    }

    /// SF Symbols only — never an emoji, and never a bespoke glyph where the
    /// system already ships the right one.
    public var symbolName: String {
        switch self {
        case .pencil: "pencil"
        case .brush: "paintbrush"
        case .highlighter: "highlighter"
        case .eraser: "eraser"
        case .shape: "square.on.circle"
        case .text: "textformat"
        // Outline, like every other tool. The rail overrides this with the
        // number actually about to be dropped; this is the menu fallback.
        case .badge: "1.circle"
        // SF Symbols has no paint bucket, so the rail draws its own (see
        // `BucketGlyph`); this is the fallback for menus and the accessibility
        // description.
        case .fill: "drop.fill"
        case .eyedropper: "eyedropper"
        case .select: "rectangle.dashed"
        case .pixelate: "mosaic"
        case .spotlight: "rectangle.center.inset.filled"
        }
    }

    /// Single-key shortcut. Every tool is keyboard reachable — an accessibility
    /// requirement, not a power-user nicety.
    public var shortcut: Character {
        switch self {
        case .pencil: "p"
        case .brush: "b"
        case .highlighter: "h"
        case .eraser: "e"
        case .shape: "u"
        case .text: "t"
        case .badge: "n"
        case .fill: "k"
        case .eyedropper: "i"
        case .select: "m"
        case .pixelate: "r"
        case .spotlight: "s"
        }
    }

    public var isFreehand: Bool {
        switch self {
        case .pencil, .brush, .highlighter, .eraser: true
        default: false
        }
    }

    /// Drags out a rectangle that is a *region*, not a mark.
    /// Drags a rectangle and applies an effect to it, rather than selecting it or
    /// drawing a shape. Both name their own undo step after the tool.
    public var isRegionEffect: Bool {
        switch self {
        case .pixelate, .spotlight: true
        default: false
        }
    }

    public var isRegionDrag: Bool {
        switch self {
        case .select, .pixelate, .spotlight: true
        default: false
        }
    }

    public var usesBrushSize: Bool {
        switch self {
        case .brush, .highlighter, .eraser, .shape, .badge: true
        default: false
        }
    }

    public var usesShapeKind: Bool { self == .shape }

    /// Whether to draw the brush footprint under the pointer.
    ///
    /// Marking tools only. A ring around the fill bucket or the eyedropper
    /// would imply an area those tools do not have.
    public var showsBrushPreview: Bool {
        switch self {
        case .pencil, .brush, .highlighter, .eraser, .shape, .badge: true
        default: false
        }
    }

    /// Reads the canvas without changing it, so it must stay out of undo —
    /// putting a colour pick on the undo stack is a classic way to make ⌘Z
    /// feel broken.
    public var isReadOnly: Bool { self == .eyedropper }

    /// Rail order, grouped by job. Three short runs scan far faster than one
    /// undifferentiated column.
    public static let groups: [[ToolKind]] = [
        [.pencil, .brush, .highlighter, .eraser],
        [.shape, .text, .badge, .fill, .eyedropper],
        [.select, .pixelate, .spotlight],
    ]
}

/// Which marquee the select tool drags out.
///
/// One tool, four ways to enclose something — the way Preview's markup bar
/// does it. Four rail buttons for "select a region" is four times the
/// scanning cost for one decision, and the lasso was never a different *job*.
public enum SelectionKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case rectangle
    case ellipse
    /// Traced freehand; closes itself.
    case lasso
    /// A connected colour region under one point.
    case instantAlpha

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .rectangle: "Rectangular selection"
        case .ellipse: "Elliptical selection"
        case .lasso: "Lasso selection"
        case .instantAlpha: "Instant Alpha"
        }
    }

    public var symbolName: String {
        switch self {
        case .rectangle: "rectangle.dashed"
        case .ellipse: "circle.dashed"
        case .lasso: "lasso"
        case .instantAlpha: "wand.and.stars"
        }
    }

    /// Traced rather than dragged out as a box.
    public var isFreeform: Bool { self == .lasso }

    /// Resolves from one canvas pixel rather than a drag.
    public var isPointSelect: Bool { self == .instantAlpha }
}

/// Which shape the shape tool emits.
///
/// One tool, many shapes — the family reveals itself in the tool's own options
/// rather than costing a rail button each, which is the trade that keeps the
/// rail scannable while still covering what the classic app drew.
///
/// Most of these are **point lists**: one parametric generator produces the
/// triangle, diamond, pentagon, hexagon and both stars, so adding a shape is a
/// case in `points(in:)` rather than a new rasteriser.
public enum ShapeKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case line
    /// Drag the chord, then drag again to bend it. The classic curve.
    case curve
    /// The single most-wanted annotation primitive, and the one the classic app
    /// never had — every user drew one by hand out of three lines.
    case arrow
    case rectangle
    case roundedRectangle
    case ellipse
    case triangle
    case rightTriangle
    case diamond
    case pentagon
    case hexagon
    case star5
    case star6
    /// A rounded box with a tail — the annotation shape that carries text.
    case callout
    /// Click each corner; closes when you click the first one again.
    case polygon

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .line: "Line"
        case .curve: "Curve"
        case .arrow: "Arrow"
        case .rectangle: "Rectangle"
        case .roundedRectangle: "Rounded rectangle"
        case .ellipse: "Ellipse"
        case .triangle: "Triangle"
        case .rightTriangle: "Right triangle"
        case .diamond: "Diamond"
        case .pentagon: "Pentagon"
        case .hexagon: "Hexagon"
        case .star5: "Five-point star"
        case .star6: "Six-point star"
        case .callout: "Speech bubble"
        case .polygon: "Polygon"
        }
    }

    public var symbolName: String {
        switch self {
        case .line: "line.diagonal"
        case .curve: "point.topleft.down.curvedto.point.bottomright.up"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .roundedRectangle: "rectangle.roundedtop"
        case .ellipse: "circle"
        case .triangle: "triangle"
        case .rightTriangle: "angle"
        case .diamond: "diamond"
        case .pentagon: "pentagon"
        case .hexagon: "hexagon"
        case .star5: "star"
        case .star6: "seal"
        case .callout: "bubble.left"
        case .polygon: "skew"
        }
    }

    /// Open shapes have no interior, so the fill control does not apply.
    public var isClosed: Bool {
        switch self {
        case .line, .curve, .arrow: false
        default: true
        }
    }

    /// Needs more than one drag: the curve bends after its chord, the polygon
    /// collects clicks until it closes.
    public var isMultiStep: Bool { self == .curve || self == .polygon }

    /// Corners of a polygonal shape inscribed in `rect`, clockwise from the top.
    ///
    /// Sampling on the ellipse inscribed in `rect` (rather than on a circle)
    /// is what lets every one of these stretch with the drag instead of staying
    /// stubbornly regular in a box that is not square.
    func points(in rect: PixelRect) -> [PixelPoint] {
        guard !rect.isEmpty else { return [] }
        let rx = Double(rect.width - 1) / 2
        let ry = Double(rect.height - 1) / 2
        let cx = Double(rect.minX) + rx
        let cy = Double(rect.minY) + ry

        // Angles run clockwise from straight up, which is where every one of
        // these shapes has a vertex when drawn by hand.
        func onRim(_ index: Int, of count: Int, scale: Double = 1) -> PixelPoint {
            let angle = -Double.pi / 2 + 2 * .pi * Double(index) / Double(count)
            return PixelPoint(
                x: Int((cx + cos(angle) * rx * scale).rounded()),
                y: Int((cy + sin(angle) * ry * scale).rounded())
            )
        }

        func star(points count: Int, innerScale: Double) -> [PixelPoint] {
            (0..<(count * 2)).map { step in
                onRim(step, of: count * 2, scale: step.isMultiple(of: 2) ? 1 : innerScale)
            }
        }

        switch self {
        case .triangle:
            return [
                PixelPoint(x: Int(cx.rounded()), y: rect.minY),
                PixelPoint(x: rect.maxX - 1, y: rect.maxY - 1),
                PixelPoint(x: rect.minX, y: rect.maxY - 1),
            ]
        case .rightTriangle:
            return [
                PixelPoint(x: rect.minX, y: rect.minY),
                PixelPoint(x: rect.maxX - 1, y: rect.maxY - 1),
                PixelPoint(x: rect.minX, y: rect.maxY - 1),
            ]
        case .diamond:
            return (0..<4).map { onRim($0, of: 4) }
        case .pentagon:
            return (0..<5).map { onRim($0, of: 5) }
        case .hexagon:
            return (0..<6).map { onRim($0, of: 6) }
        // 0.382 is the classic five-point ratio; the six-point star reads
        // better slightly fuller.
        case .star5:
            return star(points: 5, innerScale: 0.382)
        case .star6:
            return star(points: 6, innerScale: 0.5)
        default:
            return []
        }
    }
}

/// How a closed shape is painted.
public enum ShapeStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    case outline
    case filled
    case outlineAndFill

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .outline: "Outline"
        case .filled: "Fill"
        case .outlineAndFill: "Outline and fill"
        }
    }

    public var symbolName: String {
        switch self {
        case .outline: "square"
        case .filled: "square.fill"
        case .outlineAndFill: "square.inset.filled"
        }
    }

    public var drawsOutline: Bool { self != .filled }
    public var drawsFill: Bool { self != .outline }
}
