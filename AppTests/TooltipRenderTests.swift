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
}
