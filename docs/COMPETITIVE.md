# What we are up against

Where ItsPaint sits against Windows 11 Paint, against macOS's own tools, and
against everything else in this space — with the gaps named honestly in both
directions.

Researched 2026-07-29. Sources at the bottom.

---

## Windows 11 Paint, as of 2026

Paint stopped being a joke around 2023. It is now the reference point for "a
simple image editor that ships with the OS", and it is the thing anyone
comparing us will compare us to.

| Capability | Windows 11 Paint | ItsPaint | Note |
|---|---|---|---|
| Pencil / brush / eraser | ✅ | ✅ | |
| Pen, highlighter | ✅ | ✅ | Plus a spray tip on the brush, the airbrush Paint dropped |
| Shapes | ✅ ~23 | ✅ 15 | Plus dash styles and per-shape fill mode |
| Text | ✅ revamped, own sub-toolbar | ✅ + bold / italic / underline, resize handles | Ours rasterises on commit; theirs stays editable in a layer |
| Fill | ✅ | ✅ + tolerance | Paint's bucket has no tolerance control |
| Colour picker | ✅ | ✅ + `⌥` from any tool | |
| Crop / resize / rotate / flip | ✅ | ✅ | |
| Transparency + checkerboard | ✅ | ✅ | |
| **Layers** | ✅ reorderable | ❌ **declined** | See [PHILOSOPHY](PHILOSOPHY.md) |
| **Rulers and grid** | ✅ | Partial — pixel grid ≥4× only | Real gap |
| **Freeform rotate** | ✅ (2026) | ✅ | `Image ▸ Rotate…`, any angle, canvas grows to fit |
| **Background removal** | ✅ on-device AI | Instant Alpha | Different mechanism, same job |
| **Generative fill / erase** | ✅ Copilot+ PCs only | ❌ **declined** | Needs a model, a network, and credits |
| Cocreator / Image Creator / stickers | ✅ Copilot+ only | ❌ declined | |
| AI credits, content watermarking | ✅ | n/a | A cost they pass on; we have none to pass |
| Tabs | ✅ (2026) | ❌ | Windows-per-document instead, which is the Mac idiom |
| Project file format | `.paint`, opaque | `.itspaint` = PNG + JSON | Ours opens in any image viewer |
| **Step badges** | ❌ | ✅ | Snagit has this; Paint does not |
| **Pixelate / de-emphasis** | ❌ | ✅ | |
| **Export breadth** | PNG/JPEG/BMP/GIF/HEIC | + TIFF, PDF, AVIF, ICO, scale control | |
| Telemetry / account / cloud | Yes | **None** | |

**The honest read.** Paint beats us on layers, rulers, freeform rotate and
one-click AI background removal. We beat it on markup-specific tooling (step
badges, pixelate, tolerance-based fill and selection), on export, on file-format
openness, and on the entire category of things that require a Microsoft account
and a Copilot+ NPU.

Three of their four advantages are cheap for us to close. The fourth — layers —
is a deliberate no, and the reason is in PHILOSOPHY: the moment a paint app has
layers it stops being "draw on a screenshot" and becomes "learn a compositing
model". Floating selections already cover paste, move, place.

### What is worth taking from their UI

Windows 11 Paint's ribbon is genuinely well organised, and two ideas transfer:

1. **A tool's variations appear only when that tool is active.** We already do
   this; it is rule 2 in PHILOSOPHY. Their shape gallery validates it.
2. **The colour section is two rows of swatches and nothing else.** Ours is now
   two swatches across the rail in either orientation, which is the same rule
   transposed. Everything beyond those two rows lives one click away.

What is worth *not* taking: the ribbon itself. It is 110pt of permanent chrome
across the full width of the window. Our rail is 48pt on one edge.

---

## The macOS side: Screenshot.app and Markup

This is the more important comparison, because it is the one that decides
whether people open us daily.

macOS already ships a capture tool (`⇧⌘3`, `⇧⌘4`, `⇧⌘5`) and an annotator
(Markup, reached from the floating thumbnail or from Preview). Between them they
cover: full screen, region, window with or without shadow, timer, save-to
location, clipboard variants with `⌃`, and an annotation set of pen, shapes,
text, signature and a magnifier loupe.

**Where Markup is weak, and it is weak in exactly the places that matter for the
job people actually use it for:**

- No step badges. Numbering the steps of a bug report is the single most common
  screenshot-markup task and Markup cannot do it.
- No pixelate or redaction of any kind.
- No crop-to-selection, no canvas resize, no scaling.
- One export path, and no format choice.
- It is *modal*. You annotate, you click Done, and the editing session is over.
  Reopening means starting again from a flattened image.
