import CoreGraphics
import Foundation
import Testing
@testable import PaintKit

@Suite("Core Graphics bridge")
struct CoreGraphicsBridgeTests {

    private func image(width: Int, height: Int) -> CGImage? {
        let (rowBytes, rowOverflow) = width.multipliedReportingOverflow(by: 4)
        let (byteCount, byteOverflow) = rowBytes.multipliedReportingOverflow(by: height)
        guard !rowOverflow, !byteOverflow else { return nil }
        let data = Data(repeating: 0, count: byteCount)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: rowBytes,
            space: Bitmap.colourSpace,
            bitmapInfo: Bitmap.bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    @Test("Bitmap survives a round trip through CGImage unchanged")
    func cgImageRoundTrip() throws {
        var original = Bitmap(width: 16, height: 9, fill: .white)
        Raster.fillRect(PixelRect(x: 2, y: 2, width: 5, height: 4),
                        colour: RGBA8(r: 200, g: 30, b: 60), into: &original)
        original.setPixel(RGBA8(r: 1, g: 2, b: 3), at: PixelPoint(x: 15, y: 8))

        let image = try #require(original.makeCGImage())
        #expect(image.width == 16 && image.height == 9)

        let restored = try #require(Bitmap(cgImage: image))
        // Exact equality — if the bridge resampled or reordered channels this
        // would drift, and every export would silently shift colour.
        #expect(restored == original)
    }

    @Test("Row order is preserved — the image is not vertically flipped")
    func rowOrderPreserved() throws {
        var original = Bitmap(width: 4, height: 4, fill: .white)
        original.setPixel(.black, at: PixelPoint(x: 0, y: 0))  // top-left

        let image = try #require(original.makeCGImage())
        let restored = try #require(Bitmap(cgImage: image))
        #expect(restored.pixel(at: PixelPoint(x: 0, y: 0)) == .black)
        #expect(restored.pixel(at: PixelPoint(x: 0, y: 3)) == .white)
    }

    @Test("Core Graphics drawing lands in y-down canvas coordinates")
    func coreGraphicsIsFlippedForUs() {
        var bitmap = Bitmap(width: 10, height: 10, fill: .white)
        bitmap.drawWithCoreGraphics { context in
            context.setFillColor(PaintColour.black.cgColor)
            // Canvas coordinates: this is the TOP-left corner.
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        #expect(bitmap.pixel(at: PixelPoint(x: 1, y: 1)) == .black)
        #expect(bitmap.pixel(at: PixelPoint(x: 1, y: 8)) == .white)
    }

    @Test("A CGImage snapshot is independent of later canvas edits")
    func snapshotIsDetached() throws {
        var bitmap = Bitmap(width: 8, height: 8, fill: .white)
        let image = try #require(bitmap.makeCGImage())
        bitmap.fillAll(with: .black)

        // The view keeps the last image while the next stroke is already
        // writing; sharing the buffer would tear.
        let snapshot = try #require(Bitmap(cgImage: image))
        #expect(snapshot.pixels.allSatisfy { $0 == .white })
    }

    @Test("CGImage sources and resize targets must both fit the raster budget")
    func rejectsUnsupportedSourceAndTarget() throws {
        // Only one 80 KiB row is needed to represent a source whose dimension
        // exceeds the policy, so this exercises the rejection without a large
        // test allocation.
        let oversizedSource = try #require(
            image(width: Bitmap.maximumDimension + 1, height: 1)
        )
        #expect(Bitmap(cgImage: oversizedSource) == nil)

        let smallSource = try #require(image(width: 1, height: 1))
        #expect(Bitmap(
            cgImage: smallSource,
            resizedTo: (Bitmap.maximumDimension + 1, 1)
        ) == nil)
        #expect(Bitmap(cgImage: smallSource, resizedTo: (8_193, 4_096)) == nil)
    }
}

@Suite("Image codec")
struct ImageCodecTests {

    private func sampleBitmap() -> Bitmap {
        var bitmap = Bitmap(width: 12, height: 8, fill: .white)
        Raster.fillRect(PixelRect(x: 1, y: 1, width: 4, height: 3),
                        colour: RGBA8(r: 220, g: 40, b: 40), into: &bitmap)
        Raster.fillRect(PixelRect(x: 6, y: 3, width: 3, height: 3),
                        colour: RGBA8(r: 20, g: 90, b: 220), into: &bitmap)
        return bitmap
    }

