# Path forward

Where this goes next, in the order it should go, with the reasoning attached.
Anything not listed here is not planned; anything in **Not planned** is a settled
no rather than an open question.

Status: **0.11.0 beta.** The engine and the chrome are done and tested; what
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

### Parity gaps worth closing

From the capability map in [COMPETITIVE](COMPETITIVE.md). Windows 11 Paint beats
us on exactly four things; three of them are cheap.

| | Why it matters | Shape of the work |
|---|---|---|
| ~~**Freeform rotate**~~ | **Shipped.** `Image ▸ Rotate…` takes any angle, grows the canvas to the rotated bounding box, and fills the exposed corners with Colour 2. The quarter turns keep their own exact path. | Done |
| **Rulers and guides** | Paint has them; we have a pixel grid above 4× and nothing else. Aligning annotations by eye is the most common reason a markup looks amateur. | View-layer only. Two edge strips reading the existing zoom and scroll origin, plus draggable guides in a small model array. |
| ~~**One-click background removal**~~ | **Shipped.** `Image ▸ Remove Background` floods from all four corners at tolerance 24, unions the regions through the same combiner Shift-click uses, and clears them as one undoable edit. Four corners because a subject touching an edge splits the page; it declines outright when the flood would take over 92% of the canvas, rather than erasing the picture, and names Instant Alpha when it does. | Done |

**Layers is the fourth, and it stays declined.** See *Not planned* below.

## Next — depth where it is cheap

- **Arrowheads as a line style** (start, end, both) rather than a separate shape,
  matching how the dash control already works.
- **Selection from the alpha channel** and **grow / shrink selection** — both
  fall out of the mask model in a few lines each.
- **Multi-page or multi-image documents.** Only if the `.itspaint` format can
  stay readable by other tools; a private container would break the promise the
  format makes.
- ~~**Signature capture**~~ **Shipped.** `⌃⌘S` signs in a strip or imports a
  photo of paper; `InkExtractor` keys the ink to transparent against a per-tile
  paper estimate and the result stamps as floating content that never grows the
  canvas. Built ahead of the list above because it turned out not to need the
  Continuity Camera integration that had put it last: a trackpad drag and an
  AirDropped photo cover both routes with no new entitlement. The camera itself
  is still deferred for exactly that reason.

## The capture track — the reason anyone opens this daily

A paint app is opened when you remember it exists. A capture tool is opened
forty times a day without thinking. Full analysis, including everything macOS's
own screenshot workflow does that we would have to keep working, is in
[CAPTURE](CAPTURE.md).

The staging matters more than the features:

1. **Be the destination.** Watch the screenshot folder and open what lands.
   Needs **no permissions at all** and breaks nothing about the existing
   workflow, because it does not touch capture.
2. **Own the clipboard variant.** `⌃⇧⌘4` already copies; a global hotkey that
   opens the clipboard into a new document closes the other half. Carbon
   `RegisterEventHotKey` works sandboxed without Accessibility.
3. **Services menu and a Share extension.** Puts an ItsPaint entry inside the
   floating thumbnail's own Share menu — the exact moment someone is deciding
   what to do with a screenshot.
4. **Take `⇧⌘4`,** opt-in, with a panel that explains the trade and deep-links
   to the Keyboard settings pane. Never silently.
5. **Capture ourselves with ScreenCaptureKit** — only after 1–4 prove the
   demand. This is the one that costs a Screen Recording permission, and the
   only one that could ever justify charging.

The four markup features that make this worth doing — step badges, pixelate,
Instant Alpha, and eight export formats — are already shipped. macOS Markup has
none of them. The capture layer is a distribution mechanism for work that
already exists.

## Later — the last mile

- ~~**Notarised releases.**~~ **Shipped in 0.11.0.** Signed with a Developer ID,
  notarised, and the ticket stapled to both the disk image and the app inside it
  so a first launch works offline. The install needs no Control-click and no
  `xattr`. What made it slow was not configuration: the first submissions sat
  over an hour in Apple's queue while CI treated a ran-out wait as a rejection,
  and once one had cleared the rest took under two minutes.