- No colour palette worth the name, and no eyedropper.

That list is the wedge. It is not "build a better Preview" — it is "the five
things Markup refuses to do are the five things a bug report needs".

See [CAPTURE.md](CAPTURE.md) for how we get into that workflow.

---

## Everything else

### Paint-class apps

| | What it is | Why it does not close the gap |
|---|---|---|
| **Krita** | The best open-source painting app | For painters. Enormous. Wrong job. |
| **GIMP** | The open-source Photoshop | Same — and its macOS build has never felt native |
| **Pinta** | Paint.NET-inspired, cross-platform, ~3.8k stars | GTK on macOS. Runs; does not feel like a Mac app. |
| **Paintbrush** | The classic macOS MS-Paint clone | **Abandoned.** Intel-only, targets OS X 10.10 and earlier. |
| **JS Paint** | Classic Paint, revived, in a browser | Delightful, and genuinely popular — but it is a browser tab |
| **KolourPaint / MyPaint** | KDE and Linux-native | Not shipped for macOS |

**The finding that matters: there is no maintained, native, Apple-silicon macOS
app in this category.** Paintbrush was it, and it has been dead for years. The
slot is empty, and "the MS Paint for modern macOS" is an unclaimed sentence.

### Capture-and-annotate apps

| | Model | Notes |
|---|---|---|
| **CleanShot X** | ~$29 one-time + cloud subscription | The benchmark. Scrolling capture, GIF and video, deep editor, self-hosted cloud. Heavy. |
| **Shottr** | Free for personal use | Closest to us in spirit: tiny, fast, scrolling capture, OCR, pixel measure. **Closed source.** |
| **Xnapper** | Paid | One job — making screenshots look good. Gradient backgrounds, auto-redaction. |
| **Snagit** | Enterprise pricing | Full-featured, corporate, expensive |
| **Snapzy, better-shot** | Open source | Young, small, low traction |

**Second finding: there is no credible open-source, native-Swift, no-network
macOS capture-and-markup tool.** Flameshot is the open-source answer everywhere
else, and it is Qt — it does not feel like a Mac app. Snapzy and better-shot are
early. Shottr occupies the "small and fast" position but is closed.

---

## The positioning that falls out of this

Two empty slots, one app:

> **The native macOS paint and markup app that has no account, no network, and
> no subscription — and that takes over your screenshot key.**

Every clause is defensible against a specific competitor:

- *native macOS* — against Pinta, GIMP, Flameshot, JS Paint
- *paint and markup* — against CleanShot X (capture-only) and Krita (paint-only)
- *no account, no network* — against Windows 11 Paint and every cloud tool
- *maintained* — against Paintbrush
- *open source* — against Shottr, CleanShot X, Xnapper
- *takes over your screenshot key* — against Markup, which is a dead end

---

## Sources

- [Windows 11 Paint — Microsoft](https://www.microsoft.com/en-us/windows/paint)
- [Everything you need to know about Paint on Windows 11 — XDA](https://www.xda-developers.com/windows-11-paint/)
- [Paint Windows 11: Features, Layers, AI Tools, and Fixes — winsides](https://winsides.com/paint-windows-11/)
- [Microsoft Paint freeform rotate — Windows Central](https://www.windowscentral.com/microsoft/windows-11/microsoft-paint-freeform-rotate-preview-announcement-photoshop-replacement)
- [Paint in Windows 11 breaks tradition with tabbed interface](https://www.getcomputerrepair.com/2026/02/21/paint-in-windows-11-tabbed-interface/)
- [Enable or Disable Generative Fill in Paint — NinjaOne](https://www.ninjaone.com/blog/enable-or-disable-generative-fill-in-the-paint-app/)
- [Take a screenshot on Mac — Apple Support](https://support.apple.com/en-us/102646)
- [Quickly Markup and Send Mac Screenshots — MacMost](https://macmost.com/quickly-markup-and-send-mac-screenshots.html)
- [Best Screenshot Apps for Mac 2026 — screensnap.pro](https://www.screensnap.pro/guides/best-screenshot-apps-mac-2026)
- [Best Shottr Alternatives for Mac 2026 — ScreenDrafter](https://screendrafter.com/blog/shottr-alternative-mac/)
- [Open Source Microsoft Paint Alternatives — AlternativeTo](https://alternativeto.net/software/microsoft-paint/?license=opensource)
- [Pinta](https://www.opensourcealternatives.to/item/pinta) · [JS Paint](https://github.com/1j01/jspaint) · [Snapzy](https://github.com/duongductrong/Snapzy) · [better-shot](https://github.com/KartikLabhshetwar/better-shot)