    /// Patch a real one-pixel PNG's IHDR dimensions and CRC. The compressed
    /// payload deliberately remains tiny: a safe decoder must reject from the
    /// header before attempting to expand it.
    private func pngAdvertising(width: UInt32, height: UInt32) throws -> Data {
        var data = try ImageCodec.encode(
            Bitmap(width: 1, height: 1, fill: .black),
            as: .png
        )
        guard data.count >= 33 else { return Data() }

        writeBigEndian(width, into: &data, at: 16)
        writeBigEndian(height, into: &data, at: 20)
        let checksum = crc32(data[12..<29])
        writeBigEndian(checksum, into: &data, at: 29)
        return data
    }

    private func writeBigEndian(_ value: UInt32, into data: inout Data, at offset: Int) {
        data[offset] = UInt8(truncatingIfNeeded: value >> 24)
        data[offset + 1] = UInt8(truncatingIfNeeded: value >> 16)
        data[offset + 2] = UInt8(truncatingIfNeeded: value >> 8)
        data[offset + 3] = UInt8(truncatingIfNeeded: value)
    }

    private func crc32(_ bytes: Data.SubSequence) -> UInt32 {
        var checksum = UInt32.max
        for byte in bytes {
            checksum ^= UInt32(byte)
            for _ in 0..<8 {
                if checksum & 1 == 1 {
                    checksum = (checksum >> 1) ^ 0xEDB8_8320
                } else {
                    checksum >>= 1
                }
            }
        }
        return ~checksum
    }

    private func oversizedDimensions(
        from operation: () throws -> Bitmap
    ) -> (width: Int, height: Int)? {
        do {
            _ = try operation()
            return nil
        } catch let error as ImageCodec.CodecError {
            guard case .imageTooLarge(let width, let height) = error else {
                return nil
            }
            return (width, height)
        } catch {
            return nil
        }
    }

    @Test("PNG is lossless — every pixel survives the round trip")
    func pngIsLossless() throws {
        let original = sampleBitmap()
        let data = try ImageCodec.encode(original, as: .png)
        let restored = try #require(ImageCodec.decode(data: data))
        #expect(restored == original)
    }

    @Test("The formats every Mac can write are always offered")
    func coreFormatsAreAlwaysAvailable() {
        // Whatever else varies by OS version, these four do not — and if one
        // ever drops out of the export list, that is a platform change worth
        // finding here rather than in a bug report.
        for format in [ImageCodec.Format.png, .jpeg, .tiff, .gif] {
            #expect(format.isWritable, "\(format.displayName) is no longer writable")
            #expect(ImageCodec.Format.exportable.contains(format))
        }
    }

    @Test("TIFF is lossless")
    func tiffIsLossless() throws {
        let original = sampleBitmap()
        let data = try ImageCodec.encode(original, as: .tiff)
        let restored = try #require(ImageCodec.decode(data: data))
        #expect(restored == original)
    }

    @Test("Every format the export panel offers actually encodes")
    func everyFormatEncodes() throws {
        // The panel lists `exportable`, which filters by the encoders this
        // machine really has — AVIF, for one, is writable on some macOS
        // versions and not others. Testing `allCases` here asserted a promise
        // the app never makes, and failed on any OS missing an encoder.
        let bitmap = sampleBitmap()
        for format in ImageCodec.Format.exportable {
            let data = try ImageCodec.encode(bitmap, as: format)
            #expect(!data.isEmpty, "\(format.displayName) produced no data")
        }
    }

    @Test("Formats without alpha are flattened onto the matte, not blackened")
    func alphaIsFlattened() throws {
        var bitmap = Bitmap(width: 8, height: 8, fill: .clear)
        Raster.fillRect(PixelRect(x: 2, y: 2, width: 4, height: 4),
                        colour: .black, into: &bitmap)

        let data = try ImageCodec.encode(bitmap, as: .jpeg, matte: .white)
        let restored = try #require(ImageCodec.decode(data: data))
        let corner = try #require(restored.pixel(at: PixelPoint(x: 0, y: 0)))
        // JPEG is lossy, so assert "near white" rather than exact white.
        #expect(corner.r > 240 && corner.g > 240 && corner.b > 240)
    }

    @Test("Flattening composites transparency onto the matte colour")
    func flatteningIsExact() {
        var bitmap = Bitmap(width: 4, height: 4, fill: .clear)
        bitmap.setPixel(.black, at: PixelPoint(x: 1, y: 1))
        let flat = ImageCodec.flattened(bitmap, onto: PaintColour(hex: "FF0000")!)
        #expect(flat.pixel(at: PixelPoint(x: 0, y: 0)) == PaintColour(hex: "FF0000")!.rgba8)
        #expect(flat.pixel(at: PixelPoint(x: 1, y: 1)) == .black)
    }

