import SwiftUI

/// A continuous value, shown as the thing it controls.
///
/// **Replaces `OptionRow` + `OptionSlider` + the size-stop capsules for tool options.**
/// That stack was four pieces saying one word: a 42pt right-aligned label, a stock
/// `Slider` at `.mini`, a trailing number, and a second row of capsules for the same
/// integer. Once one property is a label plus a grey pill, every property is a label
/// plus a grey pill, and after three rows the panel is one grey surface with no way to
/// tell which tool you are holding.
///
/// The rule this is built to: cover the panel's title and you should still know the
/// tool. So the size control carries a wedge that gets thicker to the right, the
/// highlighter's opacity control *is* a wash of the current ink, and a meter that only
/// reports a number recedes rather than competing. The property names itself, and the
/// word moves to VoiceOver where a name is worth having.
///
/// One `DragGesture(minimumDistance: 0)` over a `GeometryReader` rather than `Slider`,
/// because the AppKit knob is the giveaway that nobody looked at this panel.
struct Mark: View {

    enum Style {
        /// Size and stroke weight. A wedge, thin to thick, with ticks at the stops.
        case wedge(stops: [Int])
        /// Highlighter opacity. The track is the ink itself, 10% to 80%.
        case wash(ink: Color)
        /// Flow, match, block size. A plain fill that must not outrank a wedge.
        case meter
    }

    @Binding var value: Double
    let range: ClosedRange<Double>
    let style: Style
    /// The label VoiceOver reads. Deliberately not drawn.
    let name: String
    var gamma: Double = 1
    var readout: String
    /// Double-click restores this, so a panel is never a one-way door.
    var normal: Double

    @State private var isHovering = false
    @State private var isDragging = false
    @Environment(\.colorSchemeContrast) private var contrast

    private let trackHeight: CGFloat = 8
    private let hitHeight: CGFloat = 16

    /// Position on the track, 0...1, through the response curve.
    private var t: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        let linear = (value - range.lowerBound) / span
        return gamma == 1 ? linear : pow(min(max(linear, 0), 1), 1 / gamma)
    }

    private func value(atFraction f: Double) -> Double {
        let clamped = min(max(f, 0), 1)
        let curved = gamma == 1 ? clamped : pow(clamped, gamma)
        return range.lowerBound + curved * (range.upperBound - range.lowerBound)
    }

    private func fraction(of v: Double) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        let linear = (v - range.lowerBound) / span
        return gamma == 1 ? linear : pow(min(max(linear, 0), 1), 1 / gamma)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: Tokens.Space.hair) {
            Text(readout)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.primary.opacity(isDragging ? Tokens.Ink.strong : Tokens.Ink.regular))
                .frame(height: 14)
                .animation(Tokens.Motion.micro, value: isDragging)
            track
        }
        .accessibilityElement()
        .accessibilityLabel(name)
        .accessibilityValue(readout)
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) / 100
            switch direction {
            case .increment: value = min(range.upperBound, value + max(step, 1))
            case .decrement: value = max(range.lowerBound, value - max(step, 1))
            @unknown default: break
            }
        }
    }

    private var track: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                bed(width: width)
                if case .wedge(let stops) = style {
                    ForEach(stops, id: \.self) { stop in
                        tick(at: stop, width: width)
                    }
                }
                caret(width: width)
            }
            .frame(width: width, height: hitHeight)
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
            .onHover { hovering in
                isHovering = hovering
                // The pointer says which way this moves before it is touched.
                hovering ? NSCursor.resizeLeftRight.push() : NSCursor.pop()
            }
        }
        .frame(height: hitHeight)
    }

    /// The trough, or in the wash's case the ink itself.
    @ViewBuilder
    private func bed(width: CGFloat) -> some View {
        switch style {
        case .wash(let ink):
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(LinearGradient(
                    colors: [ink.opacity(0.10), ink.opacity(0.80)],
                    startPoint: .leading, endPoint: .trailing
                ))
                .overlay {
                    // Required in both appearances: a pale yellow ink over a light
                    // tint floor has no edge of its own.
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(.primary.opacity(contrast == .increased ? 0.5 : 0.18), lineWidth: 0.5)
                }
                .frame(height: trackHeight)
        case .wedge:
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(.primary.opacity(Tokens.Fill.track))
                .overlay(alignment: .leading) { Wedge().fill(.primary.opacity(Tokens.Ink.regular)).padding(1) }
                .overlay { increaseContrastEdge }
                .frame(height: trackHeight)
        case .meter:
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(.primary.opacity(Tokens.Fill.track))
                .overlay(alignment: .leading) {
                    GeometryReader { g in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(.primary.opacity(Tokens.Ink.muted))
                            .frame(width: max(0, g.size.width * t))
                    }
                    .padding(1)
                }
                .overlay { increaseContrastEdge }
                .frame(height: trackHeight)
        }
    }

    @ViewBuilder
    private var increaseContrastEdge: some View {
        if contrast == .increased {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(.primary.opacity(0.5), lineWidth: 1)
        }
    }

    private func caret(width: CGFloat) -> some View {
        Capsule(style: .continuous)
            .fill(.primary.opacity(isHovering || isDragging ? Tokens.Ink.strong : Tokens.Ink.regular))
            .frame(width: 1.5, height: 14)
            .offset(x: max(0, min(width - 1.5, width * t - 0.75)))
            .animation(Tokens.Motion.micro, value: isHovering)
    }

    /// A stop, drawn on the trough rather than as a second row of capsules below it.
    private func tick(at stop: Int, width: CGFloat) -> some View {
        let active = Int(value.rounded()) == stop
        return Capsule(style: .continuous)
            .fill(.primary.opacity(active ? Tokens.Ink.strong : Tokens.Ink.faint))
            .frame(width: active ? 1.5 : 1, height: active ? 12 : 10)
            .offset(x: width * fraction(of: Double(stop)))
            .allowsHitTesting(false)
            .help("\(stop) px")
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

/// The wedge inside a size trough: thin on the left, thick on the right, so the
/// control says "how wide" without the word.
private struct Wedge: Shape {
    func path(in rect: CGRect) -> Path {
        // Half a point at the thin end and the full trough at the thick end. An
        // earlier version ran 2pt to 6pt inside an 8pt trough, which at this size
        // read as a flat bar with no taper at all — the shape was there and the
        // information was not.
        var p = Path()
        let midY = rect.midY
        p.move(to: CGPoint(x: rect.minX, y: midY - 0.25))
        p.addLine(to: CGPoint(x: rect.maxX, y: midY - rect.height / 2))
        p.addLine(to: CGPoint(x: rect.maxX, y: midY + rect.height / 2))
        p.addLine(to: CGPoint(x: rect.minX, y: midY + 0.25))
        p.closeSubpath()
        return p
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
                .onHover { $0 ? NSCursor.resizeLeftRight.push() : NSCursor.pop() }
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
