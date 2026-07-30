import AppKit
import PaintKit
import SwiftUI

/// Capture a signature, or pick one already captured.
///
/// Two routes in, because the two ways people have a signature are different. You
/// either sign it here and now — trackpad, mouse or tablet, all of which arrive as
/// pointer drags — or you already have a photo of one on paper and want that. Both
/// end up in the same place: keyed ink in the library.
///
/// The camera is deliberately absent for now. It needs a camera entitlement and a
/// permission prompt, which is a bigger ask than this feature earns before anyone
/// has used it; a photo taken with the phone and AirDropped is the same result
/// through a door that is already open.
struct SignatureSheet: View {
    @Bindable var model: EditorModel
    @Environment(\.dismiss) private var dismiss

    private var store: SignatureStore { .shared }

    @State private var strokes: [[CGPoint]] = []
    @State private var importFailure: String?

    /// Signing area, in points. Wide and short, because that is the shape of a
    /// signature and a square box invites people to draw in the middle of it.
    private static let stripSize = CGSize(width: 460, height: 150)

    /// The colour the signature is actually made of.
    ///
    /// Colour 1, so a blue-ink signature is one swatch away — but never a colour
    /// that would be invisible on the page. `prefersDarkContrast` is true for light
    /// colours, and signing in white on white paper would preview as nothing, save
    /// as nothing visible, and look like a broken feature rather than a bad choice.
    private var inkColour: PaintColour {
        model.foreground.prefersDarkContrast ? .black : model.foreground
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.comfortable) {
            Text("Signature")
                .font(.headline)

            if !store.signatures.isEmpty {
                saved
                Divider()
            }

            Text("Sign in the box, then Save. Ink is keyed to transparent, so it lands on artwork without a white patch behind it.")
                .font(Tokens.Text.popoverHint)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // **This strip is paper, and paper is white in both appearances.**
            // Which means none of its furniture may use `.primary`: in dark mode
            // `.primary` *is* white, so a `.primary`-tinted border and baseline on
            // a hard-coded white page are both invisible. Everything drawn on the
            // page is explicitly dark for that reason.
            SigningStrip(strokes: $strokes, ink: inkColour)
                .frame(width: Self.stripSize.width, height: Self.stripSize.height)
                .background {
                    RoundedRectangle(cornerRadius: Tokens.Radius.panel, style: .continuous)
                        .fill(.white)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Tokens.Radius.panel, style: .continuous)
                        .strokeBorder(.black.opacity(0.18), lineWidth: 1)
                }
                .overlay(alignment: .bottom) {
                    // A baseline, the way a paper form has one. It is what stops
                    // people signing across the middle of the box and getting a
                    // signature cropped top and bottom. It fades once there is ink
                    // on the page, so it never competes with the signature.
                    Rectangle()
                        .fill(.black.opacity(strokes.isEmpty ? 0.20 : 0.07))
                        .frame(height: 1)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 34)
                        .allowsHitTesting(false)
                        .animation(Tokens.Motion.micro, value: strokes.isEmpty)
                }
                .overlay(alignment: .bottomLeading) {
                    if strokes.isEmpty {
                        Text("Sign here")
                            .font(.system(size: 11))
                            .foregroundStyle(.black.opacity(0.28))
                            .padding(.leading, 30)
                            .padding(.bottom, 14)
                            .allowsHitTesting(false)
                    }
                }

            if let importFailure {
                Label(importFailure, systemImage: "exclamationmark.triangle")
                    .font(Tokens.Text.popoverHint)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Tokens.Space.base) {
                Button("Import Image…") { importFromFile() }
                Button("Clear") { strokes = [] }
                    .disabled(strokes.isEmpty)

                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { saveDrawn() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(strokes.isEmpty)
            }
        }
        .padding(Tokens.Space.safeInset)
        .frame(width: Self.stripSize.width + Tokens.Space.safeInset * 2)
    }

    // MARK: - The library

    private var saved: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.tight) {
            Text("Saved")
                .font(Tokens.Text.popoverTitle)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Tokens.Space.base) {
                    ForEach(store.signatures) { signature in
                        SignatureChip(signature: signature) {
                            model.insertSignature(signature.bitmap)
                            dismiss()
                        } delete: {
                            store.remove(signature)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: 62)
        }
    }

    // MARK: - Saving

    private func saveDrawn() {
        // Rasterise at twice the on-screen size, so a signature stamped onto a
        // Retina screenshot is not the softest thing in the picture.
        guard let drawn = Self.rasterise(
            strokes: strokes, in: Self.stripSize, scale: 2, colour: inkColour
        ) else { return }

        do {
            let signature = try store.add(capturing: drawn, colour: inkColour)
            model.insertSignature(signature.bitmap)
            dismiss()
        } catch {
            importFailure = Self.message(for: error)
        }
    }

    private func importFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ImageCodec.readableContentTypes
        panel.allowsMultipleSelection = false
        panel.message = "Pick a photo or scan of your signature on paper."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let photo = try ImageCodec.decode(contentsOf: url)
            let signature = try store.add(capturing: photo, colour: inkColour)
            model.insertSignature(signature.bitmap)
            dismiss()
        } catch {
            importFailure = Self.message(for: error)
        }
    }

    private static func message(for error: any Error) -> String {
        switch error {
        case InkExtractor.Failure.noInkFound:
            "No signature found in that image — it needs dark ink on a light page."
        case InkExtractor.Failure.notASignature:
            "Most of that image is dark. Crop it closer to the signature and try again."
        default:
            (error as NSError).localizedDescription
        }
    }

    /// Draw the collected strokes into a bitmap with the engine's own raster.
    ///
    /// Not Core Graphics: this app already knows how to lay a soft round nib along
    /// a path, and using it means a captured signature is made of the same strokes
    /// the brush makes. The background stays transparent, so `InkExtractor` takes
    /// the alpha-trusting path rather than trying to estimate paper that was never
    /// there.
    static func rasterise(
        strokes: [[CGPoint]],
        in size: CGSize,
        scale: CGFloat,
        colour: PaintColour
    ) -> Bitmap? {
        let width = Int(size.width * scale), height = Int(size.height * scale)
        guard width > 0, height > 0, strokes.contains(where: { !$0.isEmpty }) else { return nil }

        var bitmap = Bitmap(width: width, height: height, fill: .clear)
        // Wide enough to read when the signature is scaled down onto a screenshot,
        // narrow enough that letters do not close up.
        let brush = Brush(shape: .soft, size: Int(3 * scale))

        for stroke in strokes {
            let points = stroke.map {
                PixelPoint(x: Int($0.x * scale), y: Int($0.y * scale))
            }
            guard let first = points.first else { continue }
            if points.count == 1 {
                Raster.stamp(brush, colour: colour.rgba8, at: first, into: &bitmap)
                continue
            }
            if points.count == 2 {
                Raster.strokeLine(
                    from: first, to: points[1], brush: brush, colour: colour.rgba8, into: &bitmap
                )
                continue
            }

            // **The same midpoint quadratics the strip previews**, so what is saved
            // is what was signed. Joining the raw samples with straight lines is
            // what the preview deliberately avoids, and doing it here turned a
            // quick flourish — where the samples are furthest apart — into a
            // visible polygon in the stamp while the box had shown a smooth curve.
            //
            // `through` is the curve's own halfway point, because `strokeCurve`
            // takes a point to pass through rather than a control point: a
            // quadratic at t=½ sits at (start + 2·control + end) / 4.
            var from = first
            for i in 1..<(points.count - 1) {
                let mid = PixelPoint(
                    x: (points[i].x + points[i + 1].x) / 2,
                    y: (points[i].y + points[i + 1].y) / 2
                )
                Raster.strokeCurve(
                    from: from,
                    through: PixelPoint(
                        x: (from.x + 2 * points[i].x + mid.x) / 4,
                        y: (from.y + 2 * points[i].y + mid.y) / 4
                    ),
                    to: mid,
                    brush: brush,
                    colour: colour.rgba8,
                    into: &bitmap
                )
                from = mid
            }
            Raster.strokeLine(
                from: from, to: points[points.count - 1],
                brush: brush, colour: colour.rgba8, into: &bitmap
            )
        }
        return bitmap
    }
}

