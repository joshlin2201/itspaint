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
        tool: ToolKind = .pencil,
        shapeKind: ShapeKind = .rectangle,
        brushSize: Int = 4,
        brushShape: Brush.Shape = .round,
        shapeStyle: ShapeStyle = .outline,
        fillTolerance: Int = 0,
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
            (brushShape == .soft ? .round : brushShape, max(1, brushSize))
        }
    }

    /// The brush the current settings resolve to, mask and all.
    public var brush: Brush {
        let nib = self.nib
        return Brush(shape: nib.shape, size: nib.size)
    }
}
