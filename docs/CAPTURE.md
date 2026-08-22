# Replacing the screenshot workflow

The plan for making ItsPaint the thing that happens when someone presses
`⇧⌘4` — and the honest accounting of what each route costs.

This is the stickiness play. A paint app is opened when you remember it exists.
A capture tool is opened forty times a day without thinking.

---

## What "end-to-end compatibility" actually means

Before designing anything, this is the full surface macOS already gives people.
Anything we take over has to cover all of it or we have made their Mac worse.

### The shortcuts

| Key | Behaviour |
|---|---|
| `⇧⌘3` | Whole screen, one file per display |
| `⇧⌘4` | Crosshair region. `Space` mid-drag moves the selection; `⌥` resizes from centre; `⇧` constrains one axis; `Esc` cancels |
| `⇧⌘4` then `Space` | Window or menu picker. Captures with the window shadow; `⌥`-click drops the shadow |
| `⇧⌘5` | The capture UI: whole screen / window / selection, record screen / record selection, and an **Options** menu |
| `⇧⌘6` | Touch Bar, where one exists |
| `⌃` + any of the above | To the clipboard instead of a file |

### The Options menu, which is the part people forget

Save to (Desktop / Documents / Clipboard / Mail / Messages / Preview / other),
timer (none / 5s / 10s), **show floating thumbnail**, remember last selection,
show mouse pointer.

### The rest of the contract

- Default file name `Screenshot <date> at <time>.png` on the Desktop.
- Captured at the display's real backing scale — 2× on Retina.
- The floating thumbnail: click for Markup, swipe right to dismiss, **drag it
  straight into another app** without ever creating a file, right-click for a
  destination menu, or ignore it and it saves itself.
- Screen Recording permission is per-app and per-TCC; DRM-protected content
  captures black.

**Anything that claims to replace this and drops the floating thumbnail's
drag-to-app behaviour has broken the single most-used part of it.**

---

## Four routes in, cheapest first

### Route 1 — Be the destination, not the capturer

macOS already writes screenshots somewhere. Point it at a folder, watch that
folder, open what lands.

```
defaults write com.apple.screencapture location ~/Pictures/ItsPaint
killall SystemUIServer
```

- **Permission needed: none.** No Screen Recording prompt, no Accessibility, no
  TCC dialog at all.
- **Effort: about a day.** `DispatchSource` file-system watch on a
  security-scoped bookmark, which is available to a sandboxed app.
- **Keeps: every shortcut, every option, the thumbnail, the drag behaviour.**
  We change nothing about capture, so nothing about capture can break.
- **Cost, stated plainly:** a sandboxed app cannot write another app's defaults,
  so the user either runs that command or we ship a one-click panel that
  explains it. And it only catches the *file* variants — `⌃⇧⌘4` still goes to
  the clipboard.

This is the version to ship first. It is nearly free, it cannot regress
anything, and it converts the existing OS workflow into ours.

### Route 2 — Own the clipboard variant

`⌃⇧⌘4` already puts a capture on the clipboard, and ItsPaint already opens
clipboard images. A menu-bar item plus one global hotkey that means
"paste whatever was just captured into a new document" closes the other half.

- **Permission needed: none.** `RegisterEventHotKey` (Carbon) works from a
  sandboxed app and does **not** require Accessibility, unlike
  `NSEvent.addGlobalMonitorForEvents`.
- **Effort: a day on top of route 1.**
- Together, routes 1 and 2 cover the whole capture surface without asking the
  user for a single permission.

### Route 3 — Take the key

Claim `⇧⌘4` itself. The system owns it until the user gives it up, and there is
no API to seize it — the supported path is what CleanShot X documents:

> System Settings → Keyboard → Keyboard Shortcuts → Screenshots → clear the
> shortcut, then bind it in our app.

- **Effort:** small in code, real in onboarding. Needs a first-run panel that
  deep-links to that pane (`x-apple.systempreferences:com.apple.Keyboard-Settings.extension`)
  and explains the trade in one sentence.
- **Do not do this silently, and do not do it by default.** Taking a key the
  user did not offer is how a utility becomes the thing they uninstall.

### Route 4 — Capture ourselves, with ScreenCaptureKit

`SCScreenshotManager.captureImage` on macOS 14+ gives display, window and rect
capture, correct Retina scale, and — importantly — the ability to exclude our
own overlay window from the shot.

- **Permission needed: Screen Recording (TCC).** One prompt, one trip to System
  Settings, and a relaunch. This is the friction that routes 1–3 exist to avoid.
- **What it buys that the others cannot:** live region selection with a
  magnifier and dimensions readout, window picking with our own chrome, delayed
  capture, capture-to-a-live-canvas, and eventually scrolling capture — the one
  feature every paid competitor has and the OS does not.
- **Effort: weeks, not days.** An overlay window per display, correct behaviour
  across mixed-scale multi-monitor setups, and the whole `⇧⌘5` options surface.

---

## Integration surfaces that cost almost nothing

These need no permission and no capture code, and each one is a separate door
into the app. Most are an `Info.plist` entry and a handler.

