import SwiftUI

/// A continuous value, as one object you can read and drag.
///
/// **Every continuous value in the tool options panel is one of these.**
///
/// A field and a slider in the same 26pt: the name on the left, the value on the
/// right, and the fill behind them is the value again. Nothing sits on a line of its
/// own, so a panel of three values is three rows rather than six, and every row
/// starts and ends at the same x without a label column to line up.
///
/// The styles still say what the number is for. Size carries a dot that is the
/// nib, drawn to scale, and stops along its foot. The highlighter's fill is its own
/// ink. A meter only reports a number and recedes.
///
/// One `DragGesture(minimumDistance: 0)` over a `GeometryReader` rather than `Slider`,
/// because the AppKit knob is the giveaway that nobody looked at this panel.
struct Mark: View {

    enum Style {
        /// Size and stroke weight. The nib to scale, with dots at the stops.
        case wedge(stops: [Int])
        /// Highlighter opacity. The fill is the ink itself, at that opacity.
        case wash(ink: Color)
        /// Flow, match, block size. A plain fill and nothing more.
        case meter
    }

    @Binding var value: Double
    let range: ClosedRange<Double>
    let style: Style
    /// Drawn at the head of the track, and read by VoiceOver.
    let name: String
    var gamma: Double = 1
    var readout: String
    /// Double-click restores this, so a panel is never a one-way door.
    var normal: Double

    @State private var isHovering = false
    @State private var isDragging = false
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.optionsAxisIsVertical) private var isVertical

    private let height = Tokens.Size.optionControl

    // MARK: - The curve

    /// Where a value sits on the track, 0...1, through the response curve.
    ///
    /// Static and public to the module so the mapping can be checked without a
    /// view: it is arithmetic, it is what the control is *for*, and it was
    /// previously three private copies of two lines that had already drifted —
    /// `fraction(of:)` clamped and `t` did not.
    static func fraction(of value: Double, in range: ClosedRange<Double>, gamma: Double) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        let linear = min(max((value - range.lowerBound) / span, 0), 1)
        return gamma == 1 ? linear : pow(linear, 1 / gamma)
    }

    static func value(atFraction f: Double, in range: ClosedRange<Double>, gamma: Double) -> Double {
        let clamped = min(max(f, 0), 1)
        let curved = gamma == 1 ? clamped : pow(clamped, gamma)
        return range.lowerBound + curved * (range.upperBound - range.lowerBound)
    }

    /// Position on the track, 0...1.
    ///
    /// **Clamped, which it was not.** A model value can legitimately sit outside a
    /// mark's own range — `ToolSettings` lets the spray's density reach 1 while
    /// the Flow mark stops at 0.6 — and the meter's fill is an unclipped overlay,
    /// so an out-of-range value painted straight past the end of its own trough.
    /// The gamma path clamped; the linear path did not, and every mark that does
    /// not bend its travel takes the linear path.
    private var t: Double { Self.fraction(of: value, in: range, gamma: gamma) }

    private func value(atFraction f: Double) -> Double {
        Self.value(atFraction: f, in: range, gamma: gamma)
    }

    private func fraction(of v: Double) -> Double {
        Self.fraction(of: v, in: range, gamma: gamma)
    }

    var body: some View {
        track
        // A `GeometryReader` offers only 10pt intrinsically, so a mark measuring
        // its own row along the bottom bar collapses to a stub. Here rather than
        // at each call site: it was on `widthMark` alone, and the six controls
        // that used to be stock sliders need it just as much.
        .frame(minWidth: isVertical ? nil : Tokens.Size.horizontalMarkMinimum)
        .accessibilityElement()
        .accessibilityLabel(name)
        .accessibilityValue(readout)
        .accessibilityAdjustableAction { direction in
            // **One step for integers, a twentieth for fractions.** `max(step, 1)`
            // was correct for a 1...96 size and catastrophic for a 0.1...0.8 ink:
            // a single VoiceOver increment jumped the whole range, so every
            // fractional mark in the panel had exactly two reachable values.
            let span = range.upperBound - range.lowerBound
            let step = span >= 8 ? 1 : span / 20
            switch direction {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            @unknown default: break
            }
        }
    }

    private var track: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                bed(width: width)
                if isHovering || isDragging {
                    if case .wedge(let stops) = style {
                        ForEach(stops, id: \.self) { stop in
                            tick(at: stop, width: width)
                        }
                    }
                    caret(width: width)
                }
                caption
            }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        isDragging = true
                        value = snapped(value(atFraction: g.location.x / width), width: width, x: g.location.x)
                    }
                    .onEnded { _ in isDragging = false }
            )
            .onTapGesture(count: 2) { value = normal }
            .onHover { isHovering = $0 }
            // The pointer says which way this moves before it is touched.
            .hoverCursor(.resizeLeftRight)
        }
        .frame(height: height)
    }

    /// The trough, and the value filling it from the left.
    private func bed(width: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.segmentTrack, style: .continuous)
        return shape
            .fill(.primary.opacity(Tokens.Fill.track))
            .animation(Tokens.Motion.micro, value: isHovering)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(fill)
                    .frame(width: max(0, width * t))
            }
            .clipShape(shape)
            .overlay {
                if contrast == .increased { shape.strokeBorder(.primary.opacity(0.5), lineWidth: 1) }
            }
    }

    private var fill: AnyShapeStyle {
        if case .wash(let ink) = style { return AnyShapeStyle(ink.opacity(value)) }
        return AnyShapeStyle(.primary.opacity(isDragging || contrast == .increased ? Tokens.Fill.markActive : Tokens.Fill.mark))
    }

    /// The name and the number, over the fill and out of the pointer's way.
    private var caption: some View {
        HStack(spacing: Tokens.Space.tight) {
            Text(name)
                .foregroundStyle(.primary.opacity(Tokens.Ink.regular))
                .fixedSize()
            Spacer(minLength: 0)
            if case .wedge = style { nib }
            Text(readout)
                .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                .foregroundStyle(.primary.opacity(Tokens.Ink.strong))
                .fixedSize()
        }
        .font(.system(size: 11.5))
        // A pale ink can sit under the words, so the words bring their own edge.
        .shadow(color: isWash ? .black.opacity(0.45) : .clear, radius: 1)
        .padding(.horizontal, Tokens.Space.snug)
        .allowsHitTesting(false)
    }

    private var isWash: Bool {
        if case .wash = style { true } else { false }
    }

    /// The nib, to scale for as far as the row has room, in place of a word for it.
    private var nib: some View {
        Circle()
            .fill(.primary.opacity(Tokens.Ink.regular))
            .frame(width: 2 + 12 * CGFloat(t), height: 2 + 12 * CGFloat(t))
            .frame(width: 14, height: 14)
    }

    /// A line at the end of the fill, for as long as the pointer is here: the moment
    /// anybody is asking whether this drags. At rest the fill's own edge is the value,
    /// and a line would only cut through the name at the low end of the track.
    private func caret(width: CGFloat) -> some View {
        let thickness: CGFloat = 2.5
        return Capsule(style: .continuous)
            .fill(.primary.opacity(Tokens.Ink.strong))
            .frame(width: thickness, height: height - 8)
            .offset(x: max(2, min(width - thickness - 2, width * CGFloat(t) - thickness / 2)))
    }

    /// A stop, as a dot along the foot of the track, clear of the words. Only under the
    /// pointer, because that is the only time they do anything.
    private func tick(at stop: Int, width: CGFloat) -> some View {
        let active = Int(value.rounded()) == stop
        return Circle()
            .fill(.primary.opacity(active ? Tokens.Ink.strong : Tokens.Ink.faint))
            .frame(width: 2.5, height: 2.5)
            .offset(x: width * CGFloat(fraction(of: Double(stop))) - 1.25, y: height / 2 - 4)
            .allowsHitTesting(false)
    }

    /// Within three points of a stop, take the stop. Leave the band and it is free
    /// again, so the stops are a convenience rather than a cage.
    private func snapped(_ raw: Double, width: CGFloat, x: CGFloat) -> Double {
        guard case .wedge(let stops) = style else { return raw }
        for stop in stops where abs(width * fraction(of: Double(stop)) - x) <= 3 {
            return Double(stop)
        }
        return raw
    }
}

