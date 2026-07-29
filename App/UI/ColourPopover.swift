import PaintKit
import SwiftUI

/// The 28-swatch grid, on demand from the colour well.
///
/// The pair is restated at full size *above* the grid so the mapping from
/// "front / back" to the two chips is unambiguous — the compact overlapping
/// pair in the cluster is legible but not self-explanatory, and this is where
/// it gets explained.
///
/// Swatch selection uses a ring **inside** the cell, drawn in the material's
/// own label colour rather than the accent, because the accent already means
/// "selected tool" everywhere else in this chrome. An outer ring would also
/// shift every neighbour by a pixel as selection moved.
struct ColourPopover: View {
    @Bindable var model: EditorModel

    private static let columns = 14

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.snug) {
            header

            grid(model.palette.swatches, cell: { swatch($0) })
                .padding(Tokens.Space.tight)
                .background {
                    RoundedRectangle(cornerRadius: Tokens.Radius.well, style: .continuous)
                        .fill(.primary.opacity(0.08))
                }

            if !model.recentColours.isEmpty {
                Text("Recent")
                    .font(Tokens.Text.popoverHint)
                    .foregroundStyle(.primary.opacity(0.5))
                HStack(spacing: Tokens.Space.hair) {
                    ForEach(Array(model.recentColours.enumerated()), id: \.offset) { _, colour in
                        swatch(colour)
                    }
                }
            }

            Button {
                model.presentSystemColourPicker(for: .foreground)
            } label: {
                HStack(spacing: Tokens.Space.tight) {
                    Image(systemName: "eyedropper.halffull").font(.system(size: 10))
                    Text("Other colour…")
                }
                .font(Tokens.Text.popoverHint)
                .foregroundStyle(.primary.opacity(0.75))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(Tokens.Space.comfortable - 2)
        .frame(width: 340)
    }

    private var header: some View {
        HStack(spacing: Tokens.Space.snug) {
            ZStack(alignment: .topLeading) {
                largeChip(model.background)
                    .offset(x: 11, y: 9)
                largeChip(model.foreground)
            }
            .frame(
                width: Tokens.Size.colourPairLarge + 11,
                height: Tokens.Size.colourPairLarge + 9
            )

            VStack(alignment: .leading, spacing: 1) {
                Text("Front \(model.foreground.hexString) · Back \(model.background.hexString)")
                    .font(Tokens.Text.popoverTitle)
                Text("X swaps · ⇧⌘C opens this")
                    .font(Tokens.Text.popoverHint)
                    .foregroundStyle(.primary.opacity(0.55))
            }

            Spacer(minLength: 0)

            Button {
                model.swapColours()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Swap front and back (X)")
            .accessibilityLabel("Swap front and back colours")
        }
    }

    private func grid<Cell: View>(
        _ colours: [PaintColour], @ViewBuilder cell: @escaping (PaintColour) -> Cell
    ) -> some View {
        let rows = stride(from: 0, to: colours.count, by: Self.columns).map {
            Array(colours[$0..<min($0 + Self.columns, colours.count)])
        }
        return VStack(spacing: Tokens.Space.hair) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: Tokens.Space.hair) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, colour in
                        cell(colour)
                    }
                }
            }
        }
    }

    private func swatch(_ colour: PaintColour) -> some View {
        let isFront = colour == model.foreground
        let isBack = colour == model.background

        return Button {
            model.applySwatch(colour, to: .foreground)
        } label: {
            RoundedRectangle(cornerRadius: Tokens.Radius.swatch, style: .continuous)
                .fill(Color(cgColor: colour.cgColor))
                .frame(width: Tokens.Size.swatch, height: Tokens.Size.swatch)
                .overlay {
                    // Inset hairline: on glass, a white or near-white swatch
                    // would otherwise have no edge at all.
                    RoundedRectangle(cornerRadius: Tokens.Radius.swatch, style: .continuous)
                        .strokeBorder(.black.opacity(0.35), lineWidth: 0.5)
                }
                .overlay {
                    if isFront || isBack {
                        RoundedRectangle(cornerRadius: Tokens.Radius.swatch - 1.5, style: .continuous)
                            .strokeBorder(
                                colour.prefersDarkContrast ? Color.black : Color.white,
                                lineWidth: isFront ? 2 : 1
                            )
                            .padding(2)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(colour.hexString)
        .accessibilityLabel("Colour \(colour.hexString)")
        .accessibilityAddTraits(isFront ? [.isSelected, .isButton] : .isButton)
        .contextMenu {
            Button("Set as front") { model.applySwatch(colour, to: .foreground) }
            Button("Set as back") { model.applySwatch(colour, to: .background) }
        }
    }

    private func largeChip(_ colour: PaintColour) -> some View {
        RoundedRectangle(cornerRadius: Tokens.Radius.segmentInner, style: .continuous)
            .fill(Color(cgColor: colour.cgColor))
            .frame(width: Tokens.Size.colourPairLarge, height: Tokens.Size.colourPairLarge)
            .overlay {
                RoundedRectangle(cornerRadius: Tokens.Radius.segmentInner, style: .continuous)
                    .strokeBorder(.black.opacity(0.35), lineWidth: 0.5)
            }
    }
}
