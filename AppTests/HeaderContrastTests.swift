import AppKit
import Testing
@testable import ItsPaint

/// The dimensions read-out under the filename, against the well the window
/// paints behind it. Issue #29 was the light appearance's version of this at
/// about 2.4:1 — the hint step of the ink scale, at 10.5pt, on grey.
///
/// Measured off the real system colours for the appearance rather than off
/// constants, so a macOS that repaints `underPageBackgroundColor` moves the
/// number here too. 3:1 is the floor WCAG puts under any text at all; the
/// values as of writing are about 4:1 light and 6:1 dark.
@Suite("Header contrast")
@MainActor
struct HeaderContrastTests {
    /// WCAG relative luminance of an opaque sRGB colour.
    private static func luminance(_ colour: NSColor) -> Double {
        let c = colour.usingColorSpace(.sRGB) ?? colour
        func linear(_ channel: CGFloat) -> Double {
            let v = Double(channel)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(c.redComponent) + 0.7152 * linear(c.greenComponent)
            + 0.0722 * linear(c.blueComponent)
    }

    /// `ink` at `opacity` composited over an opaque `background`, as the eye sees it.
    /// `labelColor` carries its own alpha, which is part of the answer.
    private static func composite(_ ink: NSColor, opacity: Double, over background: NSColor) -> NSColor {
        let i = ink.usingColorSpace(.sRGB) ?? ink
        let b = background.usingColorSpace(.sRGB) ?? background
        let a = Double(i.alphaComponent) * opacity
        func mix(_ x: CGFloat, _ y: CGFloat) -> CGFloat { CGFloat(a) * x + CGFloat(1 - a) * y }
        return NSColor(
            srgbRed: mix(i.redComponent, b.redComponent),
            green: mix(i.greenComponent, b.greenComponent),
            blue: mix(i.blueComponent, b.blueComponent),
            alpha: 1
        )
    }

    /// Contrast of the subtitle's ink at `opacity` in the named appearance.
    static func subtitleContrast(at opacity: Double, in appearance: NSAppearance.Name) -> Double {
        var ratio = 0.0
        NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
            let well = NSColor.underPageBackgroundColor
            let text = composite(.labelColor, opacity: opacity, over: well)
            let lighter = max(luminance(text), luminance(well))
            let darker = min(luminance(text), luminance(well))
            ratio = (lighter + 0.05) / (darker + 0.05)
        }
        return ratio
    }

    @Test("The dimensions read-out clears 3:1 in the light appearance")
    func legibleInLight() {
        #expect(Self.subtitleContrast(at: Tokens.Ink.muted, in: .aqua) >= 3)
    }

    @Test("The dimensions read-out clears 3:1 in the dark appearance")
    func legibleInDark() {
        #expect(Self.subtitleContrast(at: Tokens.Ink.muted, in: .darkAqua) >= 3)
    }

    /// Positive control: the step it replaced has to fail this, or the check
    /// would have passed the bug it exists for.
    @Test("The hint step it replaced did not clear it in light")
    func theOldStepFails() {
        #expect(Self.subtitleContrast(at: Tokens.Ink.faint, in: .aqua) < 3)
    }
}
