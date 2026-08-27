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

    /// Render one chip and hand back the image, so every check in this file is
    /// looking at the same thing the pointer is.
    ///
    /// Dark, because that is where this chrome lives, and because rendering
    /// `.primary` text over a black background in the light scheme paints black on
    /// black: the first run of this file produced an image with the detail line
    /// perfectly present and perfectly invisible.
    private func render(_ title: String, _ shortcut: String?, _ detail: String?) throws -> NSImage {
        let view = Tooltip(title: title, shortcut: shortcut, detail: detail)
            .padding(10)
            .environment(\.colorScheme, .dark)
            .background(Color(white: 0.13))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return try #require(renderer.nsImage, "\(title) chip did not render")
    }

    /// The tallest a chip may be: a title and **two** lines under it.
    ///
    /// Derived by rendering, not written down. `66` used to be written down, and it
    /// was measured off a chip that was silently clipping its own third line — so
    /// the constant was not describing the design, it was describing the bug. A
    /// ceiling taken from a one-line chip plus one line's worth of growth cannot
    /// drift away from the thing it is bounding.
    private func twoLineCeiling() throws -> CGFloat {
        let bare = try render("Title", "C", nil).size.height
        let one = try render("Title", "C", "One line.").size.height
        return one + (one - bare)
    }

    @Test("Every tool with a tip renders one line of explanation")
    func tipsRenderAndStayOneOrTwoLines() throws {
        let withTips = ToolKind.allCases.filter { $0.tip != nil }
        #expect(withTips.contains(.clone))
        #expect(withTips.contains(.select))

        let ceiling = try twoLineCeiling()

        for tool in withTips {
            let image = try render(
                tool.displayName, String(tool.shortcut).uppercased(), tool.tip
            )

            // Wide enough to read, and not so tall it has wrapped into a paragraph.
            #expect(image.size.width <= 260, "\(tool) tip is \(image.size.width)pt wide")
            #expect(
                image.size.height <= ceiling,
                "\(tool) tip is \(image.size.height)pt — past the \(ceiling)pt two-line ceiling"
            )

            if let out = ProcessInfo.processInfo.environment["ITSPAINT_TIP_DIR"],
               let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try png.write(to: URL(fileURLWithPath: "\(out)/tip-\(tool.rawValue).png"))
            }
        }
    }

    /// **The check the size caps above cannot make.**
    ///
    /// A chip that measures itself for one line and then draws three is still
    /// comfortably under 66pt — it is under it *because* the last two lines were
    /// clipped away by the chip's own rounded-rectangle mask. Every assertion in
    /// this file that bounds the chip from above gets *more* true as the bug gets
    /// worse, which is the shape `docs/CHECKS_THAT_MISS.md` warns about.
    ///
    /// The only honest property is the one the eye uses: a longer sentence makes a
    /// taller chip. No font arithmetic, no magic constant to tune.
    @Test("A chip grows with the sentence it carries")
    func chipHeightTracksItsDetail() throws {
        func height(_ detail: String) throws -> CGFloat {
            let view = Tooltip(title: "Copy image", shortcut: "⌘C", detail: detail)
                .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            return try #require(renderer.nsImage, "chip did not render").size.height
        }

        let one = try height("Short.")
        let two = try height("Puts it on the clipboard, ready to paste anywhere")
        let three = try height(
            "Puts it on the clipboard, ready to paste anywhere, in any app that "
                + "happens to be open at the time"
        )

        #expect(two > one, "a two-line tip is \(two)pt — the same as a one-line one")
        #expect(three > two, "a three-line tip is \(three)pt — the same as a two-line one")
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
    ///
    /// It returns a LEADING edge, not a centre, because the chip is pinned by its
    /// top-left corner so its top edge stays on one line whatever height it is.
    @Test("The header chip stays inside the window at either end of the row")
    func headerChipIsClamped() {
        let window = CGRect(x: 0, y: 0, width: 900, height: 600)
        let chip = CGFloat(220)
        let centre = { (anchor: CGRect, container: CGRect) in
            EditorView.tooltipLeading(under: anchor, in: container, chipWidth: chip) + chip / 2
        }

        // Under a button in the middle: centred on the button.
        let middle = CGRect(x: 440, y: 8, width: 26, height: 26)
        #expect(centre(middle, window) == middle.midX)

        // Under the last button before the right edge: pulled back inside.
        let trailing = CGRect(x: 870, y: 8, width: 26, height: 26)
        #expect(centre(trailing, window) + chip / 2 <= window.width)
        #expect(centre(trailing, window) < trailing.midX)
        // The leading edge itself is what gets used, so assert on it directly.
        #expect(EditorView.tooltipLeading(under: trailing, in: window, chipWidth: chip) >= 0)

        // And at the leading edge, the same in reverse.
        let leading = CGRect(x: 2, y: 8, width: 26, height: 26)
        #expect(EditorView.tooltipLeading(under: leading, in: window, chipWidth: chip) >= 0)
        #expect(centre(leading, window) > leading.midX)

        // A window narrower than the chip cannot contain it; centre it rather
        // than pinning it to one side and cutting the whole sentence off.
        let narrow = CGRect(x: 0, y: 0, width: 120, height: 600)
        #expect(centre(leading, narrow) == 60)
    }

    /// Every header chip hangs from one line, whatever height it is. That is the
    /// property the fixed offset buys, and the reason the chip is pinned by its
    /// top-left corner rather than positioned by its centre.
    @Test("The chip's top edge is clear of the header row")
    func headerChipSitsUnderTheHeader() {
        #expect(EditorView.tooltipTop > 0)
        // Below the row it explains, or it covers the buttons it is naming.
        #expect(EditorView.tooltipTop >= Tokens.Chrome.titleReserve - Tokens.Space.snug)
    }

    /// **The chip points at what it names, and stays in the window doing it.**
    ///
    /// The rail's chip used to be drawn by a second, dumber layer that offset it by
    /// a constant — so hovering the eyedropper, nine cells down, put the answer up
    /// beside the pencil, and a tall chip beside a low cell in a short window went
    /// off the bottom entirely. One layer now, one rule: the chip's near edge sits
    /// on a fixed line beside the chrome and slides along it to follow the control.
    @Test("The chip follows the control it names and never leaves the window")
    func theChipFollowsAndStaysInside() {
        let window = CGRect(x: 0, y: 0, width: 900, height: 600)
        let chip = CGSize(width: 220, height: 60)

        func origin(_ anchor: CGRect, rail: EditorModel.ChromeEdge) -> CGPoint {
            EditorView.tooltipOrigin(beside: anchor, in: window, chip: chip, rail: rail)
        }

        // A header control hangs from the header's one line, whatever the rail is
        // doing — that is what makes reading along the header move the text
        // sideways only.
        let headerButton = CGRect(x: 440, y: 9, width: 26, height: 26)
        for edge in [EditorModel.ChromeEdge.left, .bottom] {
            #expect(origin(headerButton, rail: edge).y == EditorView.tooltipTop)
        }

        // Down the side rail the chip stays in one column and tracks the cell.
        let high = CGRect(x: 8, y: 120, width: 34, height: 34)
        let low = CGRect(x: 8, y: 430, width: 34, height: 34)
        let column = Tokens.Chrome.railInset + Tokens.Rail.thickness + Tokens.Space.snug
        #expect(origin(high, rail: .left).x == column)
        #expect(origin(low, rail: .left).x == column)
        #expect(origin(low, rail: .left).y > origin(high, rail: .left).y,
                "the chip did not follow the cell down the rail")

        // Along the bottom bar it is the other way round: one line, sliding
        // sideways.
        let leftCell = CGRect(x: 20, y: 545, width: 34, height: 34)
        let rightCell = CGRect(x: 700, y: 545, width: 34, height: 34)
        #expect(origin(leftCell, rail: .bottom).y == origin(rightCell, rail: .bottom).y)
        #expect(origin(rightCell, rail: .bottom).x > origin(leftCell, rail: .bottom).x)

        // And at every extreme, both corners of the chip land inside the window.
        let corners = [
            (CGRect(x: 8, y: 60, width: 34, height: 34), EditorModel.ChromeEdge.left),
            (CGRect(x: 8, y: 590, width: 34, height: 34), .left),
            (CGRect(x: 2, y: 545, width: 34, height: 34), .bottom),
            (CGRect(x: 880, y: 545, width: 34, height: 34), .bottom),
            (CGRect(x: 880, y: 9, width: 26, height: 26), .left),
        ]
        for (anchor, edge) in corners {
            let point = origin(anchor, rail: edge)
            #expect(point.x >= 0, "chip starts at x \(point.x)")
            #expect(point.y >= 0, "chip starts at y \(point.y)")
            #expect(point.x + chip.width <= window.width, "chip ends at x \(point.x + chip.width)")
            #expect(point.y + chip.height <= window.height, "chip ends at y \(point.y + chip.height)")
        }
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
            // The rail's colour chips, which briefly put three clauses and a live
            // hex value in the *title* — a heading has no width cap, so the chip
            // came out about 380pt wide and nothing in this file could see it.
            ("Colour 1 · FF000059", "35% opaque. Double-click for another colour"),
            ("Colour 2 · 00000000", "Fully transparent, so it rubs paint out. Click to use it as Colour 1"),
            ("More colours", "Any colour, at any opacity. A fully clear one rubs paint out."),
        ]

        let ceiling = try twoLineCeiling()

        for (title, detail) in chips {
            let image = try render(title, "⌘C", detail)
            #expect(image.size.width <= 260, "\(title) chip is \(image.size.width)pt wide")
            #expect(
                image.size.height <= ceiling,
                "\(title) chip is \(image.size.height)pt — past the \(ceiling)pt two-line ceiling"
            )
        }
    }
}
