import AppKit
import PaintKit

/// Native selection and clipboard editing use AppKit attributes; documents and
/// exports use the same small, portable style runs as the CoreText renderer.
enum TextContent {
    static func attributes(_ style: TextRenderer.Style, zoom: Double) -> [NSAttributedString.Key: Any] {
        var scaled = style
        scaled.pointSize *= zoom
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = switch style.alignment {
        case .left: .left
        case .centre: .center
        case .right: .right
        }
        return [
            .font: scaled.makeFont() as NSFont,
            .foregroundColor: NSColor(cgColor: style.colour.cgColor) ?? .textColor,
            .underlineStyle: style.isUnderlined ? NSUnderlineStyle.single.rawValue : 0,
            .paragraphStyle: paragraph,
        ]
    }

    static func attributed(_ runs: [TextRun], zoom: Double) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        for run in runs {
            result.append(NSAttributedString(string: run.text, attributes: attributes(run.style, zoom: zoom)))
        }
        return result
    }

    static func style(_ attributes: [NSAttributedString.Key: Any], zoom: Double) -> TextRenderer.Style {
        let font = attributes[.font] as? NSFont ?? .systemFont(ofSize: 36 * zoom)
        let traits = NSFontManager.shared.traits(of: font)
        let colour = ((attributes[.foregroundColor] as? NSColor) ?? .black).usingColorSpace(.sRGB)
            ?? NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        let alignment = (attributes[.paragraphStyle] as? NSParagraphStyle)?.alignment ?? .left
        return TextRenderer.Style(
            fontName: NSFontManager.shared.convert(font, toNotHaveTrait: [.boldFontMask, .italicFontMask]).fontName,
            pointSize: font.pointSize / max(zoom, 0.01),
            colour: PaintColour(red: colour.redComponent, green: colour.greenComponent, blue: colour.blueComponent, alpha: colour.alphaComponent),
            alignment: alignment == .center ? .centre : alignment == .right ? .right : .left,
            isBold: traits.contains(.boldFontMask),
            isItalic: traits.contains(.italicFontMask),
            isUnderlined: (attributes[.underlineStyle] as? Int ?? 0) != 0
        )
    }

    static func runs(_ text: NSAttributedString, zoom: Double) -> [TextRun] {
        var result: [TextRun] = []
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, _ in
            let string = (text.string as NSString).substring(with: range)
            let style = style(attributes, zoom: zoom)
            if let last = result.last, last.style == style {
                result[result.count - 1] = TextRun(text: last.text + string, style: style)
            } else {
                result.append(TextRun(text: string, style: style))
            }
        }
        return result
    }
}
