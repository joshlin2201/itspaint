import AppKit
import PaintKit
import Foundation
import Testing
@testable import ItsPaint

/// Renders the real `CanvasNSView` offscreen and inspects the resulting pixels.
///
/// This covers the layer unit tests cannot reach — what is actually *drawn* —
/// without needing a running app, a window server screenshot, or Accessibility
/// permission to drive the UI. If floating content composites in the wrong
/// place or the handles stop being drawn, this fails.
@Suite("Canvas rendering", .serialized)
@MainActor
struct CanvasRenderingTests {

    /// A rendered view plus the backing scale it was rendered at.
    ///
    /// `bitmapImageRepForCachingDisplay` renders at the display's backing scale,
    /// so on a retina machine the result is 2× the view's point size. Sampling
    /// it with point coordinates silently reads the wrong pixel — every probe
    /// lands in the top-left quadrant — which looks exactly like "the overlay
    /// was never drawn". Hence the explicit scale.
    private struct Rendered {
        let bitmap: Bitmap
        let scale: Int

        /// Sample using view *point* coordinates.
        func pixel(at point: PixelPoint) -> RGBA8? {
            bitmap.pixel(at: PixelPoint(x: point.x * scale, y: point.y * scale))
        }
    }

    private func render(_ view: CanvasNSView) -> Rendered? {
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let cgImage = rep.cgImage, let bitmap = Bitmap(cgImage: cgImage) else { return nil }
        let scale = max(1, bitmap.width / max(1, Int(view.bounds.width)))
        return Rendered(bitmap: bitmap, scale: scale)
    }

    /// Every test view lives in a real (offscreen) window.
    ///
    /// A bare `NSView` that has been sent mouse events and marked for display,
    /// and is then deallocated, leaves AppKit holding a pointer it messages on
    /// the next window pass — which segfaults the test host inside
    /// `isFlipped`, nowhere near the test that caused it. Hosting the view
    /// properly is also closer to what the app actually does.
    private static var hostWindows: [NSWindow] = []