    @Test("Format is inferred from the file extension, case-insensitively")
    func formatInference() {
        #expect(ImageCodec.Format.inferred(from: URL(fileURLWithPath: "/a/b.PNG")) == .png)
        #expect(ImageCodec.Format.inferred(from: URL(fileURLWithPath: "/a/b.jpg")) == .jpeg)
        #expect(ImageCodec.Format.inferred(from: URL(fileURLWithPath: "/a/b.heic")) == .heic)
        #expect(ImageCodec.Format.inferred(from: URL(fileURLWithPath: "/a/b.xyz")) == nil)
    }

    @Test("Writing to disk and reading back preserves the image")
    func diskRoundTrip() throws {
        let original = sampleBitmap()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("itspaint-codec-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        try ImageCodec.write(original, to: url)
        let restored = try ImageCodec.decode(contentsOf: url)
        #expect(restored == original)
    }

    @Test("Oversized PNG headers are rejected before URL or Data decoding")
    func oversizedHeaderPreflight() throws {
        let advertisedWidth = UInt32(Bitmap.maximumDimension + 1)
        let data = try pngAdvertising(width: advertisedWidth, height: 1)
        let sourceURL = URL(fileURLWithPath: "Pasted image")

        let dataDimensions = oversizedDimensions {
            try ImageCodec.decode(data: data, sourceURL: sourceURL)
        }
        #expect(dataDimensions?.width == Int(advertisedWidth))
        #expect(dataDimensions?.height == 1)
        #expect(ImageCodec.decode(data: data) == nil)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("itspaint-oversized-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)
        let urlDimensions = oversizedDimensions {
            try ImageCodec.decode(contentsOf: url)
        }
        #expect(urlDimensions?.width == Int(advertisedWidth))
        #expect(urlDimensions?.height == 1)
    }

    @Test("Malformed in-memory image data fails closed with its source label")
    func malformedDataFailsClosed() {
        let sourceURL = URL(fileURLWithPath: "Clipboard image")
        do {
            _ = try ImageCodec.decode(
                data: Data([0x89, 0x50, 0x4E, 0x47]),
                sourceURL: sourceURL
            )
            #expect(Bool(false), "Malformed image data unexpectedly decoded")
        } catch let error as ImageCodec.CodecError {
            guard case .decodeFailed(let reportedURL) = error else {
                #expect(Bool(false), "Malformed image returned the wrong codec error")
                return
            }
            #expect(reportedURL == sourceURL)
        } catch {
            #expect(Bool(false), "Malformed image returned a non-codec error")
        }
    }

    @Test("Opening a missing file reports a recoverable error")
    func missingFileErrors() {
        let url = URL(fileURLWithPath: "/definitely/not/here-\(UUID().uuidString).png")
        #expect(throws: (any Error).self) { try ImageCodec.decode(contentsOf: url) }
    }

    @Test("Every codec error offers a next step")
    func errorsHaveRecovery() {
        let errors: [ImageCodec.CodecError] = [
            .unreadableSource(URL(fileURLWithPath: "/x.png")),
            .unsupportedFormat("psd"),
            .decodeFailed(URL(fileURLWithPath: "/x.png")),
            .imageTooLarge(width: 30_000, height: 30_000),
            .encodeFailed(.png),
        ]
        for error in errors {
            #expect(error.errorDescription?.isEmpty == false)
            #expect(error.recoverySuggestion?.isEmpty == false)
        }
    }
}

@Suite("Image transforms")
struct ImageTransformTests {

    private func asymmetric() -> Bitmap {
        var bitmap = Bitmap(width: 6, height: 4, fill: .white)
        bitmap.setPixel(.black, at: PixelPoint(x: 0, y: 0))
        bitmap.setPixel(RGBA8(r: 255, g: 0, b: 0), at: PixelPoint(x: 5, y: 0))
        bitmap.setPixel(RGBA8(r: 0, g: 255, b: 0), at: PixelPoint(x: 0, y: 3))
        return bitmap
    }

    @Test("Flipping horizontally twice is the identity")
    func flipHorizontalInvolutive() {
        let original = asymmetric()
        let twice = ImageTransform.flippedHorizontally(
            ImageTransform.flippedHorizontally(original)
        )
        #expect(twice == original)
    }

