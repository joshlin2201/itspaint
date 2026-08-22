import SwiftUI
import Testing
import PaintKit
@testable import ItsPaint

/// The tooltip gained a second line, and a layout nobody has looked at is a layout
/// nobody has checked. This renders it on its own, with no window and no hover, so
/// the chrome can be inspected and its size asserted.
@Suite("Tooltip layout")
@MainActor
struct TooltipRenderTests {

    @Test("Every tool with a tip renders one line of explanation")
    func tipsRenderAndStayOneOrTwoLines() throws {
        let withTips = ToolKind.allCases.filter { $0.tip != nil }
        #expect(withTips.contains(.clone))
        #expect(withTips.contains(.select))

        for tool in withTips {
            let view = Tooltip(
                title: tool.displayName,
                shortcut: String(tool.shortcut).uppercased(),
                detail: tool.tip
            )
            .padding(10)
            // Dark, because that is where this chrome lives, and because rendering
            // `.primary` text over a black background in the light scheme paints
            // black on black: the first run of this test produced an image with the
            // detail line perfectly present and perfectly invisible.
            .environment(\.colorScheme, .dark)
            .background(Color(white: 0.13))

            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try #require(renderer.nsImage, "\(tool) tooltip did not render")

            // Wide enough to read, and not so tall it has wrapped into a paragraph.
            #expect(image.size.width <= 260, "\(tool) tip is \(image.size.width)pt wide")
            #expect(image.size.height <= 66, "\(tool) tip wrapped to \(image.size.height)pt")

            if let out = ProcessInfo.processInfo.environment["ITSPAINT_TIP_DIR"],
               let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try png.write(to: URL(fileURLWithPath: "\(out)/tip-\(tool.rawValue).png"))
            }
        }
    }

    /// A tip must not restate the name, which is directly above it.
    @Test func aTipSaysSomethingTheTitleDoesNot() {
        for tool in ToolKind.allCases {
            guard let tip = tool.tip else { continue }
            #expect(!tip.lowercased().hasPrefix(tool.displayName.lowercased()),
                    "\(tool)'s tip opens by repeating its own name")
        }
    }

    /// The header's chip is positioned by hand, because its buttons sit in a
    /// capsule that clips anything drawn inside it. Whatever the arithmetic does,
    /// it must never leave the chip hanging off the window.
    @Test("The header chip stays inside the window at either end of the row")
    func headerChipIsClamped() {
        let window = CGRect(x: 0, y: 0, width: 900, height: 600)
        let chip = CGFloat(220)

        // Under a button in the middle: centred on the button.
        let middle = CGRect(x: 440, y: 8, width: 26, height: 26)
        #expect(
            EditorView.tooltipCentre(under: middle, in: window, chipWidth: chip) == middle.midX
        )

        // Under the last button before the right edge: pulled back inside.
        let trailing = CGRect(x: 870, y: 8, width: 26, height: 26)
        let clamped = EditorView.tooltipCentre(under: trailing, in: window, chipWidth: chip)
        #expect(clamped + chip / 2 <= window.width)
        #expect(clamped < trailing.midX)

        // And at the leading edge, the same in reverse.
        let leading = CGRect(x: 2, y: 8, width: 26, height: 26)
        let pushed = EditorView.tooltipCentre(under: leading, in: window, chipWidth: chip)
        #expect(pushed - chip / 2 >= 0)
        #expect(pushed > leading.midX)

        // A window narrower than the chip cannot contain it; centre it rather
        // than pinning it to one side and cutting the whole sentence off.
        let narrow = CGRect(x: 0, y: 0, width: 120, height: 600)
        #expect(
            EditorView.tooltipCentre(under: leading, in: narrow, chipWidth: chip) == 60
        )
    }

    /// The header's own chips carry a line of explanation, and the buttons they
    /// belong to are the ones people reported not recognising. They get the same
    /// size check the tools' tips get.
    @Test("Header chips read in one or two lines")
    func headerChipsAreReadable() throws {
        let chips: [(String, String)] = [
            ("Copy image", "Puts it on the clipboard, ready to paste anywhere"),
            ("Paste image", "Drops the clipboard onto the canvas, still movable"),
            ("Drag image out", "Pick the picture up and drop it into Slack, Mail or the Finder"),
            ("Signature", "Sign here, or drop in a signature you have already saved"),
            ("Duplicate", "Opens a copy in a new window"),
        ]

        for (title, detail) in chips {
            let view = Tooltip(title: title, shortcut: "⌘C", detail: detail)
                .padding(10)
                .environment(\.colorScheme, .dark)
                .background(Color(white: 0.13))
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try #require(renderer.nsImage, "\(title) chip did not render")
            #expect(image.size.width <= 260, "\(title) chip is \(image.size.width)pt wide")
            #expect(image.size.height <= 66, "\(title) chip wrapped to \(image.size.height)pt")
        }
    }
}
