import Foundation

/// An sRGB colour in straight (un-premultiplied) floating-point components.
///
/// This is the *authoring* representation — what a swatch stores, what the
/// colour editor edits, what the document serialises. `RGBA8` is the *raster*
/// representation. Keeping them apart means picking a colour never quantises
/// through 8-bit premultiplied storage and back.
public struct PaintColour: Equatable, Hashable, Codable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red.clampedToUnit
        self.green = green.clampedToUnit
        self.blue = blue.clampedToUnit
        self.alpha = alpha.clampedToUnit
    }

    public static let black = PaintColour(red: 0, green: 0, blue: 0)
    public static let white = PaintColour(red: 1, green: 1, blue: 1)
    public static let clear = PaintColour(red: 0, green: 0, blue: 0, alpha: 0)

    /// Convert to the premultiplied 8-bit raster format.
    public var rgba8: RGBA8 {
        let a = UInt8((alpha * 255).rounded())
        guard a > 0 else { return .clear }
        @inline(__always) func premultiply(_ c: Double) -> UInt8 {
            UInt8(max(0, min(255, (c * alpha * 255).rounded())))
        }
        return RGBA8(r: premultiply(red), g: premultiply(green), b: premultiply(blue), a: a)
    }

    /// Build from a raster pixel, undoing premultiplication.
    public init(_ pixel: RGBA8) {
        let (r, g, b, a) = pixel.unpremultiplied
        self.init(
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            alpha: Double(a) / 255
        )
    }

    // MARK: - Hex

    /// Uppercase `RRGGBB`, or `RRGGBBAA` when not fully opaque.
    public var hexString: String {
        let r = Int((red * 255).rounded())
        let g = Int((green * 255).rounded())
        let b = Int((blue * 255).rounded())
        if alpha >= 1 {
            return String(format: "%02X%02X%02X", r, g, b)
        }
        return String(format: "%02X%02X%02X%02X", r, g, b, Int((alpha * 255).rounded()))
    }

    /// Parse `RGB`, `RRGGBB`, or `RRGGBBAA`, with or without a leading `#`.
    public init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.allSatisfy(\.isHexDigit) else { return nil }

        // Expand shorthand: F0A -> FF00AA.
        if text.count == 3 {
            text = text.map { "\($0)\($0)" }.joined()
        }
        guard text.count == 6 || text.count == 8, let value = UInt32(text, radix: 16) else {
            return nil
        }

        if text.count == 6 {
            self.init(
                red: Double((value >> 16) & 0xFF) / 255,
                green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255
            )
        } else {
            self.init(
                red: Double((value >> 24) & 0xFF) / 255,
                green: Double((value >> 16) & 0xFF) / 255,
                blue: Double((value >> 8) & 0xFF) / 255,
                alpha: Double(value & 0xFF) / 255
            )
        }
    }

    // MARK: - HSB

    /// Hue 0...360, saturation and brightness 0...1.
    public var hsb: (hue: Double, saturation: Double, brightness: Double) {
        let maxC = max(red, green, blue)
        let minC = min(red, green, blue)
        let delta = maxC - minC
        var hue = 0.0
        if delta > 0 {
            if maxC == red {
                hue = 60 * (((green - blue) / delta).truncatingRemainder(dividingBy: 6))
            } else if maxC == green {
                hue = 60 * (((blue - red) / delta) + 2)
            } else {
                hue = 60 * (((red - green) / delta) + 4)
            }
        }
        if hue < 0 { hue += 360 }
        return (hue, maxC == 0 ? 0 : delta / maxC, maxC)
    }

    public init(hue: Double, saturation: Double, brightness: Double, alpha: Double = 1) {
        // Wrap into 0..<360 first: a negative hue keeps its sign through
        // `truncatingRemainder`, lands in the default sector and comes back as
        // pure red — so -30° would silently stop meaning 330°.
        let wrapped = hue.truncatingRemainder(dividingBy: 360)
        let h = (wrapped < 0 ? wrapped + 360 : wrapped) / 60
        let s = saturation.clampedToUnit
        let v = brightness.clampedToUnit
        let c = v * s
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let m = v - c

        let (r, g, b): (Double, Double, Double)
        switch Int(h.rounded(.down)) {
        case 0: (r, g, b) = (c, x, 0)
        case 1: (r, g, b) = (x, c, 0)
        case 2: (r, g, b) = (0, c, x)
        case 3: (r, g, b) = (0, x, c)
        case 4: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        self.init(red: r + m, green: g + m, blue: b + m, alpha: alpha)
    }

    /// Relative luminance (WCAG). Used to decide whether a swatch needs a light
    /// or dark checkmark so the selection indicator never disappears into it.
    public var relativeLuminance: Double {
        @inline(__always) func linear(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    public var prefersDarkContrast: Bool { relativeLuminance > 0.45 }
}

private extension Double {
    var clampedToUnit: Double {
        if isNaN { return 0 }
        return Swift.max(0, Swift.min(1, self))
    }
}
