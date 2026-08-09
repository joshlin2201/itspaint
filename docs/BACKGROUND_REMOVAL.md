# Background removal without a model

**Image ▸ Remove Background** in ItsPaint takes a product shot off its page and
leaves the checkerboard showing through. It ships no model, downloads no
weights, touches no network, and does not ask the Neural Engine for anything.
It is thirty lines of code on top of the flood fill that was already there for the
paint bucket.

![A product shot on a flat page, then the same window with the background gone](images/remove-background.gif)

This document is the whole implementation and, more usefully, the two decisions
that made it work.

---

## What the feature actually is

The honest framing first, because it is the part that gets skipped: **this is
not segmentation.** It does not know what a subject is. It knows what a *page*
is.

That distinction is the entire feature. The images people want this for —
product shots, logos, screenshots, scanned diagrams, clip art, a photo of a
thing on a desk — share one property: the background is flat and it touches the
edge of the frame. A model is the right tool for a subject standing in a
forest. For a bottle on a white sweep it is a hundred megabytes of machinery to
answer a question a flood fill answers exactly.

Exactly, not approximately. A trained matte gives you a probability per pixel
and a fringe of grey where it is unsure. A flood fill over a flat page gives
you the page, pixel-accurate, deterministically, and in the same millisecond
budget as the paint bucket.

## The implementation

```swift
public func removeBackground(tolerance: Int = 24) -> Bool {
    _ = commitFloating()
    guard !canvas.bounds.isEmpty else { return false }

    let corners = [
        PixelPoint(x: 0, y: 0),
        PixelPoint(x: canvas.width - 1, y: 0),
        PixelPoint(x: 0, y: canvas.height - 1),
        PixelPoint(x: canvas.width - 1, y: canvas.height - 1)
    ]

    let previous = selection
    selection = nil
    for corner in corners {
        selection = combinedSelection(
            with: Raster.floodSelection(from: corner, tolerance: tolerance, in: canvas),
            operation: .add
        )
    }

    guard let page = selection, !page.isEmpty else {
        selection = previous
        return false
    }
    let covered = page.mask?.count { $0 > 0 } ?? page.bounds.area
    let remaining = canvas.count - covered
    guard remaining >= max(64, canvas.count / 4000) else {
        selection = previous
        return false
    }

    makeSelectionTransparent(named: "Remove background")
    return true
}
```

That is all of it. Four seeds, one union, one sanity check, one existing
operation.

### Seeding from four corners, not one

One seed in the top-left is enough for a plain sweep and wrong for almost
everything else. A screenshot has a titlebar. A scan has a shadow down one
side. A product shot has a gradient that drifts past the tolerance somewhere
along the way. Any of those splits the page into regions that a single flood
never reaches.

Four corners is not a heuristic about images so much as a fact about framing:
if a subject occupied all four corners it would not have a background to
remove. Unioning the four floods costs four passes over pixels that are mostly
already marked — the fill checks `coverage[i] == 0` before it tests colour, so
the second, third and fourth seeds walk the boundary and stop.

### The union is the selection type, not a new one

The four floods combine through `combinedSelection(with:operation:.add)` — the
same call `⇧`-click makes when you add a region to an Instant Alpha selection.

This was deliberate and it is the part worth stealing. The first draft built a
private mask, unioned bytes by hand, and converted to a `Selection` at the end.
It worked, and it meant "add these two regions together" existed twice in the
codebase, so the day one of them learned about anti-aliased edges the other one
would not have.

Accumulating the union *in* `selection` rather than in a local also means the
existing `makeSelectionTransparent` is the whole ending — the page is already
selected when it is time to clear it, so there is no second code path that knows
how to erase a region. `makeSelectionTransparent` consumes the selection and
sets it back to `nil`, which is why nothing is left selected after a successful
run. On a decline the function restores whatever you had selected before, so a
refusal costs you nothing, not even your selection.

### It declines rather than guessing

```swift
let remaining = canvas.count - covered
guard remaining >= max(64, canvas.count / 4000) else {
    selection = previous
    return false
}
```

Point this at a photograph and the flood does not stop — sky, water, and skin
are all within tolerance of something at a corner, and it eats the frame. The
useless answer is a blank canvas. The dangerous answer is a *nearly* blank
canvas, because that one looks like the feature ran.

So when the flood leaves nothing behind it returns `false`, restores whatever
selection you had, and the app says it could not separate the page. The menu
item does nothing rather than something wrong.

**This guard was wrong for its first three releases, and the way it was wrong is
worth more than the fix.** It compared *coverage* against a ceiling:

```swift
guard Double(covered) / Double(canvas.count) < 0.92 else { ... }   // don't
```