/// Spotlight's dim, as a plate whose darkness is the value.
///
/// The one panel with a single property, so the panel is that property. A trough with
/// a caret and the word "Dim" would describe the setting; this shows it. Black in both
/// appearances, because dimming is physically dark and a light-mode "dim" that lightens
/// would be a lie about what the tool does.
struct SpotlightDimPlate: View {
    @Binding var dim: Double
    var height: CGFloat = 36

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: Tokens.Radius.segmentTrack, style: .continuous)
                .fill(Color.black.opacity(dim))
                .overlay {
                    // Always, so a 10% plate is still an object rather than a gap.
                    RoundedRectangle(cornerRadius: Tokens.Radius.segmentTrack, style: .continuous)
                        .strokeBorder(.primary.opacity(contrast == .increased ? 0.5 : 0.20),
                                      lineWidth: contrast == .increased ? 1 : 0.5)
                }
                .overlay {
                    Text("\(Int((dim * 100).rounded()))%")
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        // Past 40% the plate is dark enough that white is the readable
                        // choice; below it the plate is nearly the panel and the label
                        // has to behave like panel text.
                        .foregroundStyle(dim >= 0.40 ? AnyShapeStyle(Color.white.opacity(0.92))
                                                     : AnyShapeStyle(.primary.opacity(Tokens.Ink.strong)))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { g in
                        dim = min(0.9, max(0.1, g.location.x / geo.size.width))
                    }
                )
                .hoverCursor(.resizeLeftRight)
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Dim")
        .accessibilityValue("\(Int((dim * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: dim = min(0.9, dim + 0.05)
            case .decrement: dim = max(0.1, dim - 0.05)
            @unknown default: break
            }
        }
    }
}

extension View {
    /// Show `cursor` while the pointer is over this view.
    ///
    /// `push` and `pop` are one stack for the whole app, so a panel that closed under
    /// the pointer, which a tool shortcut does, used to skip its `pop` and leave the
    /// cursor behind for good. The modifier pops on disappearing too.
    func hoverCursor(_ cursor: NSCursor) -> some View { modifier(HoverCursor(cursor: cursor)) }
}

private struct HoverCursor: ViewModifier {
    let cursor: NSCursor
    @State private var isPushed = false

    func body(content: Content) -> some View {
        content
            .onHover { set($0) }
            .onDisappear { set(false) }
    }

    private func set(_ pushed: Bool) {
        guard pushed != isPushed else { return }
        isPushed = pushed
        pushed ? cursor.push() : NSCursor.pop()
    }
}
