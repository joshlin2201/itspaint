import Foundation
import PaintKit

/// The hero artwork: a chameleon mid-colour-change, tongue out for a drop of
/// paint, on a fully transparent canvas.
///
/// The subject is the pitch. A chameleon is the one animal whose whole job is
/// colour, its body runs the palette from warm snout to blue tail, and the
/// knocked-out background puts the editor's transparency checkerboard behind
/// the art — the same way every screenshot of this scene demonstrates Instant
/// Alpha without a caption.
///
/// Everything is engine output: filled polygons for the low-poly facets,
/// freehand brush strokes for the tail spiral and tongue, the highlighter for
/// the shadow on the branch, and Instant Alpha to remove the key background.
@MainActor
enum ChameleonScene {
    /// Where the knockout samples the key background.
    static let backgroundSample = PixelPoint(x: 12, y: 12)

    static func render() -> Bitmap {
        // A key colour no facet uses, removed exactly (tolerance 0) at the end.
        let canvas = DemoCanvas(fill: colour("FF00FF"))

        drawBranch(on: canvas)
        drawFarLegs(on: canvas)
        drawTail(on: canvas)
        drawBody(on: canvas)
        drawNearLegs(on: canvas)
        drawBranchShadow(on: canvas)
        drawHead(on: canvas)
        drawEye(on: canvas)
        drawTongueAndDrop(on: canvas)
        knockOutBackground(on: canvas)

        return canvas.engine.canvas
    }

    // MARK: - Branch

    private static func drawBranch(on canvas: DemoCanvas) {
        let engine = canvas.engine

        // Main bough, drawn as one thick stroke so the ends are round.
        stroke(
            on: canvas,
            through: [point(50, 548), point(400, 515), point(700, 486), point(960, 462)],
            size: 30,
            colour: colour("7A4E2D")
        )
        // A darker underside line gives the bough a round section.
        stroke(
            on: canvas,
            through: [point(70, 558), point(420, 524), point(960, 472)],
            size: 9,
            colour: colour("5D3A1F")
        )
        // A short fork keeps the left end from reading as a floating pole.
        stroke(
            on: canvas,
            through: [point(300, 524), point(210, 570), point(140, 600)],
            size: 18,
            colour: colour("6B4326")
        )

        // Two leaves on the right end, built from polygon points because the
        // ellipse shape is axis-aligned.
        engine.settings.brushSize = 1
        filledPolygon(
            on: canvas,
            points: [
                point(806, 470), point(842, 428), point(886, 414),
                point(872, 452), point(836, 478),
            ],
            colour: colour("57BE6E")
        )
        filledPolygon(
            on: canvas,
            points: [
                point(862, 476), point(906, 452), point(946, 448),
                point(922, 482), point(882, 494),
            ],
            colour: colour("3FA65C")
        )
    }

    // MARK: - Legs

    private static func drawFarLegs(on canvas: DemoCanvas) {
        let far = colour("1E5730")
        // Far legs sit behind the body: most of each is hidden, so a simple
        // tapered quad down to the branch is enough.
        filledPolygon(
            on: canvas,
            points: [point(560, 370), point(596, 366), point(588, 492), point(556, 494)],
            colour: far
        )
        filledPolygon(
            on: canvas,
            points: [point(452, 385), point(486, 383), point(478, 504), point(448, 506)],
            colour: far
        )
    }

    private static func drawNearLegs(on canvas: DemoCanvas) {
        let near = colour("2E7D44")
        let toe = colour("27703C")

        // Front near leg. The foot is a mitt wrapped over the bough, with a
        // cleft stroke to split it into the two-toed clamp chameleons have.
        filledPolygon(
            on: canvas,
            points: [point(614, 392), point(656, 386), point(650, 470), point(612, 474)],
            colour: near
        )
        filledPolygon(
            on: canvas,
            points: [
                point(610, 460), point(654, 456), point(668, 478), point(660, 500),
                point(636, 506), point(614, 496), point(604, 478),
            ],
            colour: toe
        )
        stroke(
            on: canvas,
            through: [point(634, 464), point(636, 500)],
            size: 4,
            colour: colour("1E5730")
        )

        // Back near leg.
        filledPolygon(
            on: canvas,
            points: [point(408, 400), point(450, 398), point(440, 486), point(402, 488)],
            colour: near
        )
        filledPolygon(
            on: canvas,
            points: [
                point(398, 474), point(440, 472), point(452, 492), point(444, 512),
                point(420, 518), point(400, 508), point(390, 492),
            ],
            colour: toe
        )
        stroke(
            on: canvas,
            through: [point(418, 478), point(416, 512)],
            size: 4,
            colour: colour("1E5730")
        )
    }