    private func makeView(_ model: EditorModel, zoom: Double = 1) -> CanvasNSView {
        let view = CanvasNSView()
        view.model = model
        view.zoom = zoom
        view.invalidateCanvasSize()

        let window = NSWindow(
            contentRect: NSRect(
                x: 0, y: 0,
                width: max(320, view.frame.width),
                height: max(240, view.frame.height)
            ),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        window.contentView?.addSubview(view)
        Self.hostWindows.append(window)
        return view
    }

    @Test("The canvas is drawn, unflipped, at the right place")
    func drawsCanvasRightWayUp() throws {
        var canvas = Bitmap(width: 40, height: 30, fill: .white)
        Raster.fillRect(PixelRect(x: 0, y: 0, width: 8, height: 6), colour: .black, into: &canvas)

        let view = makeView(EditorModel(canvas: canvas))
        let rendered = try #require(render(view))

        // The black block was at the TOP-left of the canvas and must render
        // there — a flipped blit is the classic way this breaks.
        let topLeft = try #require(rendered.pixel(at: PixelPoint(x: 2, y: 2)))
        let bottomLeft = try #require(rendered.pixel(at: PixelPoint(x: 2, y: view.bounds.height.asInt - 3)))
        #expect(topLeft.r < 60)
        #expect(bottomLeft.r > 200)
    }

    @Test("Floating content is composited over the canvas")
    func drawsFloatingContent() throws {
        let model = EditorModel(canvas: Bitmap(width: 120, height: 90, fill: .white))
        model.engine.paste(Bitmap(width: 40, height: 30, fill: RGBA8(r: 220, g: 20, b: 40)))

        let view = makeView(model)
        let rendered = try #require(render(view))

        // Pasted content centres at (40, 30)...(80, 60).
        let inside = try #require(rendered.pixel(at: PixelPoint(x: 60, y: 45)))
        #expect(inside.r > 150 && inside.g < 90, "floating content not drawn: \(inside)")

        // And the canvas outside it is untouched.
        let outside = try #require(rendered.pixel(at: PixelPoint(x: 8, y: 8)))
        #expect(outside.r > 200 && outside.g > 200)
    }

    @Test("Floating content is drawn but NOT written into the canvas")
    func floatingIsNotDestructive() throws {
        let model = EditorModel(canvas: Bitmap(width: 120, height: 90, fill: .white))
        model.engine.paste(Bitmap(width: 40, height: 30, fill: .black))
        _ = render(makeView(model))

        // Drawing must never be a side effect on the document.
        #expect(model.canvas.pixels.allSatisfy { $0 == .white })
    }

    @Test("Resize handles are drawn around floating content")
    func drawsHandles() throws {
        let model = EditorModel(canvas: Bitmap(width: 200, height: 160, fill: .black))
        model.engine.paste(Bitmap(width: 100, height: 80, fill: .black))

        let view = makeView(model)
        let rendered = try #require(render(view))

        // Handles are white squares on an all-black canvas and content, so any
        // bright pixel near a corner of the floating frame is a handle.
        let frame = try #require(model.floating).frame
        var foundBright = false
        for y in (frame.minY - 6)...(frame.minY + 6) {
            for x in (frame.minX - 6)...(frame.minX + 6) {
                if let pixel = rendered.pixel(at: PixelPoint(x: x, y: y)), pixel.r > 180 {
                    foundBright = true
                }
            }
        }
        #expect(foundBright, "no handle drawn at the floating content's corner")
    }

    @Test("Handles are not drawn for content too small to hold them")
    func noHandlesOnTinyContent() throws {
        // They would cover the very thing they resize. Mid-grey content on a
        // black canvas, so a white handle is unmistakable — pasting black on
        // black could not have failed whatever was drawn.
        let grey = RGBA8(r: 128, g: 128, b: 128)
        let model = EditorModel(canvas: Bitmap(width: 120, height: 90, fill: .black))
        model.engine.paste(Bitmap(width: 8, height: 8, fill: grey))

        let view = makeView(model)
        let rendered = try #require(render(view))
        let frame = try #require(model.floating).frame

        // Inset past the marching ants, which legitimately run along the frame.
        let interior = frame.insetBy(2)
        for y in interior.minY..<interior.maxY {
            for x in interior.minX..<interior.maxX {
                let pixel = try #require(rendered.pixel(at: PixelPoint(x: x, y: y)))
                #expect(pixel.r < 200, "a handle was drawn over tiny content at \(x), \(y)")
            }
        }
    }

    @Test("A change the canvas painted itself does not repaint the whole view")
    func paintedRevisionIsNotRepainted() {
        // SwiftUI re-runs the representable on every observed change, including
        // the pointer moving. Repainting unconditionally there would undo the
        // rect-scoped invalidation the whole view is built on.
        let model = EditorModel(canvas: Bitmap(width: 40, height: 30, fill: .white))
        let view = makeView(model)

        #expect(view.repaintIfChanged(revision: model.revision))
        #expect(
            !view.repaintIfChanged(revision: model.revision),
            "an unchanged revision forced a full redraw"
        )

        // A change from outside the view — a menu command, an undo — still does.
        model.invertColours()
        #expect(view.repaintIfChanged(revision: model.revision))
    }