    @Test("Flipping vertically twice is the identity")
    func flipVerticalInvolutive() {
        let original = asymmetric()
        let twice = ImageTransform.flippedVertically(
            ImageTransform.flippedVertically(original)
        )
        #expect(twice == original)
    }

    @Test("Horizontal flip moves the top-left marker to the top-right")
    func flipMovesCorners() {
        let flipped = ImageTransform.flippedHorizontally(asymmetric())
        #expect(flipped.pixel(at: PixelPoint(x: 5, y: 0)) == .black)
        #expect(flipped.pixel(at: PixelPoint(x: 0, y: 0)) == RGBA8(r: 255, g: 0, b: 0))
    }

    @Test("Rotating 90° swaps the dimensions")
    func rotationSwapsDimensions() {
        let rotated = ImageTransform.rotated(asymmetric(), by: .clockwise90)
        #expect(rotated.width == 4 && rotated.height == 6)
    }

    @Test("Four 90° rotations return the original bit-for-bit")
    func fourRotationsAreIdentity() {
        // Exact integer permutation, no resampling — this must be lossless or
        // repeatedly straightening an image would degrade it.
        var bitmap = asymmetric()
        for _ in 0..<4 { bitmap = ImageTransform.rotated(bitmap, by: .clockwise90) }
        #expect(bitmap == asymmetric())
    }

    @Test("Clockwise then counter-clockwise cancels out")
    func rotationsCancel() {
        let original = asymmetric()
        let there = ImageTransform.rotated(original, by: .clockwise90)
        let back = ImageTransform.rotated(there, by: .counterClockwise90)
        #expect(back == original)
    }

    @Test("Rotating 180° equals two 90° rotations")
    func halfTurnAgrees() {
        let original = asymmetric()
        let half = ImageTransform.rotated(original, by: .half)
        let twice = ImageTransform.rotated(
            ImageTransform.rotated(original, by: .clockwise90), by: .clockwise90
        )
        #expect(half == twice)
    }

    @Test("Crop extracts exactly the requested region")
    func cropExtracts() throws {
        var bitmap = Bitmap(width: 10, height: 10, fill: .white)
        Raster.fillRect(PixelRect(x: 3, y: 3, width: 4, height: 4), colour: .black, into: &bitmap)

        let cropped = try #require(ImageTransform.cropped(bitmap, to: PixelRect(x: 3, y: 3, width: 4, height: 4)))
        #expect(cropped.width == 4 && cropped.height == 4)
        #expect(cropped.pixels.allSatisfy { $0 == .black })
    }

    @Test("Growing the canvas keeps the artwork and reveals the fill")
    func canvasGrowth() {
        var bitmap = Bitmap(width: 4, height: 4, fill: .white)
        bitmap.setPixel(.black, at: PixelPoint(x: 0, y: 0))

        let grown = ImageTransform.resizedCanvas(bitmap, to: (8, 8), fill: PaintColour(hex: "FF0000")!)
        #expect(grown.width == 8 && grown.height == 8)
        #expect(grown.pixel(at: PixelPoint(x: 0, y: 0)) == .black)
        #expect(grown.pixel(at: PixelPoint(x: 7, y: 7)) == PaintColour(hex: "FF0000")!.rgba8)
    }

    @Test("Shrinking the canvas crops rather than scaling")
    func canvasShrink() {
        var bitmap = Bitmap(width: 8, height: 8, fill: .white)
        bitmap.setPixel(.black, at: PixelPoint(x: 1, y: 1))
        bitmap.setPixel(RGBA8(r: 255, g: 0, b: 0), at: PixelPoint(x: 7, y: 7))

        let shrunk = ImageTransform.resizedCanvas(bitmap, to: (4, 4))
        #expect(shrunk.width == 4)
        #expect(shrunk.pixel(at: PixelPoint(x: 1, y: 1)) == .black)
    }

    @Test("Nearest-neighbour doubling replicates pixels exactly")
    func nearestDoubling() throws {
        var bitmap = Bitmap(width: 2, height: 2, fill: .white)
        bitmap.setPixel(.black, at: PixelPoint(x: 0, y: 0))

        let scaled = try #require(ImageTransform.scaled(bitmap, to: (4, 4), using: .nearest))
        // A 2×2 block of black in the corner, no interpolated grey anywhere.
        for y in 0..<2 {
            for x in 0..<2 {
                #expect(scaled.pixel(at: PixelPoint(x: x, y: y)) == .black)
            }
        }
        #expect(scaled.pixel(at: PixelPoint(x: 3, y: 3)) == .white)
        #expect(scaled.pixels.allSatisfy { $0 == .black || $0 == .white })
    }

