import Testing
@testable import PaintKit

@Suite("Brush coverage")
struct BrushTests {

    @Test("A size-1 brush covers exactly one pixel, whatever its shape")
    func singlePixelNib() {
        for shape in Brush.Shape.allCases {
            let brush = Brush(shape: shape, size: 1)
            #expect(brush.coverage(dx: 0, dy: 0) == 255)
            #expect(brush.coverage(dx: 1, dy: 0) == 0)
            #expect(brush.coverage(dx: 0, dy: -1) == 0)
        }
    }

    @Test("A square brush is fully opaque across its whole extent")
    func squareIsHard() {
        let brush = Brush(shape: .square, size: 4)
        let e = brush.extent
        for dy in e.minY..<e.maxY {
            for dx in e.minX..<e.maxX {
                #expect(brush.coverage(dx: dx, dy: dy) == 255)
            }
        }
    }

    @Test("A round brush is symmetric about its centre")
    func roundIsSymmetric() {
        let brush = Brush(shape: .round, size: 9)
        for d in 1...4 {
            let right = brush.coverage(dx: d, dy: 0)
            let left = brush.coverage(dx: -d, dy: 0)
            let down = brush.coverage(dx: 0, dy: d)
            let up = brush.coverage(dx: 0, dy: -d)
            #expect(right == left)
            #expect(up == down)
            #expect(right == down)
        }
    }

    @Test("A soft brush falls off from the centre outward and never rises")
    func softFallsOff() {
        let brush = Brush(shape: .soft, size: 11)
        var previous = brush.coverage(dx: 0, dy: 0)
        #expect(previous == 255)
        for d in 1...6 {
            let current = brush.coverage(dx: d, dy: 0)
            #expect(current <= previous)
            previous = current
        }
        #expect(previous == 0)
    }
}

@Suite("Line rasterisation")
struct LineTests {

    @Test("A 1px horizontal line touches exactly the pixels it crosses")
    func horizontalLineIsExact() {
        var bmp = Bitmap(width: 10, height: 3)
        let dirty = Raster.strokeLine(
            from: PixelPoint(x: 2, y: 1), to: PixelPoint(x: 6, y: 1),
            brush: .pencil, colour: .black, into: &bmp
        )
        #expect(dirty == PixelRect(x: 2, y: 1, width: 5, height: 1))
        for x in 0..<10 {
            let expected: RGBA8 = (2...6).contains(x) ? .black : .white
            #expect(bmp.pixel(at: PixelPoint(x: x, y: 1)) == expected)
        }
        // Neighbouring rows must be untouched — no stray antialiasing.
        #expect((0..<10).allSatisfy { bmp.pixel(at: PixelPoint(x: $0, y: 0)) == .white })
    }

    @Test("A 45° diagonal produces one pixel per step")
    func diagonalIsExact() {
        var bmp = Bitmap(width: 8, height: 8)
        Raster.strokeLine(
            from: PixelPoint(x: 0, y: 0), to: PixelPoint(x: 7, y: 7),
            brush: .pencil, colour: .black, into: &bmp
        )
        for i in 0..<8 {
            #expect(bmp.pixel(at: PixelPoint(x: i, y: i)) == .black)
        }
        let painted = bmp.pixels.filter { $0 == .black }.count
        #expect(painted == 8)
    }

    @Test("A line is drawn identically in both directions")
    func lineIsDirectionAgnostic() {
        let a = PixelPoint(x: 1, y: 2), b = PixelPoint(x: 9, y: 5)
        var forward = Bitmap(width: 12, height: 8)
        var backward = Bitmap(width: 12, height: 8)
        Raster.strokeLine(from: a, to: b, brush: .pencil, colour: .black, into: &forward)
        Raster.strokeLine(from: b, to: a, brush: .pencil, colour: .black, into: &backward)
        #expect(forward == backward)
    }

    @Test("A zero-length line still marks its single pixel")
    func degenerateLine() {
        var bmp = Bitmap(width: 4, height: 4)
        let dirty = Raster.strokeLine(
            from: PixelPoint(x: 2, y: 2), to: PixelPoint(x: 2, y: 2),
            brush: .pencil, colour: .black, into: &bmp
        )
        #expect(dirty == PixelRect(x: 2, y: 2, width: 1, height: 1))
        #expect(bmp.pixel(at: PixelPoint(x: 2, y: 2)) == .black)
    }