/// One saved signature, on its own chequered tile so the transparency is visible.
private struct SignatureChip: View {
    let signature: SignatureStore.Signature
    let insert: () -> Void
    let delete: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: insert) {
            Image(nsImage: signature.preview)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 44)
                .padding(.horizontal, Tokens.Space.base)
                .frame(minWidth: 76)
                .background {
                    RoundedRectangle(cornerRadius: Tokens.Radius.chip, style: .continuous)
                        .fill(.primary.opacity(isHovering ? Tokens.Fill.hover : Tokens.Fill.cell))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Insert this signature")
        .accessibilityLabel(signature.accessibilityLabel)
        .contextMenu {
            Button("Insert") { insert() }
            Divider()
            Button("Delete", role: .destructive) { delete() }
        }
    }
}

extension SignatureStore.Signature {
    /// An `NSImage` for the chip. Built on demand rather than stored, so the store
    /// holds only pixels and nothing that has to be kept in step with them.
    ///
    /// Through PNG data, which is the route the pasteboard already uses — the only
    /// existing `Bitmap` to `NSImage` path, and the one that is known to preserve
    /// alpha correctly.
    var preview: NSImage {
        guard let data = try? ImageCodec.encode(bitmap, as: .png),
              let image = NSImage(data: data)
        else { return NSImage(size: NSSize(width: 1, height: 1)) }
        return image
    }
}
