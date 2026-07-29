# Path forward

Where this goes next, in the order it should go, with the reasoning attached.
Anything not listed here is not planned; anything in **Not planned** is a settled
no rather than an open question.

Status: **0.10.0 beta.** The engine and the chrome are done and tested; what
remains is depth in markup and the last mile to a shippable release.

---

## Now — finish the markup story

These are the gaps a Preview user notices in the first five minutes.

| | Why it matters | Shape of the work |
|---|---|---|
| **Loupe** | Preview's magnifier; genuinely useful at 100% on a dense screenshot. | A view-layer overlay reading the existing cached `CGImage`. No engine change. |
| **Adjust colour** | Brightness / contrast / saturation over the whole image or the selection. | `Bitmap.map(_:_:)` already applies a per-pixel transform inside a selection; this is a sheet plus three transforms and a live preview from a snapshot. |
| **Separate border and fill wells** | Today Colour 1 strokes and Colour 2 fills, which is the classic mapping but not what a Preview user expects when they set a shape's fill. | UI only — the engine already takes both colours per shape. |
| **Fuller image dimensions** | Fit-into presets, resolution, resample toggle, "resulting size". | `ImageTransform.scaled` and `resizedCanvas` exist; this is the sheet. DPI needs a new field in the document metadata. |

### Shipped from this list

- **Instant Alpha** — a read-only flood selection using the fill engine's span
  walk, with explicit tolerance, `⇧` add, `⌥` subtract, true masked marching
  ants, and an undoable **Make transparent** action over a checkerboard.

## Next — depth where it is cheap

- **Arrowheads as a line style** (start, end, both) rather than a separate shape,
  matching how the dash control already works.
- **Selection from the alpha channel** and **grow / shrink selection** — both
  fall out of the mask model in a few lines each.
- **Multi-page or multi-image documents.** Only if the `.itspaint` format can
  stay readable by other tools; a private container would break the promise the
  format makes.
- **Signature capture** (trackpad / camera / iPhone). High value for markup, but
  it is a Continuity Camera integration rather than a paint feature — it belongs
  after the list above.

## Later — the last mile

- **Notarised releases.** Needs a Developer ID identity in CI secrets. Until
  then the README's `xattr` line is the honest workaround.
- **App Store submission.** Entitlements, Privacy Manifest, document types and
  the exported UTI are already in place; what remains is the account work, the
  screenshots and the review.
- **Localisation.** `SWIFT_EMIT_LOC_STRINGS` is on, so strings are extractable;
  nobody has extracted them.
- **Formal trademark clearance before a paid or App Store launch.** The
  2026-07-29 public-beta knock-out search found no exact USPTO record or
  competing software product named `ItsPaint`; a lawyer-led clearance search
  is still the right gate before commercial distribution.

---

## Not planned

Each of these was considered and declined; the reasoning is in
[PHILOSOPHY](PHILOSOPHY.md).

- **Layers.** Turns "draw on a screenshot" into "learn a compositing model".
  Floating selections already cover paste, move, place.
- **A vector object model.** Shapes rasterise on release. Keeping them editable
  means a scene graph, an object selection model, and a document format nothing
  else can read.
- **Brush engines, blend modes, texture libraries.** Depth for painters, weight
  for everyone else.
- **Cloud, accounts, telemetry.** The app has no network code, and that is a
  feature.
- **Third-party dependencies.** Including for WebP encoding. AVIF covers the
  need and the system writes it.

---

## How a release happens

Versioning is [SemVer](https://semver.org); while on `0.x` the minor version may
still carry breaking changes to the document format.

1. Land the work. CI must be green on `main`.
2. Move the entries in `CHANGELOG.md` from **Unreleased** into a new version
   heading with today's date, and update the link refs at the bottom.
3. Bump `MARKETING_VERSION` in `project.yml`, then `xcodegen generate`.
4. Tag and push:
   ```bash
   git tag v0.10.0 && git push origin main --tags
   ```
5. [`release.yml`](../.github/workflows/release.yml) runs the full suite, builds
   a universal Release, verifies its bundle version, architectures, ad-hoc
   signature and sandbox entitlements, then packages a `.dmg` and a `.zip` with
   `checksums.txt`. It creates a **draft** GitHub Release — marked prerelease
   automatically while the version starts with `0.` or contains a `-`.
6. Download the draft artifacts and check the `.dmg` on a clean machine,
   quarantine flag and all. The release notes tell people to clear it; make
   sure that instruction is still true. Publish the draft only after that
   smoke test passes; the workflow never makes a release public automatically.

**Definition of done for any change here:** the fast suite is green, the change
has a test that fails without it, the docs that describe it are updated in the
same commit, and — if it touched the drawing path — the release suite with the
throughput guards is green too.
