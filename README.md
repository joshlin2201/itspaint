<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/icon.png">
  <source media="(prefers-color-scheme: light)" srcset="docs/images/icon-light.png">
  <img src="docs/images/icon.png" width="116" alt="">
</picture>

# ItsPaint

### MS Paint for the Mac. Paste a screenshot, number the steps, drag it out.

Preview markup has no step badges, no pixelate and no drag-out.

**3.17 MB** · free on the App Store · MIT ·
**no network entitlement, so the kernel refuses a socket**

[![Release](https://img.shields.io/github/v/release/joshlin2201/itspaint?sort=semver&style=flat-square&label=release&color=2563eb)](https://github.com/joshlin2201/itspaint/releases)
[![Mac App Store](https://img.shields.io/badge/Mac_App_Store-free-2563eb?style=flat-square)](https://apps.apple.com/us/app/itspaint/id6796493980?mt=12)
[![MIT](https://img.shields.io/badge/licence-MIT-1f2937?style=flat-square)](LICENSE)
[![tests](https://img.shields.io/github/actions/workflow/status/joshlin2201/itspaint/ci.yml?branch=main&style=flat-square&label=tests)](https://github.com/joshlin2201/itspaint/actions/workflows/ci.yml)

```sh
brew install --cask joshlin2201/itspaint/itspaint
```

**[Download the disk image](https://github.com/joshlin2201/itspaint/releases/latest)** · **[Mac App Store](https://apps.apple.com/us/app/itspaint/id6796493980?mt=12)** · macOS 14+, universal

<img src="docs/images/markup-reel.gif" alt="Pasting a settings sheet, numbering three steps with badges, and pixelating an API token, in nine seconds">

</div>

## What makes it different

- **3.17 MB, and a window on screen in half a second.** Krita is a gigabyte and
  built for painters. CleanShot X is $29 plus a cloud subscription. Preview is
  already on your Mac and will not number a step or pixelate a token.
- **No network entitlement.** `com.apple.security.network.client` is not requested,
  so the kernel will not open a socket for it.
  [Three commands to check that yourself](#no-network-three-commands-to-prove-it).
- **Background removal with no ML model** and nothing to download. Four
  corner-seeded flood selections, unioned.
  [Thirty lines of code](docs/BACKGROUND_REMOVAL.md).
- **The drawing engine has no UI.** `Packages/PaintKit` imports Foundation,
  CoreGraphics, ImageIO, CoreText and UniformTypeIdentifiers, and nothing else, so
  `swift test` verifies most changes with no Xcode. It is also
  [a package you can depend on](#paintkit-as-a-dependency).
- **Free, MIT, and it stays that way.** There is no account and no telemetry.

Paste the screenshot, number the steps, crop it, drag it out, close the window.
Nothing lands on your Desktop.

## PaintKit as a dependency

The engine is its own SwiftPM product, so you can draw, key out a background or encode
a PNG with none of the app around it. No AppKit, no third-party dependency, **macOS 12
and up**.

```swift
.package(url: "https://github.com/joshlin2201/itspaint", from: "0.16.4")
```

[![Swift versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fjoshlin2201%2Fitspaint%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/joshlin2201/itspaint)
[![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fjoshlin2201%2Fitspaint%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/joshlin2201/itspaint)

Those two are served from the Swift Package Index's own API rather than written here,
so they report what it built, on a machine that is not mine, and they go red without
anybody having to notice. The same page records [zero data-race-safety
errors](https://swiftpackageindex.com/joshlin2201/itspaint/builds) — every target in
both manifests is `swiftLanguageMode(.v6)`, so strict concurrency is on and nothing is
waived.

The macOS 12 is deliberate. The app needs macOS 14; the engine does not and no longer
says it does. It had the app's number by inheritance rather than by need, and a floor
is not a warning a consumer can ignore — SwiftPM refuses to resolve at all when a
dependency's deployment target is above yours.

PaintKit gets you a product shot off its page in four lines, on device, with no model
and no network:

```swift
import PaintKit

let engine = PaintEngine(canvas: try ImageCodec.decode(contentsOf: input))
guard engine.removeBackground() else { fatalError("no background to remove") }
try ImageCodec.encode(engine.canvas, as: .png).write(to: output)
```

Those four lines are compiled on every push, by a CI job that builds them from a
package outside this repository — the one that declares macOS 12, so the floor above
cannot quietly rise. And the result is checked by counting transparent pixels rather
than by whether the program exited quietly: on a 60px mark centred on a 400×400 page
the count goes from 0 to 156,400, which is 160,000 minus the 3,600 pixels of subject,
asserted for six subject sizes.

If you do depend on it: it ships often while it is in beta, and until 1.0 a minor
version may still carry a breaking change to the document format —
[CHANGELOG.md](CHANGELOG.md) says so at the top. **Watch ▸ Custom ▸ Releases** is the
notification for that one thing. Watching the repository outright also mails you every
issue and every comment, which is why most people do not.

## What it does

### Marking up

| | |
|---|---|
| **Step badges** | `1`, `2`, `3`… auto-numbered, numeral auto-contrasted, and the sequence can start anywhere for a run that spans two screenshots. |
| **Arrows and callouts** | `A` draws an arrow. Fifteen shapes in all, solid, dashed or dotted, outlined or filled. |
| **Highlighter** | Its own ink, kept apart from the colour pair. Overlapping passes in one stroke never darken. |
| **Pixelate** | A mosaic over the part you would rather not publish. Block size 4–48. |
| **Spotlight** | Drag a box and everything outside it dims, so the eye lands where you meant it to. |
| **Text with a rim** | One colour cannot stay legible across a light panel and a dark one, so annotation text carries a contrasting edge. |

### Getting things in and out

| | |
|---|---|
| **Drag straight out** | Into any app that takes an image. No save panel, and no `Screenshot 2026-08-07 at 11.42.13.png` left behind. |
| **Paste onto anything** | It arrives floating. Bigger than the canvas and the canvas grows rather than cropping it. |
| **Nine export formats** | PNG, JPEG, TIFF, BMP, GIF, HEIC, AVIF, PDF, ICO. Formats without alpha flatten onto Colour 2, not onto black. |
| **Open With** | Registered for PNG, JPEG, TIFF, BMP, GIF and HEIC. |

### Remove a background with no model and no network

<div align="center">

<img src="docs/images/remove-background.gif" alt="A product shot on a flat page, then the same window with the background gone and the checkerboard showing through">

</div>

One command. It floods from all four corners and makes the union transparent. If the
page is not actually separable it says so and changes nothing.

It knows what a page is, not what a subject is, so it works on logos, product shots
and scanned diagrams. It is useless on hair.

**[How it works, in thirty lines of code →](docs/BACKGROUND_REMOVAL.md)**

### Painting

| | |
|---|---|
| **Thirteen tools** | Pencil, brush, highlighter, eraser, clone, shape, text, badge, fill, eyedropper, select, pixelate, spotlight. One rail button each, every one a single key. |
| **Four brush nibs** | Round, square, soft, and spray. Spray keeps spraying while you hold still, which is the whole feel of an airbrush. |
| **Four ways to select** | Rectangle, ellipse, lasso, and Instant Alpha. Marching ants follow the pixel mask rather than its bounds. |
| **Pixel control** | Pointer-centred zoom, nearest-neighbour above 100%, a pixel grid, live tool footprints, rotate by any angle. |
| **Snap to grid** | `⇧⌘'` at 8–64px for shapes, selections and pasted content. Freehand ignores it. |

<div align="center">

<img src="docs/images/editor-window.png" alt="ItsPaint editing a chameleon painting on a transparent canvas, with the brush options open">

**Thirteen tools, fifteen shapes, and a transparent canvas.**
The window above is ItsPaint painting, not marking up.

</div>

## Install

```bash
brew install --cask joshlin2201/itspaint/itspaint
```

Or take the [disk image](https://github.com/joshlin2201/itspaint/releases), open it
and drag **ItsPaint** to Applications. It is also free on the
[Mac App Store](https://apps.apple.com/us/app/itspaint/id6796493980?mt=12).

It ships often while it is in beta. **Watch ▸ Custom ▸ Releases** is the quietest way
to hear about a new build.

| | |
|---|---|
| **Requires** | macOS 14 Sonoma or later |
| **Architecture** | universal, one build for Apple silicon and Intel |
| **Signing** | Developer ID, notarised, ticket stapled to the image *and* the app, so the check needs no network and there is nothing to clear from the Terminal |
| **Download** | 3.17 MB for the disk image, with a SHA-256 in `checksums.txt` |

```bash
shasum -a 256 -c checksums.txt
xcrun stapler validate ItsPaint-*.dmg
```

If macOS asks you to confirm the first launch, open **System Settings ▸ Privacy &
Security** and click **Open Anyway**. [Why that happens](#first-launch).

## No network. Three commands to prove it

This is a property the kernel enforces, not a promise anyone is making. The first
two commands run against the copy in `/Applications`, the third greps this
repository:

```bash
codesign -d --entitlements - --xml /Applications/ItsPaint.app | plutil -p -
otool -L /Applications/ItsPaint.app/Contents/MacOS/ItsPaint
grep -rniE 'URLSession|NWConnection|import Network|CFSocket' App Packages
```

| Command | What comes back |
|---|---|
| `codesign` | Three entitlements: sandbox, files you pick in a panel, app-scoped bookmarks. No `network.client` and no `.server`, so the kernel will not open a socket for it |
| `otool` | Apple frameworks and the Swift runtime, on both architectures. No `CFNetwork`, no `Network.framework`, no bundled dylib |
| `grep` | Nothing. `Package.swift` also declares no dependency, so there is no third-party code behind it |

The entitlements check goes first because it is the one that holds even if the
developer is lying to you. It reports what the kernel will permit.

**[Why that order, and how to make the same claim falsifiable in your own app →](docs/PROVING_NO_NETWORK.md)**

## Contributing, and the engine needs no Xcode

Because [PaintKit has no UI](#paintkit-as-a-dependency), most changes to how ItsPaint
*draws* can be made and checked with a text editor and a terminal. No simulator, no
GUI session, no Xcode project:

```bash
git clone https://github.com/joshlin2201/itspaint.git
cd itspaint
swift test          # the whole engine suite, in a fresh clone
```

**Seven issues are open and labelled [`good first issue`](https://github.com/joshlin2201/itspaint/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22)**,
each naming the file and the line to start at. They sit in three different parts of
the app so you can pick whichever suits you:

*View layer, AppKit drawing, no engine knowledge needed*
- [**#11** A loupe that follows the pointer](https://github.com/joshlin2201/itspaint/issues/11)

*Engine, pure functions over pixels, no Xcode needed*
- [**#12** Brightness, contrast and saturation](https://github.com/joshlin2201/itspaint/issues/12)
- [**#5** Arrowheads as a line style, not a separate shape](https://github.com/joshlin2201/itspaint/issues/5)

*Selection arithmetic, also engine-only*
- [**#3** Grow and shrink a selection by a pixel amount](https://github.com/joshlin2201/itspaint/issues/3)
- [**#4** Make a selection from the alpha channel](https://github.com/joshlin2201/itspaint/issues/4)
- [**#6** Flip and rotate the selection, not the whole image](https://github.com/joshlin2201/itspaint/issues/6)
- [**#7** Add to and subtract from a selection](https://github.com/joshlin2201/itspaint/issues/7)

[CONTRIBUTING.md](CONTRIBUTING.md) covers the structure, the design constraints, and
what a change has to prove before it lands.

<br>

<details>
<summary><b>Tools and shortcuts</b></summary>

<br>

| Group | Tools |
|---|---|
| **Draw** | Pencil, Brush (round / square / soft / spray), Highlighter (own ink, four colours), Eraser, Clone (clone / soften) |
| **Insert** | Shape, Text, Step Badge, Fill, Eyedropper |
| **Select** | Rectangle, Ellipse, Lasso, Instant Alpha |
| **Effects** | Pixelate, Spotlight |

Thirteen rail buttons. Variations live inside the tool that owns them, so there are fifteen
shapes behind Shape, four nibs behind Brush and four modes behind Select. The whole
set stays available without a button each.

| Shortcut | Action | Shortcut | Action |
|---|---|---|---|
| `P` | Pencil | `B` | Brush |
| `H` | Highlighter | `E` | Eraser |
| `C` | Clone | `F` | Soften |
| `U` | Shape | `T` | Text |
| `N` | Step Badge | `K` | Fill |
| `I` | Eyedropper | `M` | Select |
| `R` | Pixelate | `S` | Spotlight |
| `X` | Swap colours | `[` / `]` | Change tool size |
| `Space` | Pan | `Esc` | Cancel what you are doing |
| `⌥1`–`⌥9` | Choose a shape | `⇧⌘'` | Snap to grid |
| `⌘K` | Crop to selection | `⌘9` | Fit to window |
| `⇧⌘E` | Export | `⌘V` | Paste as a floating image |

Pinch or `⌘`-scroll to zoom around the pointer. Hold `⌥` to sample a colour without
changing tools. Right-drag uses the second colour. `Esc` cancels the current shape,
text box, selection, floating paste, or options panel.

Instant Alpha selects connected pixels by colour. `⇧`-click adds, `⌥`-click
subtracts, then **Make transparent**.

Pixelate is for visual de-emphasis and not for secure redaction. Cover private
information with an opaque filled shape before you export a flattened image.

</details>

<details>
<summary><b>Files and export</b></summary>

<br>

ItsPaint documents use the `.itspaint` package format, which is a lossless PNG with
JSON metadata for the canvas, colours and palette.

Export supports PNG, JPEG, TIFF, BMP, GIF, HEIC, AVIF, PDF and ICO, when the
corresponding encoder ships with the installed macOS version. The export panel has
format and scale controls, and formats without alpha are flattened onto the second
colour.

ItsPaint registers as an editor for PNG, JPEG, TIFF, BMP, GIF and HEIC, so it appears
under right-click ▸ **Open With**.

WebP export is not available, because macOS does not provide a WebP encoder. Text
becomes pixels once it is committed.

</details>

<details>
<summary><b>How it is built</b></summary>

<br>

```text
Packages/PaintKit/   UI-free drawing engine, raster operations, undo, and codecs
App/                 AppKit document lifecycle, canvas, and SwiftUI interface
```

PaintKit stores pixels as premultiplied RGBA8 and returns the changed rectangle from
every edit. The canvas redraws only that area, and undo history is bounded by memory
rather than by a fixed number of steps.

[**Background removal without a model**](docs/BACKGROUND_REMOVAL.md) is a worked
example of both layers. Four corner-seeded flood selections unioned through the same
combiner `⇧`-click uses, and a guard that declines rather than returning a nearly
blank canvas.

That guard was also wrong for three releases, in a way worth reading about:
**[a guard tuned to its test →](docs/A_GUARD_TUNED_TO_ITS_TEST.md)**

PaintKit is a product of the root package, so it can be a dependency of anything that
wants a raster canvas without an editor around it. The four-line example is in
**Contributing** above.

[docs/README.md](docs/README.md) has the design notes, architecture, feature
reference, testing guide and roadmap. [CHANGELOG.md](CHANGELOG.md) has the version
history.

</details>

<a id="first-launch"></a>

<details>
<summary><b>First launch, and the Gatekeeper message</b></summary>

<br>

Open **System Settings ▸ Privacy & Security** and click **Open Anyway**.

This happened once, on macOS 26.6, with a freshly downloaded 0.12.0, on a disk image
that `spctl --assess` accepts and whose stapled ticket validates. It looks like a
first-launch check that went to Apple and did not come back. It is alarming enough
when it happens that it belongs here rather than in an issue.

Check the download yourself:

```bash
shasum -a 256 -c checksums.txt
codesign --verify --deep --strict --verbose=2 /Volumes/ItsPaint*/ItsPaint.app
spctl -a -vvv -t exec /Volumes/ItsPaint*/ItsPaint.app   # expect: accepted
```

</details>

<div align="center">

**If you installed it, a star is how the next person finds it from search.**

[MIT License](LICENSE) · Built by [Josh Lin](https://github.com/joshlin2201)

</div>