    @Test("Smooth scaling does not flip the image")
    func smoothScaleKeepsOrientation() throws {
        // Regression guard. `drawWithCoreGraphics` flips the context so path and
        // text drawing can use canvas coordinates; a CGImage sent through that
        // same flip lands upside down. The identity case returns early and the
        // percentage case only checks dimensions, so nothing caught this until
        // the generated app icon came out inverted.
        var bitmap = Bitmap(width: 64, height: 64, fill: .white)
        Raster.fillRect(PixelRect(x: 0, y: 0, width: 64, height: 16),
                        colour: .black, into: &bitmap)   // black band along the TOP

        let scaled = try #require(ImageTransform.scaled(bitmap, to: (128, 128), using: .smooth))
        let top = try #require(scaled.pixel(at: PixelPoint(x: 64, y: 8)))
        let bottom = try #require(scaled.pixel(at: PixelPoint(x: 64, y: 120)))
        #expect(top.r < 80, "band moved off the top — image is flipped")
        #expect(bottom.r > 180)
    }

    @Test("Nearest scaling does not flip either")
    func nearestScaleKeepsOrientation() throws {
        var bitmap = Bitmap(width: 32, height: 32, fill: .white)
        Raster.fillRect(PixelRect(x: 0, y: 0, width: 32, height: 8), colour: .black, into: &bitmap)

        let scaled = try #require(ImageTransform.scaled(bitmap, to: (64, 64), using: .nearest))
        #expect(try #require(scaled.pixel(at: PixelPoint(x: 32, y: 4))).r < 80)
        #expect(try #require(scaled.pixel(at: PixelPoint(x: 32, y: 60))).r > 180)
    }

    @Test("Percentage scaling computes the expected size")
    func percentScaling() throws {
        let bitmap = Bitmap(width: 100, height: 50)
        let scaled = try #require(
            ImageTransform.scaled(bitmap, horizontalPercent: 50, verticalPercent: 200, using: .nearest)
        )
        #expect(scaled.width == 50 && scaled.height == 100)
    }

    @Test("Scaling to the same size is a no-op")
    func identityScale() throws {
        let bitmap = asymmetric()
        let scaled = try #require(ImageTransform.scaled(bitmap, to: (6, 4), using: .smooth))
        #expect(scaled == bitmap)
    }

    @Test("Degenerate sizes are rejected instead of crashing")
    func rejectsZeroSize() {
        let bitmap = Bitmap(width: 4, height: 4)
        #expect(ImageTransform.scaled(bitmap, to: (0, 10)) == nil)
        #expect(ImageTransform.scaled(bitmap, to: (10, -5)) == nil)
        #expect(ImageTransform.cropped(bitmap, to: PixelRect(x: 99, y: 99, width: 4, height: 4)) == nil)
    }

    @Test("Transforms reject targets outside the shared raster budget")
    func rejectsOversizedTargets() {
        let bitmap = Bitmap(width: 4, height: 4)
        #expect(ImageTransform.scaled(
            bitmap,
            to: (Bitmap.maximumDimension + 1, 1),
            using: .nearest
        ) == nil)
        #expect(ImageTransform.scaled(
            bitmap,
            to: (8_193, 4_096),
            using: .smooth
        ) == nil)
        #expect(ImageTransform.scaled(
            bitmap,
            horizontalPercent: .infinity,
            verticalPercent: 100
        ) == nil)
        #expect(
            ImageTransform.resizedCanvas(
                bitmap,
                to: (Bitmap.maximumDimension + 1, 1)
            ) == bitmap
        )
    }

    @Test("Skewing grows the canvas to fit the sheared image")
    func skewGrowsCanvas() throws {
        let bitmap = Bitmap(width: 40, height: 40, fill: .white)
        let skewed = try #require(
            ImageTransform.skewed(bitmap, horizontalDegrees: 30, verticalDegrees: 0)
        )
        #expect(skewed.width > 40)
        #expect(skewed.height == 40)
    }

    @Test("Zero skew leaves the image untouched")
    func zeroSkewIsIdentity() throws {
        let bitmap = asymmetric()
        let skewed = try #require(
            ImageTransform.skewed(bitmap, horizontalDegrees: 0, verticalDegrees: 0)
        )
        #expect(skewed == bitmap)
    }
}