- ~~**A Homebrew cask.**~~ **Shipped as a personal tap:**
  `brew install --cask joshlin2201/itspaint/itspaint`
  ([joshlin2201/homebrew-itspaint](https://github.com/joshlin2201/homebrew-itspaint)).
  Verified with `brew style`, `brew livecheck`, `brew install --cask` and
  `brew uninstall --zap`, then reinstalled from the published remote. The
  **official** `homebrew-cask` repo needs 30 forks **or** 30 watchers **or** 75
  stars — tripled to 90/90/**225** when the repository owner submits it — and a
  repository at least 30 days old. So the official cask is gated on exposure
  rather than on anything we build. Same cask file either way; only the venue
  changes. See [GROWTH](GROWTH.md).
- **PaintKit published as a standalone package.** It is already separate,
  dependency-free and covered by 211 of its own tests. A README and a tag turn
  it into something other people can build on — and into the thing that
  attracts contributors who never open the editor.
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
  Floating selections already cover paste, move, place. Windows 11 Paint added
  them in 2024 and it is the one place its scope genuinely grew past ours —
  reconsidered on that evidence in July 2026, and still declined, because the
  cost is the five-minute learnability the whole app is built around.
- **Generative fill, generative erase, and every other model-backed feature.**
  Windows 11 Paint ships these on Copilot+ hardware. They need a model, a
  network, and a credit system — all three of which are things this app
  promises not to have.
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
4. Tag the commit **on `public/main`** and push the tag there:
   ```bash
   git tag -a v0.11.0 <public/main sha> -m "ItsPaint 0.11.0"
   git push public v0.11.0
   ```
   The tag has to point into the published history. `public/main` and the
   local archive branch share no ancestor — see *Two histories* below — so a
   tag cut on the archive names a commit the public repo has never seen.
5. [`release.yml`](../.github/workflows/release.yml) runs the full suite, imports
   the Developer ID certificate from repository secrets, builds a signed
   universal Release, then verifies its bundle version, architectures,
   signature and sandbox entitlements. It submits the disk image for
   notarisation, staples the ticket to both the image and the app, and packages
   a `.dmg` and a `.zip` with `checksums.txt`. It creates a **draft** GitHub
   Release — marked prerelease automatically while the version starts with `0.`
   or contains a `-`.

   Both signing and notarisation degrade rather than lie: without the
   certificate the build is ad-hoc and the verification asserts *ad-hoc*, and
   the install instructions in the release notes are composed from what
   actually happened — so a build can never tell people to clear a quarantine
   flag it does not set.

   **Notarisation is a queue at Apple**, not work the workflow controls, and
   the first submission from a newly issued Developer ID is routinely the
   slowest — allow for tens of minutes rather than assuming the couple of
   minutes later submissions take.
6. Download the draft artifacts and check the `.dmg` on a clean machine. Verify
   Gatekeeper accepts it without any manual step:
   ```bash
   spctl -a -vvv -t exec /Volumes/ItsPaint*/ItsPaint.app
   xcrun stapler validate ItsPaint-<version>.dmg
   ```
   Publish the draft only after that passes; the workflow never makes a release
   public automatically.

### Two histories

`origin` is a private archive with the project's full history. `public` is the
published repository, rooted at a fresh `ItsPaint 0.10.0 public beta` squash.
**They have no common ancestor**, so `git merge` between them fails outright and
cherry-pick is the only way to move work across — deliberately, because it is
also what keeps planning and specification documents out of the public tree.

Land work on the archive branch first, then cherry-pick the implementation
commits onto a worktree based on `public/main`:

```bash
git worktree add .worktrees/public-sync public/main
cd .worktrees/public-sync && git cherry-pick <sha>...
git push public HEAD:main
```

**Definition of done for any change here:** the fast suite is green, the change
has a test that fails without it, the docs that describe it are updated in the
same commit, and — if it touched the drawing path — the release suite with the
throughput guards is green too.