    @Test("Strokes running off-canvas clip instead of crashing")
    func offCanvasClips() {
        var bmp = Bitmap(width: 5, height: 5)
        let dirty = Raster.strokeLine(
            from: PixelPoint(x: -50, y: 2), to: PixelPoint(x: 50, y: 2),
            brush: Brush(shape: .round, size: 3), colour: .black, into: &bmp
        )
        #expect(!dirty.isEmpty)
        #expect(dirty.minX >= 0 && dirty.maxX <= 5)
    }
}

@Suite("Shape rasterisation")
struct ShapeTests {

    @Test("A stroked rect paints its border and leaves the middle alone")
    func strokedRectIsHollow() {
        var bmp = Bitmap(width: 10, height: 10)
        Raster.strokeRect(
            PixelRect(x: 2, y: 2, width: 6, height: 6),
            brush: .pencil, colour: .black, into: &bmp
        )
        #expect(bmp.pixel(at: PixelPoint(x: 2, y: 2)) == .black)   // corner
        #expect(bmp.pixel(at: PixelPoint(x: 7, y: 7)) == .black)   // far corner
        #expect(bmp.pixel(at: PixelPoint(x: 4, y: 4)) == .white)   // interior
    }

    @Test("A filled ellipse is symmetric on both axes")
    func ellipseIsSymmetric() {
        var bmp = Bitmap(width: 21, height: 21)
        Raster.fillEllipse(
            in: PixelRect(x: 0, y: 0, width: 21, height: 21),
            colour: .black, into: &bmp
        )
        for y in 0..<21 {
            for x in 0..<21 {
                let here = bmp.pixel(at: PixelPoint(x: x, y: y))
                #expect(here == bmp.pixel(at: PixelPoint(x: 20 - x, y: y)))
                #expect(here == bmp.pixel(at: PixelPoint(x: x, y: 20 - y)))
            }
        }
    }

    @Test("A filled ellipse covers its centre and misses its corners")
    func ellipseShape() {
        var bmp = Bitmap(width: 21, height: 21)
        Raster.fillEllipse(
            in: PixelRect(x: 0, y: 0, width: 21, height: 21),
            colour: .black, into: &bmp
        )
        #expect(bmp.pixel(at: PixelPoint(x: 10, y: 10)) == .black)
        #expect(bmp.pixel(at: PixelPoint(x: 0, y: 0)) == .white)
        #expect(bmp.pixel(at: PixelPoint(x: 20, y: 20)) == .white)
    }

    @Test("A stroked ellipse is hollow but its outline matches the fill")
    func strokedEllipseIsHollow() {
        var stroked = Bitmap(width: 31, height: 31)
        var filled = Bitmap(width: 31, height: 31)
        let rect = PixelRect(x: 0, y: 0, width: 31, height: 31)
        Raster.strokeEllipse(in: rect, brush: .pencil, colour: .black, into: &stroked)
        Raster.fillEllipse(in: rect, colour: .black, into: &filled)

        #expect(stroked.pixel(at: PixelPoint(x: 15, y: 15)) == .white)  // hollow
        // Every stroked pixel must lie inside the filled silhouette, otherwise
        // "outline + fill" would show a fringe where the two disagree.
        for i in 0..<stroked.count where stroked.pixels[i] == .black {
            #expect(filled.pixels[i] == .black)
        }
    }

    @Test("A filled polygon covers its interior")
    func polygonFill() {
        var bmp = Bitmap(width: 12, height: 12)
        let triangle = [
            PixelPoint(x: 6, y: 1),
            PixelPoint(x: 10, y: 9),
            PixelPoint(x: 2, y: 9),
        ]
        Raster.fillPolygon(triangle, colour: .black, into: &bmp)
        #expect(bmp.pixel(at: PixelPoint(x: 6, y: 7)) == .black)
        #expect(bmp.pixel(at: PixelPoint(x: 1, y: 1)) == .white)
    }
}

@Suite("Flood fill")
struct FloodFillTests {

    private func canvasWithBox() -> Bitmap {
        var bmp = Bitmap(width: 12, height: 12, fill: .white)
        Raster.strokeRect(
            PixelRect(x: 2, y: 2, width: 8, height: 8),
            brush: .pencil, colour: .black, into: &bmp
        )
        return bmp
    }