    /// A synthetic mouse event in window coordinates.
    private func mouse(_ type: NSEvent.EventType, at point: NSPoint) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        )
    }

    @Test("Dragging a text box and typing lands real pixels")
    func textToolWritesToTheCanvas() throws {
        let model = EditorModel(canvas: Bitmap(width: 240, height: 120, fill: .white))
        model.selectTool(.text)
        model.foreground = .black
        let view = makeView(model)

        view.mouseDown(with: try #require(mouse(.leftMouseDown, at: NSPoint(x: 20, y: 20))))
        view.mouseDragged(with: try #require(mouse(.leftMouseDragged, at: NSPoint(x: 220, y: 100))))
        view.mouseUp(with: try #require(mouse(.leftMouseUp, at: NSPoint(x: 220, y: 100))))

        let editor = try #require(
            view.subviews.compactMap { $0 as? NSTextView }.first,
            "no editor appeared for the text tool"
        )
        editor.string = "Hi"
        view.commitText()

        #expect(view.subviews.isEmpty, "the editor outlived its commit")
        #expect(model.canvas.pixels.contains { $0 != RGBA8.white }, "nothing was drawn")
        #expect(model.engine.undoStack.undoActionName == "Text")
    }

    @Test("Switching tools lands an open text box rather than dropping it")
    func toolChangeCommitsText() throws {
        let model = EditorModel(canvas: Bitmap(width: 240, height: 120, fill: .white))
        model.selectTool(.text)
        let view = makeView(model)

        view.mouseDown(with: try #require(mouse(.leftMouseDown, at: NSPoint(x: 20, y: 20))))
        view.mouseUp(with: try #require(mouse(.leftMouseUp, at: NSPoint(x: 20, y: 20))))
        let editor = try #require(view.subviews.compactMap { $0 as? NSTextView }.first)
        editor.string = "Kept"

        model.selectTool(.pencil)
        view.commitText(unless: model.tool)

        #expect(view.subviews.isEmpty)
        #expect(model.canvas.pixels.contains { $0 != RGBA8.white }, "the typed text was dropped")
    }

    @Test("A marquee is drawn for a selection with no floating content")
    func drawsMarquee() throws {
        let model = EditorModel(canvas: Bitmap(width: 160, height: 120, fill: .black))
        model.selectAll()
        model.engine.deselect()

        model.selectTool(.select)
        model.engine.beginStroke(at: PixelPoint(x: 30, y: 20))
        model.engine.endStroke(at: PixelPoint(x: 120, y: 90))
        #expect(model.selection != nil)

        let view = makeView(model)
        let rendered = try #require(render(view))

        // The ants use a white underlay, so the marquee edge is bright against
        // the black canvas. Scan a band rather than one row: the stroke is
        // centred on a half-pixel boundary, so which exact row it lands on
        // depends on the backing scale.
        var bright = 0
        for y in 18...22 {
            for x in 30...120 {
                if let pixel = rendered.pixel(at: PixelPoint(x: x, y: y)), pixel.r > 150 {
                    bright += 1
                }
            }
        }
        #expect(bright > 10, "marquee edge not visible (\(bright) bright pixels)")
    }

    @Test("Instant Alpha draws the mask's inner edge, not its bounding box")
    func drawsInstantAlphaContour() throws {
        var canvas = Bitmap(width: 140, height: 100, fill: .white)
        Raster.fillRect(
            PixelRect(x: 50, y: 35, width: 40, height: 30),
            colour: .black,
            into: &canvas
        )
        let model = EditorModel(canvas: canvas)
        model.engine.selectInstantAlpha(at: PixelPoint(x: 0, y: 0))
        #expect(model.selection?.isRectangular == false)

        let rendered = try #require(render(makeView(model)))
        var brightInsideHole = 0
        for y in 35..<65 {
            for x in 50...52 {
                if let pixel = rendered.pixel(at: PixelPoint(x: x, y: y)), pixel.r > 150 {
                    brightInsideHole += 1
                }
            }
        }
        #expect(
            brightInsideHole > 4,
            "the masked selection did not draw an inner contour (\(brightInsideHole) bright pixels)"
        )
    }

    @Test("Transparent pixels reveal a checkerboard")
    func transparencyIsVisible() throws {
        let view = makeView(EditorModel(canvas: Bitmap(width: 40, height: 24, fill: .clear)))
        let rendered = try #require(render(view))
        let firstTile = try #require(rendered.pixel(at: PixelPoint(x: 2, y: 2)))
        let secondTile = try #require(rendered.pixel(at: PixelPoint(x: 10, y: 2)))
        #expect(firstTile != secondTile, "alpha rendered as one flat colour")
    }

    @Test("Zoom scales the drawn canvas")
    func zoomScales() throws {
        var canvas = Bitmap(width: 20, height: 20, fill: .white)
        Raster.fillRect(PixelRect(x: 0, y: 0, width: 10, height: 10), colour: .black, into: &canvas)

        let view = makeView(EditorModel(canvas: canvas), zoom: 4)
        #expect(view.frame.width == 80)

        let rendered = try #require(render(view))
        // The black quadrant now occupies the first 40 points, so a point at
        // (30, 30) — outside it at 1× — is inside it at 4×.
        let scaled = try #require(rendered.pixel(at: PixelPoint(x: 30, y: 30)))
        #expect(scaled.r < 60)
    }

    @Test("Nothing is drawn without a model, rather than crashing")
    func toleratesNoModel() {
        let view = CanvasNSView()
        view.setFrameSize(NSSize(width: 40, height: 40))
        _ = render(view)
    }
}

@Suite("Drop and clipboard", .serialized)
@MainActor
struct DropTests {

    @Test("Dropping an image places it centred on the drop point")
    func dropCentresOnPoint() throws {
        let model = EditorModel(canvas: Bitmap(width: 400, height: 300, fill: .white))
        model.dropImage(Bitmap(width: 40, height: 40, fill: .black), centredOn: PixelPoint(x: 200, y: 150))

        let floating = try #require(model.floating)
        #expect(floating.frame.minX == 180 && floating.frame.minY == 130)
    }

    @Test("A dropped image larger than the canvas grows it instead of cropping")
    func dropGrowsCanvas() {
        // Dropping a retina screenshot onto a small canvas and silently losing
        // three quarters of it is the failure this prevents.
        let model = EditorModel(canvas: Bitmap(width: 100, height: 100, fill: .white))
        model.dropImage(Bitmap(width: 600, height: 400, fill: .black), centredOn: PixelPoint(x: 50, y: 50))

        #expect(model.canvasSize.width >= 600)
        #expect(model.canvasSize.height >= 400)
    }

    @Test("Cross-axis drop growth is rejected before allocating an oversized canvas")
    func dropRejectsOversizedCombinedCanvas() {
        // Each image is independently tiny in memory, but combining their
        // widest dimensions would request a 20,000 × 20,000 canvas.
        let model = EditorModel(canvas: Bitmap(width: 1, height: 20_000, fill: .white))
        let before = model.canvas
        let dropped = Bitmap(width: 20_000, height: 1, fill: .black)

        model.dropImage(dropped, centredOn: .zero)

        #expect(model.canvas == before)
        #expect(model.floating == nil)
        #expect(model.presentedError?.message.localizedCaseInsensitiveContains("large") == true)
    }

    @Test("A drop near an edge stays reachable on the canvas")
    func dropClampsIntoView() throws {
        let model = EditorModel(canvas: Bitmap(width: 400, height: 300, fill: .white))
        model.dropImage(Bitmap(width: 80, height: 80, fill: .black), centredOn: PixelPoint(x: 2, y: 2))

        let floating = try #require(model.floating)
        // Clamped to the canvas, so it can still be grabbed and moved.
        #expect(floating.frame.minX >= 0 && floating.frame.minY >= 0)
    }

    @Test("A drop is undoable back to the original canvas")
    func dropUndoes() {
        let model = EditorModel(canvas: Bitmap(width: 200, height: 200, fill: .white))
        let pristine = model.canvas
        model.dropImage(Bitmap(width: 50, height: 50, fill: .black), centredOn: PixelPoint(x: 100, y: 100))
        model.engine.commitFloating()
        #expect(model.canvas != pristine)

        model.undo()
        #expect(model.canvas == pristine)
    }

    @Test("Zoom to fit uses the exact scale, not the coarse ramp")
    func zoomToFitIsExact() {
        // Snapping a fit to the ramp is wrong: a canvas wanting 98% would drop
        // to 50% and waste half the window, which defeats a canvas-first
        // layout whose whole premise is that the artwork owns ~96% of it.
        // A viewport whose exact fit is deliberately NOT a ramp value: 0.766
        // sits between the 0.5 and 1.0 steps, so snapping would visibly waste
        // a third of the window.
        let model = EditorModel(canvas: Bitmap(width: 1000, height: 640))
        model.zoomToFit(CGSize(width: 900, height: 500))

        #expect(abs(model.zoom - 0.765) < 0.02, "fit was not exact: \(model.zoom)")
        #expect(model.zoom > 0.5, "fit snapped down and wasted the window")
    }

    @Test("Zoom to fit shows the whole canvas and never magnifies past 100%")
    func zoomToFitBounds() {
        let model = EditorModel(canvas: Bitmap(width: 4000, height: 3000))
        let viewport = CGSize(width: 1000, height: 800)
        model.zoomToFit(viewport)

        #expect(model.zoom < 1)
        // The scaled canvas must actually fit inside the viewport.
        #expect(Double(model.canvasSize.width) * model.zoom <= viewport.width)
        #expect(Double(model.canvasSize.height) * model.zoom <= viewport.height)

        // A small image is not blown up just because there is room.
        let small = EditorModel(canvas: Bitmap(width: 40, height: 30))
        small.zoomToFit(CGSize(width: 1200, height: 900))
        #expect(small.zoom == 1)
    }

    @Test("Manual zoom still snaps to the ramp")
    func manualZoomStillSnaps() {
        // The ramp exists so stepping through it keeps pixels honest. Only fit
        // is exempt.
        let model = EditorModel(canvas: Bitmap(width: 400, height: 300))
        model.zoom = 3.3
        #expect(EditorModel.zoomSteps.contains(model.zoom))

        model.zoomToFit(CGSize(width: 300, height: 300))
        model.zoomIn()
        #expect(EditorModel.zoomSteps.contains(model.zoom))
    }

    @Test("Zoom to fit ignores a degenerate viewport")
    func zoomToFitIgnoresTinyViewport() {
        let model = EditorModel(canvas: Bitmap(width: 400, height: 300))
        let before = model.zoom
        model.zoomToFit(CGSize(width: 0, height: 0))
        #expect(model.zoom == before)
    }
}


private extension CGFloat {
    var asInt: Int { Int(self) }
}
