import AppKit
import PaintKit

/// Bridges the shared `NSColorPanel` to whichever colour well opened it.
///
/// One panel, not one per well: `NSColorPanel` is a singleton, and two views
/// both claiming its target would leave whichever registered last silently
/// overwriting the other's colour. Routing every request through here makes the
/// current owner explicit and lets it be handed over cleanly.
@MainActor
final class ColourPanelController: NSObject {

    static let shared = ColourPanelController()

    private var onChange: ((PaintColour) -> Void)?
    /// Identifies who owns the panel, so re-clicking the same well toggles it
    /// closed rather than reopening it.
    private var owner: String?

    private override init() { super.init() }

    /// Show the panel seeded with `initial`, routing edits to `onChange`.
    func present(
        owner: String,
        initial: PaintColour,
        onChange: @escaping (PaintColour) -> Void
    ) {
        let panel = NSColorPanel.shared

        if self.owner == owner, panel.isVisible {
            panel.orderOut(nil)
            self.owner = nil
            self.onChange = nil
            return
        }

        self.owner = owner
        self.onChange = onChange

        panel.showsAlpha = true
        panel.color = NSColor(
            srgbRed: initial.red, green: initial.green, blue: initial.blue, alpha: initial.alpha
        )
        panel.setTarget(self)
        panel.setAction(#selector(colourChanged(_:)))
        panel.isContinuous = true
        panel.makeKeyAndOrderFront(nil)
    }

    /// Release the panel when the owning document goes away, so a stale
    /// closure cannot keep writing into a closed document's model.
    ///
    /// Matched by prefix: a document owns one key per colour role
    /// (`<id>-foreground`, `<id>-background`) but closes as a whole, and an
    /// exact match here would never fire for either of them.
    func relinquish(owner prefix: String) {
        guard self.owner?.hasPrefix(prefix) == true else { return }
        self.owner = nil
        self.onChange = nil
        let panel = NSColorPanel.shared
        panel.setTarget(nil)
        panel.setAction(nil)
    }

    @objc private func colourChanged(_ sender: NSColorPanel) {
        // The panel can vend colours in any space — a device or generic RGB
        // value would shift once converted, so normalise to sRGB first.
        guard let colour = sender.color.usingColorSpace(.sRGB) else { return }
        onChange?(
            PaintColour(
                red: Double(colour.redComponent),
                green: Double(colour.greenComponent),
                blue: Double(colour.blueComponent),
                alpha: Double(colour.alphaComponent)
            )
        )
    }
}