That reads like the same test. It is not. A logo, an icon, or a product shot on
a white sweep — the images this command exists for — is routinely 95% or more
background. So the command refused precisely the pictures it was built to
handle. A 60-pixel mark centred on a 400×400 page is 97.8% background and came
back *"There's no background to remove."*

Two things kept it hidden. The test fixture was a 40×20 canvas holding a 20×8
subject, which sits at 80% page and sails under the threshold — **the constant
was satisfied by the test and by nothing a person would open.** And this
document argued the failure was a deliberate trade, in a paragraph that named
the exact broken case and called it a corner worth buying. It was not a corner.
It was the centre of the use case, described as an edge because the threshold
that caused it had already been written down.

The fix is not a better constant. Coverage was the wrong quantity. What the
guard is protecting against is the image whose page and subject are *one region*,
where keying out the page erases the picture — and that shows up as **nothing
left over**, at any coverage at all. So measure the remainder instead. The floor
stays small and grows slowly: a subject is never required to be a large fraction
of the image, only to be more than the stray anti-aliased pixels a flood leaves
along an edge where it stopped.

The regression test now runs subjects of 8, 16, 40, 60, 120 and 200 pixels
square on a 400×400 page — 99% down to 75% background — because a threshold
tuned on one fixture is how the first one survived.

## The flood fill underneath

`Raster.floodSelection` is a span filler, not the four-way recursion in every
tutorial. It walks a scanline to both ends of a run, pushes the span, and
carries on:

```swift
func scan(_ x0: Int, _ x1: Int, _ y: Int) {
    var x = x0
    while x <= x1 {
        guard fillable(x, y) else { x += 1; continue }
        var start = x
        while fillable(start - 1, y) { start -= 1 }
        var end = x
        while fillable(end + 1, y) { end += 1 }
        stack.append((start, end, y))
        x = end + 1
    }
}
```

The stack is explicit and heap-allocated, so a 6000×4000 page of near-uniform
colour is a large array, not four million stack frames and a crash. Pixels are
premultiplied RGBA8 in a flat array; `fillable` is one bounds check, one
coverage check, and one tolerance compare, and it is `@inline(__always)`.

## What this costs, and what it does not

| | Model-based matting | This |
|---|---|---|
| Download | 40–200 MB of weights | nothing |
| First run | model load, warm-up | immediate |
| Network | usually, at least once | never — the sandbox has no network entitlement |
| Subject in a scene | works | declines |
| Flat page, hard edge | soft fringe | exact |
| Code | a framework | 30 lines over an existing fill |

The gap in that table is real and it is not going to be closed by tuning a
threshold. If you need a person cut out of a park, use a model.

### "macOS already has this in Preview"

It does, and that is the honest first objection to this whole page. Preview has a
**Remove Background** button, and it is a subject-lifting model — the same family
of thing Windows 11 Paint uses. So the question is not free-versus-paid, it is
which failure you want.

|  | Preview | This |
|---|---|---|
| Asks | "what is the subject?" | "what is the page?" |
| Person in a park | works | **declines** |
| Flat page, hard edge | a matte, with a soft fringe | the exact pixels |
| Result | probabilistic | deterministic — same input, same output, always |
| When unsure | returns its best guess | returns `false` and changes nothing |

For a photograph Preview is the better tool and you should use it. For a product
shot on a white sweep, a logo, a scan, or a screenshot — the cases this exists
for — a flood fill over a flat region is not an approximation of subject
lifting, it is the exact answer, and it cannot invent a fringe that was not
there.

The part worth taking from this page is not that a flood fill beats a model. It
is that a *bounded* problem sometimes has an exact solution hiding inside code
you already shipped, and 30 lines over the paint bucket is a cheaper thing to own
than a dependency on somebody's matting framework.

## Verifying the claims

The no-network claim in this document is checkable against the build you have,
not just this page. Three commands, described in full in the
[README](../README.md#no-network-and-how-to-check):

```bash
codesign -d --entitlements - --xml /Applications/ItsPaint.app | plutil -p -
otool -L /Applications/ItsPaint.app/Contents/MacOS/ItsPaint
grep -rniE 'URLSession|NWConnection|import Network|CFSocket|getaddrinfo' App Packages
```

Neither `com.apple.security.network.client` nor `.server` is requested, so the
kernel refuses an outbound connection regardless of what the code asks for.

The behaviour is covered by two tests in
`Packages/PaintKit/Tests/PaintKitTests/PaintEngineTests.swift` — one that the
corners clear and the subject survives, one that a canvas with no subject is
refused rather than emptied.

---

ItsPaint is MIT licensed and lives at
[github.com/joshlin2201/itspaint](https://github.com/joshlin2201/itspaint).
The engine is a separate UI-free package, `Packages/PaintKit`, if you want the
fill without the app.
