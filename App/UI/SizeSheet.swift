import PaintKit
import SwiftUI

/// Resize the artwork, or resize the canvas around it.
///
/// One sheet with two modes rather than two dialogs, because the distinction is
/// exactly what people get wrong — "resize" that scales the picture versus
/// "resize" that changes how much room there is around it. Putting them side by
/// side with a plain-language explanation of each is what makes the choice
/// obvious instead of a coin flip.
struct SizeSheet: View {
    @Bindable var model: EditorModel
    @Environment(\.dismiss) private var dismiss

    enum Mode: String, CaseIterable, Identifiable {
        case scaleImage
        case canvasSize

        var id: String { rawValue }

        var title: String {
            switch self {
            case .scaleImage: "Image size"
            case .canvasSize: "Canvas size"
            }
        }

        var explanation: String {
            switch self {
            case .scaleImage: "Scales the whole picture. Everything gets bigger or smaller."
            case .canvasSize: "Changes how much room there is. The picture keeps its size."
            }
        }
    }

    @State private var mode: Mode = .scaleImage
    @State private var width: Int = 0
    @State private var height: Int = 0
    @State private var locksAspect = true
    @State private var scaling: ImageTransform.Scaling = .smooth

    private var originalAspect: Double {
        Double(model.canvasSize.width) / Double(max(1, model.canvasSize.height))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.comfortable) {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(mode.explanation)
                .font(Tokens.Text.popoverHint)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            dimensions

            if width > 0, height > 0,
               !Bitmap.isSizeSupported(width: width, height: height) {
                Text("Choose a smaller size. ItsPaint supports images up to 32 megapixels.")
                    .font(Tokens.Text.popoverHint)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if mode == .scaleImage {
                percentShortcuts
                Picker("Quality", selection: $scaling) {
                    ForEach(ImageTransform.Scaling.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.radioGroup)
                Text(scaling == .nearest
                     ? "Keeps hard edges. Right for pixel art and screenshots."
                     : "Blends pixels. Right for photographs.")
                    .font(Tokens.Text.popoverHint)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Text("\(model.canvasSize.width) × \(model.canvasSize.height) → \(width) × \(height)")
                    .font(Tokens.Text.readout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Apply") { apply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding(Tokens.Space.safeInset)
        .frame(width: 380)
        .onAppear(perform: reset)
        .onChange(of: mode) { _, _ in reset() }
    }

    private var dimensions: some View {
        HStack(alignment: .center, spacing: Tokens.Space.comfortable) {
            field("Width", value: $width) { newValue in
                guard locksAspect, mode == .scaleImage else { return }
                height = max(1, Int((Double(newValue) / originalAspect).rounded()))
            }
            field("Height", value: $height) { newValue in
                guard locksAspect, mode == .scaleImage else { return }
                width = max(1, Int((Double(newValue) * originalAspect).rounded()))
            }

            if mode == .scaleImage {
                Toggle(isOn: $locksAspect) {
                    Image(systemName: locksAspect ? "lock" : "lock.open")
                        .accessibilityLabel("Lock aspect ratio")
                }
                .toggleStyle(.button)
                .help("Keep the original proportions")
            }
        }
    }

    private func field(
        _ label: String, value: Binding<Int>, onEdit: @escaping (Int) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.tight) {
            Text(label).font(Tokens.Text.pillLabel).foregroundStyle(.secondary)
            TextField(
                label,
                value: Binding(
                    get: { value.wrappedValue },
                    set: { newValue in
                        value.wrappedValue = max(1, min(20_000, newValue))
                        onEdit(value.wrappedValue)
                    }
                ),
                format: .number
            )
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .frame(width: 92)
        }
    }

    /// The sizes people actually reach for, so the common case is one click
    /// rather than mental arithmetic.
    private var percentShortcuts: some View {
        HStack(spacing: Tokens.Space.tight) {
            ForEach([25, 50, 100, 200], id: \.self) { percent in
                Button("\(percent)%") {
                    width = max(1, model.canvasSize.width * percent / 100)
                    height = max(1, model.canvasSize.height * percent / 100)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Spacer()
        }
    }

    private var isValid: Bool {
        width > 0 && height > 0
            && Bitmap.isSizeSupported(width: width, height: height)
            && (width != model.canvasSize.width || height != model.canvasSize.height)
    }

    private func reset() {
        width = model.canvasSize.width
        height = model.canvasSize.height
    }

    private func apply() {
        switch mode {
        case .scaleImage:
            model.scaleImage(width: width, height: height, using: scaling)
        case .canvasSize:
            model.resizeCanvas(width: width, height: height)
        }
        dismiss()
    }
}