    // MARK: - Tail

    private static func drawTail(on canvas: DemoCanvas) {
        // The curled tail is a solid disc with a spiral groove — a chameleon's
        // coil really does read as a flat wheel — and it is where the body's
        // hue walk lands on blue.
        let centre = point(232, 408)

        filledCircle(on: canvas, centre: centre, radius: 84, colour: colour("128C7E"))

        // Connector wedge from the hip to the coil.
        filledPolygon(
            on: canvas,
            points: [point(340, 344), point(348, 424), point(268, 416), point(276, 352)],
            colour: colour("1F8A70")
        )

        // The last stretch of tail has already turned blue: a wide band laid
        // along the outer coil, so the colour follows the anatomy.
        let coil = spiralPoints(centre: centre)
        stroke(on: canvas, through: Array(coil[16...50]), size: 24, colour: colour("2F80ED"))

        // Spiral groove, one continuous stroke tightening to the middle.
        stroke(on: canvas, through: coil, size: 9, colour: colour("0B6157"))

        // The tail tip parks at the centre of its own coil.
        filledCircle(on: canvas, centre: point(238, 402), radius: 11, colour: colour("2F80ED"))
    }

    private static func spiralPoints(centre: PixelPoint) -> [PixelPoint] {
        // Two and a bit turns, radius easing from the rim to the tip.
        (0...130).map { step in
            let angle = Double(step) * 0.11
            let radius = 76 - Double(step) * 0.52
            return point(
                centre.x + Int((radius * cos(angle)).rounded()),
                centre.y + Int((radius * sin(angle)).rounded())
            )
        }
    }

    // MARK: - Body

    private static func drawBody(on canvas: DemoCanvas) {
        // Base silhouette in the mid green. Facets land on top of it, so any
        // seam between facets shows green rather than the key colour.
        filledPolygon(
            on: canvas,
            points: [
                point(332, 388), point(352, 296), point(414, 232), point(504, 192),
                point(592, 182), point(660, 196), point(700, 250), point(700, 330),
                point(660, 380), point(600, 406), point(478, 422), point(388, 416),
            ],
            colour: colour("3FA65C")
        )

        // Facets: light along the spine, deep in the shade, teal toward the
        // tail. Values step rather than blend — this is flat paint.
        filledPolygon(
            on: canvas,
            points: [point(414, 232), point(504, 192), point(548, 240), point(462, 268)],
            colour: colour("57BE6E")
        )
        filledPolygon(
            on: canvas,
            points: [point(504, 192), point(592, 182), point(628, 236), point(548, 240)],
            colour: colour("4FB264")
        )
        filledPolygon(
            on: canvas,
            points: [point(352, 296), point(414, 232), point(462, 268), point(420, 330)],
            colour: colour("2F9E54")
        )
        filledPolygon(
            on: canvas,
            points: [point(462, 268), point(548, 240), point(576, 320), point(500, 348), point(420, 330)],
            colour: colour("23854B")
        )
        filledPolygon(
            on: canvas,
            points: [point(548, 240), point(628, 236), point(648, 320), point(576, 320)],
            colour: colour("2F9E54")
        )
        filledPolygon(
            on: canvas,
            points: [point(332, 388), point(352, 296), point(420, 330), point(400, 396)],
            colour: colour("1F8A70")
        )
        filledPolygon(
            on: canvas,
            points: [point(400, 396), point(420, 330), point(500, 348), point(478, 404)],
            colour: colour("17836B")
        )

        // Belly band, pale and warm, following the underline.
        filledPolygon(
            on: canvas,
            points: [
                point(388, 416), point(478, 422), point(600, 406), point(660, 380),
                point(646, 400), point(560, 428), point(452, 438), point(392, 428),
            ],
            colour: colour("F2EAC9")
        )

        // Dorsal crest — small coral sails along the spine.
        let crest = colour("EF6A5B")
        filledPolygon(
            on: canvas,
            points: [point(414, 232), point(438, 200), point(452, 224)],
            colour: crest
        )
        filledPolygon(
            on: canvas,
            points: [point(464, 210), point(490, 176), point(506, 204)],
            colour: crest
        )
        filledPolygon(
            on: canvas,
            points: [point(522, 188), point(548, 158), point(562, 188)],
            colour: crest
        )
        filledPolygon(
            on: canvas,
            points: [point(578, 180), point(602, 152), point(616, 184)],
            colour: crest
        )

        // A neck facet bridges the head so the join is a plane, not a seam.
        filledPolygon(
            on: canvas,
            points: [point(622, 240), point(664, 204), point(676, 296), point(642, 326)],
            colour: colour("5FB050")
        )
    }

