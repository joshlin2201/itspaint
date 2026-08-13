import Foundation

/// Everything the inspector can change about how the active tool paints.
/// The two jobs the clone cell does.
public enum CloneMode: String, CaseIterable, Codable, Sendable {
    /// Copy pixels from a pinned source, at a fixed offset.
    case clone
    /// Blur towards the pre-stroke neighbourhood, which is what hides a clone seam.
    case soften

    public var displayName: String { self == .clone ? "Clone" : "Soften" }
    public var symbolName: String {
        self == .clone ? "plus.rectangle.on.rectangle" : "drop.halffull"
    }
}

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
    /// Spacing of the alignment grid in pixels, or `0` for none.
    ///
    /// **Not the pixel grid.** That one draws every pixel above 4x zoom and
    /// snapping to it would mean nothing — a drag already lands on whole pixels.
    /// This is the coarse grid people mean by "snap": a shape or a marquee that
    /// starts and ends on a multiple of it, so two rectangles drawn a minute
    /// apart line up without anyone measuring.
    ///
    /// Off by default. It changes what a drag does, and a drag that quietly
    /// disobeys is worse than one that needs a menu item first.
    public var snapGrid: Int

    /// Highlighter opacity, 0...1.
    public var highlighterOpacity: Double
    /// The highlighter's own colour, remembered apart from the colour pair.
    ///
    /// **Sharing the pair made the tool close to useless.** It took the current
    /// foreground and applied the opacity, so the highlighter a fresh document
    /// hands you is translucent *black* — a grey smear. Getting yellow meant
    /// changing the global colour, highlighting, then changing it back before
    /// drawing anything else, every single time. The complaint in the wild is
    /// exactly this: "the pen and the highlighter should be separate and each one
    /// has a color."
    ///
    /// Yellow, because that is what a highlighter is. `nil` restores following
    /// the pair.
    public var highlighterColour: PaintColour?
    /// Mosaic cell size for the pixelate tool.
    public var pixelateBlockSize: Int
    /// How far the area outside a spotlight is darkened. Clamped to 0.1...0.9: a
    /// spotlight that dims by nothing is a no-op, and one that dims to black hides
    /// the context that makes it a spotlight rather than a crop.
    public var spotlightDim: Double
    /// Which job the clone cell is doing.
    ///
    /// Two jobs on one rail cell because the *job* is repair and the Draw run has no
    /// legal sixth button. They differ by more than a brush tip does — source, what
    /// the first click means, parameters, undo name — and less than a second rail
    /// slot would justify.
    public var cloneMode: CloneMode
    /// How hard a clone stroke lays the copied pixels down, 0.1...1.
    public var cloneOpacity: Double
    /// How far Soften moves a pixel towards its blurred neighbourhood, 0.15...0.85.
    ///
    /// Not 1: at full strength one stroke melts a hard edge, which is smudge arriving
    /// by another road. Not below 0.15: a slider that can be a no-op is a dead control.
    public var softenStrength: Double
    /// Whether the clone nib has a soft edge.
    ///
    /// Its own setting rather than `brushShape`, because sharing that pair would make
    /// the first clone stroke inherit whatever the brush was doing and then change the
    /// brush on the way out. Soft by default: it hides a one-pixel misalignment at the
    /// edge of a patch, which is the whole reason a repair looks repaired.
    public var cloneSoftTip: Bool
    /// Whether a shape outline is antialiased.
    ///
    /// On, because a diagonal arrow across a screenshot is the most common mark this
    /// app makes and a stamped hard nib leaves a visible staircase on one. At a 3px
    /// weight the steps are wide enough to read as jagged at 100% zoom, which is the
    /// single thing that makes a drawing tool look cheap.
    ///
    /// Off is not a fallback, it is pixel art: every covered pixel fully covered, no
    /// half-lit neighbours, which is what you want when the image will be scaled with
    /// nearest-neighbour or its colours counted. The pencil ignores this entirely and
    /// is always hard, because that is the promise of the pencil.
    public var smoothEdges: Bool
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
        snapGrid: Int = 0,
        highlighterOpacity: Double = 0.38,
        highlighterColour: PaintColour? = PaintColour(hex: "FFE24D"),
        pixelateBlockSize: Int = 12,
        spotlightDim: Double = 0.45,
        smoothEdges: Bool = true,
        cloneMode: CloneMode = .clone,
        cloneOpacity: Double = 1,
        softenStrength: Double = 0.4,
        cloneSoftTip: Bool = true,
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
        self.snapGrid = max(0, snapGrid)
        self.highlighterOpacity = min(1, max(0.05, highlighterOpacity))
        self.highlighterColour = highlighterColour
        self.pixelateBlockSize = max(2, pixelateBlockSize)
        self.spotlightDim = min(max(spotlightDim, 0.1), 0.9)
        self.smoothEdges = smoothEdges
        self.cloneMode = cloneMode
        self.cloneOpacity = min(1, max(0.1, cloneOpacity))
        self.softenStrength = min(0.85, max(0.15, softenStrength))
        self.cloneSoftTip = cloneSoftTip
        self.strokeDash = strokeDash
        self.selectionKind = selectionKind
        self.selectionTolerance = min(255, max(0, selectionTolerance))
        self.sprayDensity = min(1, max(0.02, sprayDensity))
        self.textStyle = textStyle
    }

    /// The grid spacings offered, in pixels.
    ///
    /// Powers of two because that is what the things people align to are —
    /// icons, screenshots of UI, sprite cells — and four choices because a
    /// spacing picker with a slider invites tuning a number nobody can see the
    /// effect of until they drag.
    public static let snapGrids = [8, 16, 32, 64]

    /// The inks a highlighter actually comes in.
    ///
    /// Four, not a full picker: a highlighter's job is to leave the text under it
    /// readable, which rules out most of the palette before taste enters. These
    /// are the colours a real pack contains, and the last one is the pair for
    /// anyone who wants something else.
    public static let highlighterInks: [(name: String, colour: PaintColour)] = [
        ("Yellow", PaintColour(hex: "FFE24D")!),
        ("Green", PaintColour(hex: "8CE99A")!),
        ("Pink", PaintColour(hex: "FF8FC8")!),
        ("Blue", PaintColour(hex: "74C0FC")!),
    ]

    /// Range of the size control, and the bounds every size step honours.
    public static let sizeRange = 1...96

    /// The four one-click sizes, mirroring the weights the classic Size dropdown
    /// offered.
    ///
    /// **Here rather than in the options panel** because the first stop has to be
    /// the size a fresh brush opens at. When these lived beside the view that
    /// draws them, the two numbers were in different modules and drifted: the
    /// stops were 1 / 4 / 12 / 28 while the brush opened at 2, so the row every
    /// new user met was a segmented control with no segment selected —
    /// indistinguishable from a disabled one. Same file, one test, cannot drift.
    ///
    /// 1px is deliberately absent: that is the pencil's whole job, and the slider
    /// still reaches it.
    public static let sizeStops = [2, 6, 14, 28]

    /// As far as a tolerance slider is worth travelling.
    ///
    /// The sweep recorded against `fillTolerance` above measured coverage as stable
    /// from 8 through 32, and at 48 a probe in dark window chrome goes from 4% to
    /// 91% because adjacent near-blacks in a dark UI sit within 48 of each other.
    /// The sliders offered 0 to 128 anyway, so most of the track did not match more,
    /// it flooded the screenshot.
    ///
    /// 32 rather than 40, because 32 is the last value the sweep actually covered.
    /// Picking the middle of the untested gap would be the same guess this file
    /// spends a paragraph talking someone out of.
    ///
    /// The stored properties still clamp to 0...255, so an engine driven directly
    /// can go higher. This only bounds what the slider can dial in.
    public static let usefulTolerance = 32

    /// The sizes a given tool can actually paint at.
    ///
    /// `nib` clamps the highlighter to a 4px chisel, and for a long time nothing
    /// told the options panel that. The slider offered 1, the stop strip lit up 2,
    /// the readout said 2, and the stroke came out 4. Worse, `[` walked 4 → 3 → 2 → 1
    /// without changing a single pixel, which reads as a dead key rather than a
    /// clamp. A control that cannot be wrong beats a comment asking the next person
    /// to keep two numbers in step.
    public static func sizeRange(for tool: ToolKind) -> ClosedRange<Int> {
        tool == .highlighter ? 4...sizeRange.upperBound : sizeRange
    }

    /// The stop strip for a tool, with any stop below its floor pulled up to it.
    public static func sizeStops(for tool: ToolKind) -> [Int] {
        let floor = sizeRange(for: tool).lowerBound
        var seen = Set<Int>()
        return sizeStops.map { max($0, floor) }.filter { seen.insert($0).inserted }
    }

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
