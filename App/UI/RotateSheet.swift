import PaintKit
import SwiftUI

/// Rotate the artwork by any angle.
///
/// The quarter turns already live in the Image menu, because they are exact and
/// need no decision. This is for the other case — a photographed or scanned
/// image that is two degrees off level — where the useful part of the range is
/// tiny and lives either side of zero.
///
/// So the slider is ±45°, not 0–360: past 45° the right answer is a quarter
/// turn first, and spending the whole travel on angles nobody straightens by
/// makes one degree impossible to land on.
struct RotateSheet: View {
    @Bindable var model: EditorModel
    @Environment(\.dismiss) private var dismiss

    @State private var degrees: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.comfortable) {
            Text("Rotate")
                .font(.headline)

            Text("The canvas grows to fit the corners. New space is filled with Colour 2.")
                .font(Tokens.Text.popoverHint)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Tokens.Space.snug) {
                Slider(value: $degrees, in: -45...45, step: 0.5)
                    .labelsHidden()
                TextField("", value: $degrees, format: .number.precision(.fractionLength(0...1)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 62)
                    .multilineTextAlignment(.trailing)
                Text("°").foregroundStyle(.secondary)
            }

            // The angles worth one click. Half a degree is the common scan
            // correction; 45 is the one people reach for deliberately.
            HStack(spacing: Tokens.Space.tight) {
                ForEach([-45.0, -5.0, -1.0, 0.0, 1.0, 5.0, 45.0], id: \.self) { stop in
                    Button(stop == 0 ? "0" : String(format: "%+g", stop)) {
                        degrees = stop
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            HStack {
                Text(preview)
                    .font(Tokens.Text.popoverHint)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Rotate") {
                    model.rotate(degrees: degrees)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(degrees == 0)
            }
        }
        .padding(Tokens.Space.safeInset)
        .frame(width: 380)
    }

    /// The size the rotation will produce, so the canvas growth is not a
    /// surprise that only shows up after the fact.
    private var preview: String {
        let radians = abs(degrees) * .pi / 180
        let width = Double(model.canvasSize.width)
        let height = Double(model.canvasSize.height)
        let newWidth = Int((width * cos(radians) + height * sin(radians)).rounded(.up))
        let newHeight = Int((width * sin(radians) + height * cos(radians)).rounded(.up))
        return "\(newWidth) × \(newHeight)"
    }
}