    // MARK: - Head

    private static func drawHead(on canvas: DemoCanvas) {
        // Head base overlapping the body's right edge.
        filledPolygon(
            on: canvas,
            points: [
                point(636, 196), point(692, 148), point(766, 180), point(806, 224),
                point(840, 276), point(832, 306), point(788, 334), point(740, 350),
                point(694, 358), point(658, 330), point(644, 260),
            ],
            colour: colour("7CC242")
        )

        // Casque and brow catch the light.
        filledPolygon(
            on: canvas,
            points: [point(636, 196), point(692, 148), point(716, 210)],
            colour: colour("8FD14F")
        )
        filledPolygon(
            on: canvas,
            points: [point(692, 148), point(766, 180), point(716, 210)],
            colour: colour("7CC242")
        )
        filledPolygon(
            on: canvas,
            points: [point(716, 210), point(766, 180), point(806, 224), point(762, 256)],
            colour: colour("6DB33F")
        )

        // The snout warms up — this is where the colour change begins.
        filledPolygon(
            on: canvas,
            points: [point(762, 256), point(806, 224), point(840, 276), point(820, 302)],
            colour: colour("F2A03D")
        )
        filledPolygon(
            on: canvas,
            points: [point(820, 302), point(840, 276), point(832, 306), point(788, 334)],
            colour: colour("E8842B")
        )
        filledPolygon(
            on: canvas,
            points: [point(694, 358), point(740, 350), point(788, 334), point(742, 366)],
            colour: colour("5FA636")
        )

        // The famous smile, one long stroke from the snout to the cheek.
        stroke(
            on: canvas,
            through: [point(836, 286), point(806, 314), point(762, 336), point(716, 348)],
            size: 5,
            colour: colour("1F5B33")
        )
        // Nostril.
        filledCircle(on: canvas, centre: point(810, 248), radius: 4, colour: colour("1F5B33"))
    }

    // MARK: - Eye

    private static func drawEye(on canvas: DemoCanvas) {
        // A chameleon eye is a turret: skin ring, cream lid, amber iris, and a
        // pupil aimed at the paint drop.
        filledCircle(on: canvas, centre: point(702, 258), radius: 42, colour: colour("8FD14F"))
        ringStroke(on: canvas, centre: point(702, 258), radius: 34, size: 4, colour: colour("4C8C2B"))
        filledCircle(on: canvas, centre: point(702, 258), radius: 25, colour: colour("FFF8E7"))
        filledCircle(on: canvas, centre: point(707, 252), radius: 14, colour: colour("F2A03D"))
        filledCircle(on: canvas, centre: point(710, 249), radius: 7, colour: colour("17324D"))
        filledCircle(on: canvas, centre: point(713, 245), radius: 3, colour: .white)
    }

    private static func ringStroke(
        on canvas: DemoCanvas,
        centre: PixelPoint,
        radius: Int,
        size: Int,
        colour: PaintColour
    ) {
        let points = (0...36).map { step -> PixelPoint in
            let angle = Double(step) / 36 * 2 * .pi
            return point(
                centre.x + Int((Double(radius) * cos(angle)).rounded()),
                centre.y + Int((Double(radius) * sin(angle)).rounded())
            )
        }
        stroke(on: canvas, through: points, size: size, colour: colour)
    }

    // MARK: - Tongue and the paint drop