| Surface | What it gives | Effort |
|---|---|---|
| **Services menu** (`NSServices`) | "Edit in ItsPaint" on any selected image or file, system-wide | Hours |
| **Share extension** | We appear in the screenshot thumbnail's Share menu, in Finder, in Preview, in Safari | A day |
| **App Intents / Shortcuts action** | "Annotate image" becomes scriptable, and lands us in Spotlight and the Shortcuts gallery | A day |
| **Finder Quick Action** | Right-click an image → ItsPaint | Hours |
| **`Open With` default for PNG/JPEG** | Already declared as document types; needs a "make default" affordance | Hours |
| **`itspaint://` URL scheme** | Automation, and a link that opens the app | Hours |
| **Dock drag target** | Already works — the canvas accepts drops | Done |

The Share extension is the highest-value one on this list, because it puts us
*inside the floating thumbnail's own menu* — the exact moment the user is
deciding what to do with a screenshot.

---

## What we must beat, and it is not the capture

macOS Markup is a competent annotator. We do not win by capturing better than
Apple in v1; we win because of what happens after the capture:

- **Step badges.** Numbering a bug report is the most common markup task on
  earth and Markup cannot do it. We already ship it.
- **Pixelate.** Redacting a token, an email, a customer name. Markup has
  nothing. We already ship it.
- **Instant Alpha.** Knock a background out deterministically, with a tolerance
  you control and no model deciding for you. We already ship it.
- **Crop, canvas resize, scale, and nine export formats.** Markup has one path
  out.
- **It does not end.** Markup is modal — click Done and the session is over.
  An `.itspaint` document stays editable, and it is a PNG with a JSON sidecar,
  so it opens anywhere.

Four of those five are already built. That is the point: the capture layer is a
distribution mechanism for markup we have already shipped.

---

## Order of work

1. **Route 1 + Route 2** — folder watch and clipboard hotkey, behind a menu-bar
   item. No permissions, covers the whole existing workflow, ships in a week.
2. **Services + Share extension.** Every screenshot anyone takes now has an
   "ItsPaint" entry one click away.
3. **Route 3, opt-in, with a proper onboarding panel.**
4. **Route 4** only once 1–3 have proven people want this. Scrolling capture is
   the reason to eventually do it, and it is the one feature that would let us
   charge for a capture product. See [GROWTH.md](GROWTH.md).

**Non-negotiable throughout:** no network, no account, no telemetry. The reason
anyone would trust a screenshot tool with a permission this broad is that it
demonstrably cannot phone home, and the source is right there.

---

## Sources

- [Take a screenshot on Mac — Apple Support](https://support.apple.com/en-us/102646)
- [What's new in ScreenCaptureKit — WWDC23](https://developer.apple.com/videos/play/wwdc2023/10136/)
- [Using default screenshot shortcuts with CleanShot X](https://github.com/StokicDusan/til/blob/master/mac/use-default-screenshot-shortcuts-with-cleanshot-x.md)
- [Turn off the screenshot floating thumbnail — LazyScreenshots](https://www.lazyscreenshots.com/blog/disable-screenshot-floating-thumbnail-mac/)
- [Snipping Tool for Mac: the complete guide — LazyScreenshots](https://www.lazyscreenshots.com/blog/snipping-tool-for-mac/)
- [Snapzy — open-source macOS capture app](https://github.com/duongductrong/Snapzy)

## The share card bakes its claims into pixels

`docs/images/social-preview.png` is what renders on X, Slack, Discord and LinkedIn,
and as the landing page's `og:image`. It is generated, and it carries text: the app
name, the job, and a download size.

No checker can read a PNG. `claims.py` catches a stale number in prose and
`surfaces.py` catches one on the landing page, and both would sail past a share card
that had been wrong for six releases — which is exactly how the card came to be
advertising a chameleon and three measured-dead hooks for a fortnight.

So the size the card was drawn with was written here, in a file `claims.py` reads, on
the theory that when the download grows this line fails and regenerating the card is
the fix rather than editing the number.

**That did not hold, and the way it failed is worth more than the mechanism was.**
Read on 2026-08-21, the card renders `"3.15 MB"`. This paragraph claimed `3.16`. So the
line meant to mirror the card had drifted from the card, and nothing noticed, because
`claims.py` was comparing this number to *the release* — a comparison that goes red
every time a release ships, for a reason that has nothing to do with the PNG. It fired
on 0.16.4 exactly as designed and the artifact it is about was already two releases
stale. **A tripwire that is checked against a proxy is a tripwire for the proxy.**

The card is therefore knowingly stale: it says `"3.15 MB"` against a measured 3.17.
Nobody is misled by a two-hundredths-of-a-megabyte error in a number whose whole job is
"this is small", so it is not worth a hand-composed replacement that would not match
the original's type. It
gets redrawn the next time the generator runs. The size is in quotes above because it
is a *quotation of the artifact*, which is the one thing this line can be honest
about; comparing it to the release was never a check on the card at all.

Regenerate: capture a window with `WindowCaptureTests` — that part is real, it is in
`AppTests/WindowCaptureTests.swift` — then compose. The card is 1280×640 and the window
shot is bled off the right edge. **There is no compose script.** This paragraph said it
"lives with the promo tooling" and it does not live there or anywhere else in this
repository, which is the practical reason the card has not been redrawn in six
releases: the instruction named a tool that was never written. Whoever redraws it
writes that tool first, and should put it somewhere a path can point at.
