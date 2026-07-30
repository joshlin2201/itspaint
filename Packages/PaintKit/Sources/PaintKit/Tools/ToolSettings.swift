import Foundation

/// Everything the inspector can change about how the active tool paints.
public struct ToolSettings: Equatable, Sendable {
    public var tool: ToolKind
    public var shapeKind: ShapeKind
    public var brushSize: Int
    public var brushShape: Brush.Shape
    public var shapeStyle: ShapeStyle
    /// Flood-fill tolerance, 0...255.
    public var fillTolerance: Int
    /// Corner radius for the rounded-rectangle shape, in pixels.
    public var cornerRadius: Int
    /// Highlighter opacity, 0...1.
    public var highlighterOpacity: Double
    /// Mosaic cell size for the pixelate tool.
    public var pixelateBlockSize: Int
    /// Whether shape outlines are solid, dashed or dotted.
    public var strokeDash: Raster.Dash
    /// Which region the select tool resolves.
    public var selectionKind: SelectionKind
    /// Colour tolerance for Instant Alpha, 0...255.
    public var selectionTolerance: Int
    /// How thickly the airbrush sprays, 0.02...1. Low values are the point of
    /// the tool: coverage builds where you linger.
    public var sprayDensity: Double
    /// How the text tool renders. Its colour is filled in from the front
    /// swatch at commit time, like every other marking tool.
    public var textStyle: TextRenderer.Style

    public init(
        // Brush, not pencil. A one-pixel hard nib is the right *tool* to have,
        // but it is the wrong thing to hand someone on a Retina screen the
        // first time they drag — at any zoom below 100% a single pixel is a
        // faint dotted line, and the app reads as broken before it reads as
        // precise.
        tool: ToolKind = .brush,
        shapeKind: ShapeKind = .rectangle,
        // Small enough to draw with, thick enough to see.
        brushSize: Int = 2,
        brushShape: Brush.Shape = .round,
        shapeStyle: ShapeStyle = .outline,
        // **Not zero.** An exact-match bucket is the right default for flat
        // synthetic artwork and the wrong one for everything this app is
        // actually pointed at. Measured on a real screenshot, an exact-match
        // fill on the flat blue of a menu bar covers 0.00% — the tool appears
        // broken, because JPEG noise and Retina downscaling mean no two pixels
        // in a "flat" region are equal.
        //
        // The same sweep says where the ceiling is. Coverage is stable from 8
        // through 32 (2.7% → 3.2% on that menu bar), then falls off a cliff:
        // at 48 a probe in dark window chrome jumps from 4% to 91% because
        // adjacent near-blacks in a dark UI are within 48 of each other. 16
        // clears the artifact floor with the cliff still three times away.
        fillTolerance: Int = 16,
        cornerRadius: Int = 12,
        highlighterOpacity: Double = 0.38,
        pixelateBlockSize: Int = 12,
        strokeDash: Raster.Dash = .solid,
        selectionKind: SelectionKind = .rectangle,
        selectionTolerance: Int = 12,
        sprayDensity: Double = 0.12,
        textStyle: TextRenderer.Style = TextRenderer.Style()
    ) {
        self.tool = tool
        self.shapeKind = shapeKind
        self.brushSize = max(1, brushSize)
        self.brushShape = brushShape
        self.shapeStyle = shapeStyle
        self.fillTolerance = min(255, max(0, fillTolerance))
        self.cornerRadius = max(0, cornerRadius)
        self.highlighterOpacity = min(1, max(0.05, highlighterOpacity))
        self.pixelateBlockSize = max(2, pixelateBlockSize)
        self.strokeDash = strokeDash
        self.selectionKind = selectionKind
        self.selectionTolerance = min(255, max(0, selectionTolerance))
        self.sprayDensity = min(1, max(0.02, sprayDensity))
        self.textStyle = textStyle
    }

    /// Range of the size control, and the bounds every size step honours.
    public static let sizeRange = 1...96

    /// Shape and diameter the current settings resolve to.
    ///
    /// Split out from `brush` because building a brush also builds its coverage
    /// mask — up to size² square roots — while the footprint ring under the
    /// pointer, redrawn on every mouse-moved event, only needs the outline.
    public var nib: (shape: Brush.Shape, size: Int) {
        switch tool {
        case .pencil:
            // The pencil is always a hard single pixel. That is the promise of
            // the tool; making it size-aware would make it a small brush.
            (.square, 1)
        case .eraser:
            (.square, max(1, brushSize))
        case .highlighter:
            // A chisel nib: square, so overlapping passes tile cleanly instead
            // of leaving scalloped edges the way a round nib would.
            (.square, max(4, brushSize))
        case .brush:
            (brushShape, max(1, brushSize))
        default:
            // Everything else borrows the brush's diameter but not its tip:
            // a shape outline is a hard edge, and neither soft falloff nor a
            // spray footprint means anything for one.
            (brushShape == .round ? .round : hardEquivalent, max(1, brushSize))
        }
    }

    /// The tip a tool that only wants a diameter should use.
    private var hardEquivalent: Brush.Shape {
        switch brushShape {
        case .soft, .spray, .round: .round
        case .square: .square
        }
    }

    /// Whether the current stroke sprays rather than stamps.
    ///
    /// **The tip decides, and only the brush's tip.** This used to be
    /// `ToolKind.isSpray`, which meant the airbrush had to be its own rail
    /// button to exist at all. Spray is now a nib, so the question is about the
    /// nib — and it is scoped to the brush because the pencil is a fixed 1px
    /// point, and a spraying eraser or highlighter is not a thing anyone asked
    /// for even though both borrow `brushShape` for their diameter.
    public var isSpraying: Bool { tool == .brush && brushShape.isSpray }

    /// The brush the current settings resolve to, mask and all.
    public var brush: Brush {
        let nib = self.nib
        return Brush(shape: nib.shape, size: nib.size)
    }
}