    private static func drawTongueAndDrop(on canvas: DemoCanvas) {
        // The story: the tongue has just caught a drop of blue paint.
        stroke(
            on: canvas,
            through: [
                point(824, 296), point(848, 272), point(866, 240),
                point(880, 204), point(890, 168), point(896, 142),
            ],
            size: 9,
            colour: colour("F26B8A")
        )
        filledCircle(on: canvas, centre: point(898, 136), radius: 12, colour: colour("F26B8A"))

        // The drop itself: a circle with a pointed crown.
        filledCircle(on: canvas, centre: point(902, 104), radius: 20, colour: colour("2F80ED"))
        filledPolygon(
            on: canvas,
            points: [point(902, 62), point(886, 96), point(918, 96)],
            colour: colour("2F80ED")
        )
        filledCircle(on: canvas, centre: point(909, 98), radius: 5, colour: .white)

        // Four short rays so the catch reads as a moment, not a diagram.
        let ray = colour("F2C94C")
        stroke(on: canvas, through: [point(864, 76), point(876, 86)], size: 4, colour: ray)
        stroke(on: canvas, through: [point(938, 74), point(928, 84)], size: 4, colour: ray)
        stroke(on: canvas, through: [point(870, 122), point(880, 114)], size: 4, colour: ray)
        stroke(on: canvas, through: [point(940, 118), point(930, 112)], size: 4, colour: ray)
    }

    // MARK: - Shadow

    private static func drawBranchShadow(on canvas: DemoCanvas) {
        // Highlighter, not paint: 38% ink over the bough reads as shadow. The
        // stroke stays inside the branch so no translucent pixel touches the
        // key background — a tinted key would survive the exact-match knockout.
        let engine = canvas.engine
        engine.settings.tool = .highlighter
        engine.settings.brushSize = 12
        engine.colours.foreground = colour("17324D")
        canvas.drag(
            from: point(410, 508),
            to: point(648, 486),
            via: [point(470, 503), point(560, 494)]
        )
        engine.settings.tool = .brush
    }

    // MARK: - Knockout

    private static func knockOutBackground(on canvas: DemoCanvas) {
        let engine = canvas.engine
        engine.settings.tool = .select
        engine.settings.selectionKind = .instantAlpha
        engine.settings.selectionTolerance = 0
        engine.beginStroke(at: backgroundSample)
        engine.makeSelectionTransparent()

        // The legs, branch and belly enclose pockets of key colour that the
        // flood from the corner cannot reach. Clicking each one is exactly
        // what a user does with Instant Alpha; finding them by scanning is
        // just faster than clicking.
        let key = colour("FF00FF").rgba8
        while let pocket = firstPixel(matching: key, in: engine.canvas) {
            _ = engine.selectInstantAlpha(at: pocket)
            engine.makeSelectionTransparent()
        }
    }

    private static func firstPixel(matching target: RGBA8, in bitmap: Bitmap) -> PixelPoint? {
        for y in 0..<bitmap.height {
            for x in 0..<bitmap.width {
                let point = PixelPoint(x: x, y: y)
                if bitmap.pixel(at: point) == target {
                    return point
                }
            }
        }
        return nil
    }

    // MARK: - Primitives

    private static func filledPolygon(
        on canvas: DemoCanvas,
        points: [PixelPoint],
        colour: PaintColour
    ) {
        let engine = canvas.engine
        engine.settings.brushSize = 1
        engine.settings.shapeStyle = .filled
        engine.colours.foreground = colour
        engine.settings.tool = .shape
        engine.settings.shapeKind = .polygon
        for point in points {
            engine.beginStroke(at: point)
        }
        guard let first = points.first else { return }
        engine.beginStroke(at: first)
    }

    private static func filledCircle(
        on canvas: DemoCanvas,
        centre: PixelPoint,
        radius: Int,
        colour: PaintColour
    ) {
        let engine = canvas.engine
        engine.settings.brushSize = 1
        engine.settings.shapeStyle = .filled
        engine.colours.foreground = colour
        canvas.shape(
            .ellipse,
            from: point(centre.x - radius, centre.y - radius),
            to: point(centre.x + radius, centre.y + radius)
        )
    }

    private static func stroke(
        on canvas: DemoCanvas,
        through points: [PixelPoint],
        size: Int,
        colour: PaintColour
    ) {
        guard let first = points.first, let last = points.last else { return }
        let engine = canvas.engine
        engine.settings.tool = .brush
        engine.settings.brushShape = .round
        engine.settings.brushSize = size
        engine.colours.foreground = colour
        canvas.drag(from: first, to: last, via: Array(points.dropFirst().dropLast()))
    }

    private static func point(_ x: Int, _ y: Int) -> PixelPoint {
        PixelPoint(x: x, y: y)
    }

    private static func colour(_ hex: String) -> PaintColour {
        PaintColour(hex: hex) ?? .black
    }
}
