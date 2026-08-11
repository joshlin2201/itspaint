# A guard that refused every image it existed for

**Image ▸ Remove Background** in ItsPaint has a safety check. It is there so the
command cannot hand you a blank canvas: if keying out the page would erase the
picture, it changes nothing and says so.

The check was inverted in effect for three releases. Not subtly wrong at the
margins — it refused the *entire* class of image the feature was built for, while
its test passed, its documentation defended it, and every release shipped it.

Here is the line.

```swift
let covered = page.mask?.count { $0 > 0 } ?? page.bounds.area
guard Double(covered) / Double(canvas.count) < 0.92 else {
    selection = previous
    return false          // "There's no background to remove."
}
```

Read it the way I did when I wrote it. Four flood fills run from the four corners
and get unioned into a selection — the page. If that selection covers more than 92%
of the canvas, there is essentially nothing *but* page, so removing it would leave
you with nothing. Refuse.

That reasoning is fine. The quantity is wrong.

## The images this command is for are 95% background

The feature exists for a product shot on a white sweep, a logo, an icon, a scanned
diagram, a screenshot. Take the canonical case: a 60-pixel mark centred on a 400×400
page.

```
canvas      400 × 400 = 160,000 px
subject      60 ×  60 =   3,600 px   (2.2%)
background            = 156,400 px   (97.8%)
```

97.8% is more than 92%, so the command refused it. The better the image fit the
feature's purpose — a small subject on a clean, generous page — the more certainly
it was rejected. A user's report would have read *"it works on some pictures and
says there's no background on the obvious ones"*, which is the least debuggable
sentence a bug can produce.

## The test passed, and the test is why

```swift
var canvas = Bitmap(width: 40, height: 20, fill: .white)
Raster.fillRect(PixelRect(x: 20, y: 6, width: 20, height: 8),
                colour: RGBA8(r: 200, g: 30, b: 30), into: &canvas)
#expect(engine.removeBackground())
```

800 pixels, a 160-pixel subject. **80% background — comfortably under the
threshold.** The assertion is meaningful, the fixture is realistic-looking, and the
test is green for the right reason on the wrong input.

I did not pick 40×20 to dodge the guard. I picked it because a small canvas is
readable in a diff and fast in a suite, and because the thing I was testing that day
was *"does it seed from all four corners"*, for which 40×20 is a perfectly good
canvas. The threshold was written later, against a fixture that already existed.

That is the whole mechanism, and it generalises past this bug:

> **A constant can be satisfied by its test and by nothing a person would ever
> open.** Fixtures get sized for legibility and speed. Thresholds get written
> against whatever fixture is already there. Nobody checks that the fixture
> resembles real input, because the test is green and greenness feels like
> evidence.

## The documentation is why nobody looked again

This is the part I find most uncomfortable, and the reason this document exists.

The write-up for this feature described the failure and argued it was a deliberate
trade-off:

> *The same guard is why the small-subject case is a decline and not a bug report. A
> 40-pixel logo centred on a 4000-pixel page is a legitimate image with a legitimate
> flat background, and it crosses 92% — the feature says no to an image it could
> have handled. That is the corner the threshold buys, and it is the right side to
> be wrong on: a false decline costs one undo, a false removal costs the image.*

Every clause of that is true. The conclusion is wrong, because it calls the centre
of the use case a corner. And having written it down, I had removed my own reason to
ever re-examine it — a reader who wondered about small subjects would find the
question already answered, confidently, by the author.

> **When you write down why something is acceptable, you delete the next person's
> reason to check.** The next person is usually you.

That paragraph made the bug invisible in a way the code alone could not. Code says
what it does. Prose says what it *means*, and prose does not get re-run.

## Coverage was the wrong quantity, so a better constant would not have helped

The instinct is to tune 0.92. Every value fails, because the ratio does not measure
the thing the guard cares about.

The guard is protecting against one situation: the page and the subject are the same
region, so keying the page out takes the picture with it. That situation has a
signature, and it is not "lots of background". It is **nothing left over** — at any
coverage.

```swift
let covered = page.mask?.count { $0 > 0 } ?? page.bounds.area
let remaining = canvas.count - covered
guard remaining >= max(64, canvas.count / 4000) else {
    selection = previous
    return false
}
```

Measure the remainder. A subject is never required to be a large fraction of the
image — that was the original mistake — only to be more than the stray anti-aliased
pixels a flood leaves along an edge where it stopped. 64 pixels covers an 8×8 mark;
the `count / 4000` term keeps the same idea honest on a 24-megapixel photo, where 64
surviving pixels really would mean the picture was erased.

The flat case still refuses, which is the point: a wholly blank image leaves a
remainder of zero.

## The regression test is sized like an image

```swift
@Test("A small subject on a large page is still a background",
      arguments: [8, 16, 40, 60, 120, 200])
func removeBackgroundKeepsSmallSubjects(subject: Int) {
    var canvas = Bitmap(width: 400, height: 400, fill: .white)
    …
    #expect(engine.removeBackground(), "declined a subject on a \(Int(page))% page")
}
```

99% background down to 75%, on a canvas the size of something you would actually
open. The old fixture stays too — it still tests four-corner seeding, which is what
it was always for.

## What I would take from this

- **Grep your guards for numeric literals, then ask what real input makes each one
  wrong.** Not "is the value sensible" — what *specific* file breaks it.
- **Look at your fixtures' dimensions.** A 20×20 canvas in an image-processing test
  is a smell. Not because small tests are bad, but because a threshold written
  against one has never met the real distribution.
- **Prefer a signature over a proportion.** "Did this leave anything behind" is a
  question about the failure you fear. "Is more than 92% of it background" is a
  question about something else that correlates with it, right up until it doesn't.
- **Date your rationales, or state their evidence.** *"This is fine because Y"* ages
  into an obstacle. *"As of 2026-08, verified by Z"* ages honestly.
- **An adversarial reading beats another test.** This was found by someone reading
  the code against the claim and asking what input would embarrass it — not by
  adding coverage. The coverage was already there and already green.

---

Fixed in [0.13.1](../CHANGELOG.md). The engine is
[`Packages/PaintKit`](../Packages/PaintKit), a UI-free Swift package: `swift test`
runs the whole suite in a fresh clone with no Xcode, so the regression above is one
command away from anyone who wants to see it fail against the old constant.

How the feature works, and why it uses no model at all:
[Background removal without a model](BACKGROUND_REMOVAL.md).
