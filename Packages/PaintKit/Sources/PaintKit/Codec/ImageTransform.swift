import CoreGraphics
import Foundation

/// Whole-image operations behind the Image menu.
///
/// Flip, rotate and crop are exact integer permutations of the pixel array —
/// no resampling, so rotating four times returns the identical file. Only the
/// operations that genuinely change sampling (resize, skew) go through Core
/// Graphics, and even then nearest-neighbour is offered so pixel art survives.
public enum ImageTransform {

    public enum Rotation: Int, CaseIterable, Sendable {
        case clockwise90 = 90
        case half = 180
        case counterClockwise90 = 270

        public var displayName: String {
            switch self {
            case .clockwise90: "Rotate 90° right"
            case .half: "Rotate 180°"
            case .counterClockwise90: "Rotate 90° left"
            }
        }
    }

    public enum Scaling: String, CaseIterable, Sendable, Identifiable {
        /// Blocky and exact. The right default for pixel art and screenshots.
        case nearest
        /// Interpolated. The right choice for photographs.
        case smooth

        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .nearest: "Sharp (nearest neighbour)"
            case .smooth: "Smooth"
            }
        }
    }

    // MARK: - Exact permutations

    public static func flippedHorizontally(_ bitmap: Bitmap) -> Bitmap {
        var out = bitmap
        for y in 0..<bitmap.height {
            for x in 0..<bitmap.width {
                let mirrored = PixelPoint(x: bitmap.width - 1 - x, y: y)
                out.setPixel(bitmap.unsafePixel(at: PixelPoint(x: x, y: y)), at: mirrored)
            }
        }
        return out
    }

    public static func flippedVertically(_ bitmap: Bitmap) -> Bitmap {
        var out = bitmap
        for y in 0..<bitmap.height {
            let mirroredY = bitmap.height - 1 - y
            for x in 0..<bitmap.width {
                out.setPixel(
                    bitmap.unsafePixel(at: PixelPoint(x: x, y: y)),
                    at: PixelPoint(x: x, y: mirroredY)
                )
            }
        }
        return out
    }

    public static func rotated(_ bitmap: Bitmap, by rotation: Rotation) -> Bitmap {
        switch rotation {
        case .half:
            var out = bitmap
            for y in 0..<bitmap.height {
                for x in 0..<bitmap.width {
                    out.setPixel(
                        bitmap.unsafePixel(at: PixelPoint(x: x, y: y)),
                        at: PixelPoint(x: bitmap.width - 1 - x, y: bitmap.height - 1 - y)
                    )
                }
            }
            return out

        case .clockwise90:
            var out = Bitmap(width: bitmap.height, height: bitmap.width, fill: .clear)
            for y in 0..<bitmap.height {
                for x in 0..<bitmap.width {
                    out.setPixel(
                        bitmap.unsafePixel(at: PixelPoint(x: x, y: y)),
                        at: PixelPoint(x: bitmap.height - 1 - y, y: x)
                    )
                }
            }
            return out

        case .counterClockwise90:
            var out = Bitmap(width: bitmap.height, height: bitmap.width, fill: .clear)
            for y in 0..<bitmap.height {
                for x in 0..<bitmap.width {
                    out.setPixel(
                        bitmap.unsafePixel(at: PixelPoint(x: x, y: y)),
                        at: PixelPoint(x: y, y: bitmap.width - 1 - x)
                    )
                }
            }
            return out
        }
    }

    /// Crop to `rect`, clipped to the image.
    public static func cropped(_ bitmap: Bitmap, to rect: PixelRect) -> Bitmap? {
        let extracted = bitmap.extract(rect)
        guard !extracted.rect.isEmpty else { return nil }
        return Bitmap(
            width: extracted.rect.width,
            height: extracted.rect.height,
            pixels: extracted.pixels
        )
    }

    /// Trim a uniform border, returning `nil` when there is nothing to trim.
    ///
    /// The common case is a pasted screenshot sitting in a slab of desktop:
    /// selecting that edge by hand is fiddly and easy to get one pixel wrong,
    /// and this is exact. The border colour is taken from the top-left pixel,
    /// which is what "the surrounding colour" means for a rectangular image.
    public static func trimmingUniformBorder(_ bitmap: Bitmap, tolerance: Int = 6) -> Bitmap? {
        let border = bitmap.unsafePixel(at: .zero)

        func rowIsBorder(_ y: Int) -> Bool {
            (0..<bitmap.width).allSatisfy {
                Raster.matches(bitmap.unsafePixel(at: PixelPoint(x: $0, y: y)), border, tolerance: tolerance)
            }
        }
        func columnIsBorder(_ x: Int) -> Bool {
            (0..<bitmap.height).allSatisfy {
                Raster.matches(bitmap.unsafePixel(at: PixelPoint(x: x, y: $0)), border, tolerance: tolerance)
            }
        }

        var top = 0
        while top < bitmap.height, rowIsBorder(top) { top += 1 }
        // Entirely one colour: trimming would leave nothing, so decline.
        guard top < bitmap.height else { return nil }

        var bottom = bitmap.height - 1
        while bottom > top, rowIsBorder(bottom) { bottom -= 1 }
        var left = 0
        while left < bitmap.width, columnIsBorder(left) { left += 1 }
        var right = bitmap.width - 1
        while right > left, columnIsBorder(right) { right -= 1 }

        let rect = PixelRect(
            x: left, y: top, width: right - left + 1, height: bottom - top + 1
        )
        guard rect != bitmap.bounds, !rect.isEmpty else { return nil }
        return cropped(bitmap, to: rect)
    }

    // MARK: - Canvas size

    /// Change the canvas size without scaling the artwork, anchored top-left —
    /// the "Attributes" operation. Growing reveals `fill`; shrinking crops.
    public static func resizedCanvas(
        _ bitmap: Bitmap, to size: (width: Int, height: Int), fill: PaintColour = .white
    ) -> Bitmap {
        guard Bitmap.isSizeSupported(width: size.width, height: size.height) else {
            return bitmap
        }
        var out = Bitmap(width: size.width, height: size.height, fill: fill.rgba8)
        // Replace rather than blend: a transparent source pixel must stay
        // transparent, not pick up the new canvas fill.
        let copyWidth = min(bitmap.width, size.width)
        let copyHeight = min(bitmap.height, size.height)
        for y in 0..<copyHeight {
            for x in 0..<copyWidth {
                out.setPixel(
                    bitmap.unsafePixel(at: PixelPoint(x: x, y: y)),
                    at: PixelPoint(x: x, y: y)
                )
            }
        }
        return out
    }

    // MARK: - Resampling

    /// Scale the artwork to a new pixel size.
    public static func scaled(
        _ bitmap: Bitmap,
        to size: (width: Int, height: Int),
        using scaling: Scaling = .smooth
    ) -> Bitmap? {
        guard Bitmap.isSizeSupported(width: size.width, height: size.height) else {
            return nil
        }
        if size.width == bitmap.width && size.height == bitmap.height { return bitmap }

        if scaling == .nearest {
            var out = Bitmap(width: size.width, height: size.height, fill: .clear)
            for y in 0..<size.height {
                let srcY = min(bitmap.height - 1, y * bitmap.height / size.height)
                for x in 0..<size.width {
                    let srcX = min(bitmap.width - 1, x * bitmap.width / size.width)
                    out.setPixel(
                        bitmap.unsafePixel(at: PixelPoint(x: srcX, y: srcY)),
                        at: PixelPoint(x: x, y: y)
                    )
                }
            }
            return out
        }

        guard let image = bitmap.makeCGImage() else { return nil }
        // NOT drawWithCoreGraphics: that flips the context for path drawing,
        // and a CGImage sent through the flip comes out upside down.
        return Bitmap(cgImage: image, resizedTo: size)
    }

    /// Scale by percentage, as the Stretch/Skew dialog expresses it.
    public static func scaled(
        _ bitmap: Bitmap,
        horizontalPercent: Double,
        verticalPercent: Double,
        using scaling: Scaling = .smooth
    ) -> Bitmap? {
        let rawWidth = (Double(bitmap.width) * horizontalPercent / 100).rounded()
        let rawHeight = (Double(bitmap.height) * verticalPercent / 100).rounded()
        guard rawWidth.isFinite, rawHeight.isFinite,
              rawWidth >= 1, rawHeight >= 1,
              rawWidth <= Double(Bitmap.maximumDimension),
              rawHeight <= Double(Bitmap.maximumDimension)
        else { return nil }
        let width = Int(rawWidth)
        let height = Int(rawHeight)
        guard Bitmap.isSizeSupported(width: width, height: height) else { return nil }
        return scaled(bitmap, to: (width, height), using: scaling)
    }

    /// Rotate by an arbitrary angle, growing the canvas so no corner is cut off.
    ///
    /// The quarter turns in `rotated(_:by:)` stay separate and stay exact: they
    /// are a pure index permutation, so every pixel survives untouched. This
    /// one resamples, which is unavoidable at any other angle — a rotated pixel
    /// grid does not land on a pixel grid — so it is deliberately *not* the
    /// implementation of the 90° cases. Rotating by 90 twice through here would
    /// soften the image; through `rotated` it is lossless.
    ///
    /// The canvas grows to the rotated bounding box and the corners it exposes
    /// are filled, because the alternative is silently cropping the picture the
    /// user asked to straighten.
    public static func rotated(
        _ bitmap: Bitmap,
        degrees: Double,
        fill: PaintColour = .white
    ) -> Bitmap? {
        // Anything landing on a quarter turn goes the lossless way.
        let normalised = degrees.truncatingRemainder(dividingBy: 360)
        let wrapped = normalised < 0 ? normalised + 360 : normalised
        if wrapped.rounded() == wrapped, let quarter = Rotation(rawValue: Int(wrapped)) {
            return rotated(bitmap, by: quarter)
        }

        let radians = wrapped * .pi / 180
        let cosine = abs(cos(radians))
        let sine = abs(sin(radians))
        let rawWidth = Double(bitmap.width) * cosine + Double(bitmap.height) * sine
        let rawHeight = Double(bitmap.width) * sine + Double(bitmap.height) * cosine

        guard rawWidth.isFinite, rawHeight.isFinite else { return nil }
        let newWidth = Int(rawWidth.rounded(.up))
        let newHeight = Int(rawHeight.rounded(.up))
        guard Bitmap.isSizeSupported(width: newWidth, height: newHeight),
              let image = bitmap.makeCGImage()
        else { return nil }

        var out = Bitmap(width: newWidth, height: newHeight, fill: fill.rgba8)
        out.drawWithCoreGraphics { context in
            context.interpolationQuality = .high
            // Rotate about the centre of the *new* canvas, then draw the source
            // centred on that origin — so the growth is shared equally on all
            // four sides instead of pushing the image into one corner.
            context.translateBy(x: CGFloat(newWidth) / 2, y: CGFloat(newHeight) / 2)
            context.rotate(by: CGFloat(radians))
            // Counter-flip: the surrounding context is flipped for canvas
            // coordinates, and a CGImage drawn through that lands upside down.
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(
                x: -Double(bitmap.width) / 2, y: -Double(bitmap.height) / 2,
                width: Double(bitmap.width), height: Double(bitmap.height)
            ))
        }
        return out
    }

    /// Skew by degrees on each axis, growing the canvas to fit the result.
    public static func skewed(
        _ bitmap: Bitmap,
        horizontalDegrees: Double,
        verticalDegrees: Double,
        fill: PaintColour = .white
    ) -> Bitmap? {
        let hRadians = horizontalDegrees * .pi / 180
        let vRadians = verticalDegrees * .pi / 180
        let tanH = tan(max(-1.4, min(1.4, hRadians)))
        let tanV = tan(max(-1.4, min(1.4, vRadians)))
        guard tanH != 0 || tanV != 0 else { return bitmap }

        let rawWidth = Double(bitmap.width) + abs(tanH) * Double(bitmap.height)
        let rawHeight = Double(bitmap.height) + abs(tanV) * Double(bitmap.width)
        guard rawWidth.isFinite, rawHeight.isFinite,
              rawWidth >= 1, rawHeight >= 1,
              rawWidth <= Double(Bitmap.maximumDimension),
              rawHeight <= Double(Bitmap.maximumDimension)
        else { return nil }
        let newWidth = Int(rawWidth)
        let newHeight = Int(rawHeight)
        guard Bitmap.isSizeSupported(width: newWidth, height: newHeight),
              let image = bitmap.makeCGImage()
        else { return nil }

        var out = Bitmap(width: newWidth, height: newHeight, fill: fill.rgba8)
        out.drawWithCoreGraphics { context in
            context.interpolationQuality = .high
            // Shift so the sheared image lands fully inside the grown canvas
            // rather than half of it hanging off the top-left.
            let offsetX = tanH < 0 ? abs(tanH) * Double(bitmap.height) : 0
            let offsetY = tanV < 0 ? abs(tanV) * Double(bitmap.width) : 0
            context.translateBy(x: CGFloat(offsetX), y: CGFloat(offsetY))
            context.concatenate(CGAffineTransform(1, CGFloat(tanV), CGFloat(tanH), 1, 0, 0))
            // Counter-flip: the surrounding context is flipped for canvas
            // coordinates, and a CGImage drawn through that lands upside down.
            context.translateBy(x: 0, y: CGFloat(bitmap.height))
            context.scaleBy(x: 1, y: -1)
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height)
            )
        }
        return out
    }
}
