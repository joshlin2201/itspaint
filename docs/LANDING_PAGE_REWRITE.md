# itspaintmac.com, the edits

Ready to paste into the FyneSite editor. Ordered by effect on installs, so stopping
half way still leaves the page better than it is now.

Four of these are corrections rather than improvements: the page currently states four
things that are not true. Those are marked **FALSE** and should go first whatever else
happens. `python3 ~/.itspaint-promo/surfaces.py` fails on three of them and will keep
failing until they are fixed, which is the point.

Reviewed against the live HTML by grok 4.6, and every factual claim below was checked
against the source, `docs/COMPETITIVE.md`, `docs/FEATURES.md` and the published release
before it was written down.

---

## The four false statements

### 1. FALSE — the size, in the largest type on the page

> Native, free, open source, under 3 MB.

The disk image is **3.02 MB** as of 0.15.1. It crossed three megabytes and the sentence
stayed.

**Replace with:** `Native, free, open source, 3 MB.`

Or carry the decimal, `3.02 MB`, which is what the README does and what the checker
watches. A round number that drifts is how this broke; a decimal that a script compares
against the published asset does not.

### 2. FALSE — the structured data says 0.12.0

```json
"softwareVersion": "0.12.0"
```

Three releases stale. No visitor sees it and every crawler does, so the rich result
Google renders is advertising a build that has been replaced four times.

**Replace with:** `"softwareVersion": "0.15.1"`

### 3. FALSE — the export count

> Eight export formats

Nine: PNG, JPEG, TIFF, BMP, GIF, HEIC, AVIF, PDF, ICO. AVIF is missing from the chips.
The paragraph under that heading also describes the `.itspaint` document rather than the
export list, so the heading and the body are about different things.

**Replace the cell with:**

> **Nine export formats**
> PNG, JPEG, TIFF, BMP, GIF, HEIC, AVIF, PDF and ICO. Formats without alpha flatten onto
> Colour 2 rather than onto black. The native document is a lossless PNG with a JSON
> sidecar, so it still opens in anything that reads a PNG.

### 4. FALSE — the competitor sentence

> The capable editors are a gigabyte and cost money.

Krita is a gigabyte and free. GIMP is free. Four different products got mashed into one
claim, and a Mac developer knows at least one of them.

**Replace with:**

> Krita is a gigabyte and built for painters. Pixelmator and Photoshop cost money.
> Preview is already on your Mac and will not number a step.

---

## The lead, which never names what it beats

> A blank canvas at the size you asked for. An image dropped on top of another one.
> A screenshot marked up and out the door. Native, free, open source, under 3 MB.

A stranger learns the category before they scroll and never learns why to leave the
markup they already have. Three sentences of the same length and cadence, with no
opponent in any of them.

**Replace with:**

> Preview markup will not number a step, pixelate a token, or let you drag the result
> into Slack. ItsPaint will. Blank canvas at the size you asked for, paste one image on
> top of another, crop it, mark it up, drag it out. Free on the App Store. MIT. 3 MB.

Do not add a fourth clause to balance the first three. The imbalance is the repair.

---

## Two things the page never mentions

Both are on the README's first screen and both are why someone installs.

> **Drag the image into Slack, Mail or the Finder.** No save panel, and nothing lands on
> your Desktop.

> **Spotlight.** Drag a box and everything outside it dims, so the eye lands where you
> meant it to on a busy screenshot. `S`.

Drag-out is the one a developer believes immediately, because they have a Desktop full
of `Screenshot 2026-08-12 at 11.42.13.png`.

---

## Pixelate is described as redaction, and it is not

> Mosaic redaction for tokens, emails, and customer names before a screenshot leaves
> your Mac.

`docs/FEATURES.md` says plainly that this is not secure redaction. Anyone who has seen a
mosaic reversed stops trusting the page at that word.

**Replace with:**

> Drag a box over the token and it mosaics, so it does not read at a glance. For an
> actual secret, cover it with a filled rectangle.

---

## The closing asks for the wrong thing

> Free and open source.
> ItsPaint is in public beta. If it earns a place in your dock, a star helps other
> people find it.

"If it earns a place" is diminutive, "public beta" makes a notarised App Store app sound
unfinished, and the last action on a page whose job is an install is a GitHub star.

**Replace with:**

> **Get it on your Mac.**
> Free on the App Store. Or the brew command at the top, or the disk image. macOS 14 or
> later, universal.
> If you already installed it, a star is how the next person finds it from search.

---

## Layout, in the order worth doing it

1. **Put `markup-reel.gif` in the hero.** The chameleon window proves it is a real native
   editor and sells painting. The reel shows the job: paste, three badges, pixelate, nine
   seconds. Keep the chameleon further down, where the README now puts it.

2. **One install, repeated.** Right now the green object above the fold is a Copy button
   on a brew command, the App Store is a 14.5px inline link, and the closing primary
   button is Star on GitHub. This domain is what the App Store listing points at, so a
   lot of arrivals already have a Get button behind them. App Store button in the nav, in
   the hero above the brew box, once after the reel, and once at the close. Brew stays as
   the developer alternative.

3. **Put an install in the sticky bar.** It is 60px of permanent screen holding section
   jumps and a GitHub link, and on a phone the jumps are hidden, so a visitor who scrolls
   past the hero has no way back to an install. Drop Privacy and FAQ from the bar.

4. **Reorder the feature grid.** Remove Background is the big cell with the GIF; badges
   and pixelate are small; Spotlight is absent. That is the inverse of the wedge
   `COMPETITIVE.md` names. Badges, pixelate and Spotlight on the top row, then drag-out,
   then Remove Background, then shapes, then export.

5. **Cut the overlap.** Eight ask cards followed by six FAQ answers that restate them,
   both built as heading-plus-one-paragraph. Keep the FAQ questions, they match real
   searches. Cut the asks section to the four cards the FAQ does not already answer.

6. **On a phone, lead with the App Store button, full width.** The brew command is 48
   characters of `white-space: nowrap`, so the primary call to action is currently
   something the thumb has to swipe sideways to read, on traffic that does not want brew.

---

## Leave these alone

The dark page, the green, the pixel grid and the SF stack, which make it look like the
app rather than a template with a screenshot dropped in. The markup GIF. The window shot,
once it moves. Keyboard chords and `Image ▸` paths, which are why a Mac person believes
it. The three privacy commands in a terminal in that exact order, entitlements first.
The Copy button and its copied state. No fake user counts and no testimonials. The FAQ
questions. Reduced motion and `:focus-visible`. And `declines rather than guessing` on
Remove Background, which is the sentence that makes the no-model claim credible.
