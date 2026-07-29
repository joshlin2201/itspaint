# ItsPaint — Mac application essentials

What a Mac app is expected to do, what ItsPaint does, and where each is
implemented. This is the checklist a reviewer (or App Review) walks.

---

## Keyboard

### Tools — single key, no modifier

| Key | Tool | | Key | Tool |
|---|---|---|---|---|
| `P` | Pencil | | `T` | Text |
| `B` | Brush | | `N` | Step badge |
| `A` | Airbrush | | `K` | Fill |
| `H` | Highlighter | | `I` | Eyedropper |
| `E` | Eraser | | `M` | Select |
| `U` | Shape | | | |
| `R` | Pixelate (mosaic) | | | |

The lasso and Instant Alpha are *kinds* of selection, not separate tools —
Select carries rectangle, ellipse, lasso and Instant Alpha in its options.

Pinch or ⌘-scroll zooms continuously around the pointer; ⌘+/⌘− snap to the
ramp. Escape abandons whatever is in flight.

`⌥1`–`⌥9` pick a shape and arm the Shape tool. `⌥⌘T` moves the toolbar between
the left edge and the bottom. Holding `⌥` samples a colour with any tool, and a
right-click that does not drag opens the canvas menu.

Pixelate is `R`, not `X`. `X` is reserved for swapping the colour pair — that
binding predates every paint app on this list and overriding it would be the
single most surprising thing in the app.

### Colours and sizes

| Key | Action |
|---|---|
| `X` | Swap front / back colour |
| `⇧⌘C` | Open the colour popover |
| `[` / `]` | Decrease / increase brush size |
| `⌥1`–`⌥9` | Choose one of the first nine shape kinds |

### Canvas

| Key | Action |
|---|---|
| `Space` (hold) | Temporary pan — grab and drag the canvas with any tool |
| `⌘+` / `⌘−` | Zoom in / out (snaps to the ramp) |
| `⌘0` | Actual size |
| `⌘9` | Zoom to fit (exact scale, never above 100%) |
| `⌘'` | Show / hide the pixel grid (4× and above) |
| Arrow keys | Nudge floating content one pixel |
| `⇧` while dragging | Constrain: 45° lines, squares, circles, uniform resize |
| `⇧` / `⌥` while clicking with Instant Alpha | Add to / subtract from the selection |
| `Return` | Commit floating content |
| `Escape` | Cancel the gesture, then the floating content, then the selection |

### Standard editing

| Key | Action |
|---|---|
| `⌘Z` / `⇧⌘Z` | Undo / redo, named after the operation ("Undo Pencil") |
| `⌘X` / `⌘C` / `⌘V` | Cut / copy / paste |
| `⇧⌘V` | Paste and fit — grows the canvas rather than cropping the paste |
| `⌫` | Delete the selection |
| `⌘A` / `⇧⌘A` | Select all / deselect |
| `⇧⌘I` | Invert selection |

### Documents and windows

| Key | Action |
|---|---|
| `⌘N` / `⌘O` / `⌘W` | New / open / close |
| `⌘S` / `⇧⌘S` | Save / save as |
| `⇧⌘E` | Export… |
| `⌘P` / `⇧⌘P` | Print / page setup |
| `⌘R` | Image size… |
| `⌘K` | Crop to selection |
| `⌘M` | Minimise |
| `⌃⌘F` | Full screen |
| `⌘,` | Settings |

**No conflicts.** `App/MainMenuBuilder.swift` owns every menu equivalent;
`App/Canvas/CanvasNSView.swift` owns the unmodified keys. A test asserts every
tool shortcut is unique and that none collides with a reserved key.

---

## Menus

Every command routes through the responder chain with a `nil` target, so each
item enables itself only when something can actually perform it. A menu that
offers a command that does nothing teaches people to distrust it.

- **ItsPaint** — About, Settings…, Services, Hide/Hide Others/Show All, Quit
- **File** — New, Open, Open Recent (auto-populated), Close, Save, Save As,
  Duplicate, Rename, Move To, Revert to Saved, Export… (format + scale),
  Copy Whole Image, Share…, Page Setup, Print
- **Edit** — Undo, Redo, Cut, Copy, Paste, Paste and Fit, Delete, Select All,
  Deselect, Invert Selection, Crop to Selection, Trim Borders, Swap Colours,
  Emoji & Symbols, Start Dictation
- **View** — Zoom In/Out/Actual Size/Zoom to Fit, Show Pixel Grid, Move
  Toolbar, Colours…, Enter Full Screen
- **Image** — Image Size…, Flip H/V, Rotate ±90°/180°, Invert Colours,
  Clear Image
- **Tools** — every tool by name with its key, a Shape submenu carrying all
  fifteen shapes, then Swap Colours and Larger/Smaller Brush
- **Window** — Minimise, Zoom, Bring All to Front, window list
- **Help** — ItsPaint Help

`Duplicate`, `Rename` and `Move To` come free from `NSDocument` once the
document declares its types — they are the three File commands users notice are
missing.

---

## Documents

| Expected | Status |
|---|---|
| Open Recent | Auto-populated via `clearRecentDocuments:` (documented hook, not the private `_setMenuName:`) |
| Autosave in place | Native `.itspaint` package only — an imported PNG is the user's original and is never rewritten in the background |
| Versions / Revert | Inherited from `NSDocument` autosaving |
| Duplicate | `NSDocument.duplicate()`, also on the floating actions |
| Restore windows on relaunch | Standard state restoration |
| Drag and drop | Images from Finder, browsers, any app — land at the pointer as movable content |
| Print | `NSDocument.printDocument`, paginated to the canvas |
| Quick Look / Finder icon | Declared document type with an exported UTI |

---

## Accessibility

- Every action reachable by keyboard; logical tab order; Escape closes overlays.
- Every control has an accessibility label; icon-only buttons name themselves.
- Selected tools carry `.isSelected`.
- **Reduce Transparency** turns the glass into a genuinely opaque surface, not a
  less-tinted illusion of one.
- **Increase Contrast** outlines each tool cell so selection is not carried by
  fill alone.
- **Reduce Motion** is honoured by the shared animation tokens.
- Dynamic Type flows through the system text styles.

---

## Distribution readiness

| Item | Status |
|---|---|
| App Sandbox | On, with only `files.user-selected.read-write` and app-scoped bookmarks |
| Hardened Runtime | On for Release builds |
| Privacy manifest | `PrivacyInfo.xcprivacy`, declaring file-timestamp and UserDefaults reason codes |
| No network entitlement | The app never phones home |
| App icon | Generated at 1024 and rendered into the asset catalogue |
| Version / build | `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `project.yml` |
| Category | `public.app-category.graphics-design` |
| Copyright | `NSHumanReadableCopyright` |
| Document types + exported UTI | Declared in `Info.plist` |
| Xcode 26 | Required for App Store uploads from 2026-04-28 |
| No private API | Verified — the one private selector used early (`_setMenuName:`) was removed |

**Not done, and not automatable from here:** App Store Connect record, pricing,
screenshots (16:10 at 2880×1800), and submission. Those need the Apple Developer
account and interactive steps.