    @Test("Fill stays inside a closed border")
    func respectsBorders() {
        var bmp = canvasWithBox()
        let red = RGBA8(r: 255, g: 0, b: 0)
        Raster.floodFill(from: PixelPoint(x: 5, y: 5), with: red, into: &bmp)

        #expect(bmp.pixel(at: PixelPoint(x: 5, y: 5)) == red)     // inside
        #expect(bmp.pixel(at: PixelPoint(x: 2, y: 2)) == .black)  // border intact
        #expect(bmp.pixel(at: PixelPoint(x: 0, y: 0)) == .white)  // outside untouched
    }

    @Test("Fill leaks through a one-pixel gap, as a bucket should")
    func leaksThroughGap() {
        var bmp = canvasWithBox()
        bmp.setPixel(.white, at: PixelPoint(x: 5, y: 2))  // punch a hole
        let red = RGBA8(r: 255, g: 0, b: 0)
        Raster.floodFill(from: PixelPoint(x: 5, y: 5), with: red, into: &bmp)
        #expect(bmp.pixel(at: PixelPoint(x: 0, y: 0)) == red)
    }

    @Test("Filling with the colour already there terminates immediately")
    func sameColourIsNoOp() {
        // The guard that makes this a no-op is load-bearing: without it every
        // filled pixel still matches the target and the scan never converges.
        var bmp = Bitmap(width: 64, height: 64, fill: .white)
        let dirty = Raster.floodFill(from: PixelPoint(x: 10, y: 10), with: .white, into: &bmp)
        #expect(dirty.isEmpty)
        #expect(bmp.pixels.allSatisfy { $0 == .white })
    }

    @Test("Tolerance absorbs near-matching neighbours")
    func toleranceMatches() {
        var bmp = Bitmap(width: 8, height: 8, fill: .white)
        bmp.setPixel(RGBA8(r: 250, g: 250, b: 250), at: PixelPoint(x: 4, y: 4))
        let red = RGBA8(r: 255, g: 0, b: 0)

        var strict = bmp
        Raster.floodFill(from: PixelPoint(x: 0, y: 0), with: red, tolerance: 0, into: &strict)
        #expect(strict.pixel(at: PixelPoint(x: 4, y: 4)) != red)

        var loose = bmp
        Raster.floodFill(from: PixelPoint(x: 0, y: 0), with: red, tolerance: 10, into: &loose)
        #expect(loose.pixel(at: PixelPoint(x: 4, y: 4)) == red)
    }

    @Test("Non-contiguous fill reaches isolated regions")
    func globalReplace() {
        var bmp = canvasWithBox()
        let red = RGBA8(r: 255, g: 0, b: 0)
        Raster.floodFill(
            from: PixelPoint(x: 0, y: 0), with: red,
            contiguous: false, into: &bmp
        )
        #expect(bmp.pixel(at: PixelPoint(x: 0, y: 0)) == red)   // outside
        #expect(bmp.pixel(at: PixelPoint(x: 5, y: 5)) == red)   // sealed inside, still hit
        #expect(bmp.pixel(at: PixelPoint(x: 2, y: 2)) == .black)
    }

    @Test("Flood selection finds the same connected region without changing pixels")
    func floodSelectionIsReadOnly() throws {
        let bmp = canvasWithBox()
        let before = bmp
        let selection = try #require(
            Raster.floodSelection(from: PixelPoint(x: 0, y: 0), in: bmp)
        )

        #expect(selection.contains(PixelPoint(x: 0, y: 0)))
        #expect(!selection.contains(PixelPoint(x: 5, y: 5)), "selection crossed a closed border")
        #expect(!selection.isRectangular, "the hole in the region was reduced to a box")
        #expect(bmp == before, "building a flood selection changed the artwork")
    }

    @Test("Filling a large open canvas completes without recursing")
    func largeCanvasDoesNotOverflow() {
        // A recursive four-way fill would blow the stack here; the span stack
        // must handle it. This is the regression guard for that choice.
        var bmp = Bitmap(width: 400, height: 400, fill: .white)
        let red = RGBA8(r: 255, g: 0, b: 0)
        let dirty = Raster.floodFill(from: PixelPoint(x: 200, y: 200), with: red, into: &bmp)
        #expect(dirty == bmp.bounds)
        #expect(bmp.pixels.allSatisfy { $0 == red })
    }

    @Test("Filling outside the canvas is a no-op")
    func outOfBoundsOrigin() {
        var bmp = Bitmap(width: 4, height: 4)
        let dirty = Raster.floodFill(from: PixelPoint(x: -1, y: -1), with: .black, into: &bmp)
        #expect(dirty.isEmpty)
    }
}
