import CoreGraphics
import Foundation

/// Keeps one canvas buffer alive for as long as Core Graphics reads it.
///
/// A class, so `Unmanaged` can hand Core Graphics an ownership token; `let`, so
/// the buffer it shares with the canvas can never move under an image that is
/// already pointing at it.
private final class PixelStorage {
    let pixels: [RGBA8]
    init(_ pixels: [RGBA8]) { self.pixels = pixels }
}

/// Conversion between `Bitmap` and Core Graphics.
///
/// The canvas format was chosen so this bridge is a memory reinterpretation
/// rather than a pixel-by-pixel conversion: RGBA8 premultiplied sRGB is exactly
/// `CGImageAlphaInfo.premultipliedLast` with `.byteOrder32Big`.
public extension Bitmap {

    static var colourSpace: CGColorSpace {
        CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    }

    static var bitmapInfo: CGBitmapInfo {
        CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
            .union(.byteOrder32Big)
    }

    var bytesPerRow: Int {
        let (bytes, overflow) = width.multipliedReportingOverflow(
            by: MemoryLayout<RGBA8>.stride
        )
        precondition(!overflow, "Bitmap row byte count overflowed")
        return bytes
    }

    /// Snapshot as a `CGImage`, sharing the canvas storage rather than copying
    /// it.
    ///
    /// This used to memcpy the whole raster into a `Data` on every call — a
    /// 131 MB copy per repaint on a 33-megapixel screenshot, and another one
    /// per save, per export, per copy-to-clipboard. Retaining the array in a box
    /// instead is O(1): the image and the canvas share one buffer until the next
    /// stroke writes, and copy-on-write then hands the *canvas* a fresh buffer,
    /// which is exactly the guarantee the old copy was buying — the image stays
    /// valid while the next stroke is already painting.
    ///
    /// The escaping base address is safe for precisely that reason: `storage`
    /// holds the only other reference, never mutates it, and outlives the image
    /// because Core Graphics releases the box itself.
    func makeCGImage() -> CGImage? {
        let storage = PixelStorage(pixels)
        let byteCount = pixels.count * MemoryLayout<RGBA8>.stride
        guard byteCount > 0,
              let base = storage.pixels.withUnsafeBytes(\.baseAddress)
        else { return nil }

        let box = Unmanaged.passRetained(storage)
        guard let provider = CGDataProvider(
            dataInfo: box.toOpaque(),
            data: base,
            size: byteCount,
            releaseData: { info, _, _ in
                guard let info else { return }
                Unmanaged<PixelStorage>.fromOpaque(info).release()
            }
        ) else {
            box.release()
            return nil
        }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: Self.colourSpace,
            bitmapInfo: Self.bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    /// Build a bitmap from any `CGImage`, normalising it into the canvas
    /// format. This is the single entry point for imported images, so nothing
    /// downstream ever has to cope with a foreign colour space or alpha layout.
    ///
    /// Pass `resizedTo` to resample in the same step.
    ///
    /// **This is the only correct way to draw a `CGImage` into a bitmap.**
    /// `drawWithCoreGraphics` flips the context so that path and text drawing
    /// can use canvas coordinates; a CGImage sent through that same flip lands
    /// upside down. Image work goes here, vector work goes there.
    init?(cgImage: CGImage, resizedTo target: (width: Int, height: Int)? = nil) {
        guard Bitmap.isSizeSupported(width: cgImage.width, height: cgImage.height) else {
            return nil
        }
        let width = target?.width ?? cgImage.width
        let height = target?.height ?? cgImage.height
        guard Bitmap.isSizeSupported(width: width, height: height) else { return nil }

        let (pixelCount, pixelOverflow) = width.multipliedReportingOverflow(by: height)
        let (rowBytes, rowOverflow) = width.multipliedReportingOverflow(
            by: MemoryLayout<RGBA8>.stride
        )
        let (_, byteOverflow) = rowBytes.multipliedReportingOverflow(by: height)
        guard !pixelOverflow, !rowOverflow, !byteOverflow else { return nil }

        var buffer = [RGBA8](repeating: .clear, count: pixelCount)
        let ok: Bool = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let context = CGContext(
                    data: base,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: rowBytes,
                    space: Bitmap.colourSpace,
                    bitmapInfo: Bitmap.bitmapInfo.rawValue
                  )
            else { return false }
            context.interpolationQuality = target == nil ? .none : .high
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { return nil }
        self.init(width: width, height: height, pixels: buffer)
    }

    // A `makeContext()` returning a bare `CGContext` over this bitmap was
    // removed deliberately: the only way to build one is to hand Core Graphics
    // a pointer into the pixel array, and that pointer is dangling the moment
    // the function returns. Anything drawn through it writes to freed memory.
    // `drawWithCoreGraphics` below is the safe equivalent — the pointer never
    // outlives the closure.

    /// Run Core Graphics drawing over this bitmap and keep the result.
    ///
    /// Core Graphics uses a y-up coordinate system while the canvas model is
    /// y-down (row 0 at the top, as every image format stores it). The flip is
    /// applied here, once, so no caller has to remember it.
    mutating func drawWithCoreGraphics(_ body: (CGContext) -> Void) {
        guard Self.isSizeSupported(width: width, height: height) else { return }
        let rowBytes = bytesPerRow
        let (byteCount, overflow) = rowBytes.multipliedReportingOverflow(by: height)
        guard !overflow else { return }
        pixels.withUnsafeMutableBytes { raw in
            guard raw.count == byteCount,
                  let base = raw.baseAddress,
                  let context = CGContext(
                    data: base,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: rowBytes,
                    space: Bitmap.colourSpace,
                    bitmapInfo: Bitmap.bitmapInfo.rawValue
                  )
            else { return }

            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            body(context)
        }
    }
}

public extension PixelRect {
    /// The smallest pixel rect fully containing `rect`.
    init(enclosing rect: CGRect) {
        let integral = rect.integral
        self.init(
            x: Int(integral.minX),
            y: Int(integral.minY),
            width: Int(integral.width),
            height: Int(integral.height)
        )
    }
}

public extension PaintColour {
    var cgColor: CGColor {
        CGColor(
            colorSpace: Bitmap.colourSpace,
            components: [
                CGFloat(red), CGFloat(green), CGFloat(blue), CGFloat(alpha),
            ]
        ) ?? CGColor(gray: 0, alpha: 1)
    }
}
