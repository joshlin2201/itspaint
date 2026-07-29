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
- **Edit** — Undo, Redo, Cut, Copy, Paste, Delete, Select All,
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

### Getting off ad-hoc signing

Releases are ad-hoc signed (`CODE_SIGN_IDENTITY: "-"`, `DEVELOPMENT_TEAM: ""`).
That is correct for a local build — the sandbox and its entitlements work, and
it needs no provisioning profile — but Gatekeeper rejects it on anyone else's
Mac, which is why the README has to tell people to clear the quarantine flag by
hand.

The membership is not the blocker. What is missing is a **Developer ID
Application** certificate issued under the *paid* team.

The distinction that costs people an afternoon: a free personal team and a paid
Developer Program team are different teams with different IDs, and a personal
team can only ever issue **Apple Development** certificates — which sign for
your own devices and cannot be notarised. Seeing an identity in the keychain is
not evidence that the paid team has one.

```bash
security find-identity -v -p codesigning
```

If the team ID in that output is not the one on the Developer Program
membership page, the certificate belongs to a personal team and is not the one
distribution needs.

1. **Xcode ▸ Settings ▸ Accounts.** Add the Apple ID that holds the paid
   membership — it is not necessarily the one already signed in — then select
   the paid team.
2. **Manage Certificates ▸ + ▸ Developer ID Application.** Only the Account
   Holder role can create one, and a team is capped at five.
3. Set `DEVELOPMENT_TEAM` to the paid team ID and
   `CODE_SIGN_IDENTITY: "Developer ID Application"` in the Release config of
   `project.yml`, then `xcodegen generate`. Leave `CODE_SIGN_STYLE: Manual`;
   Hardened Runtime and `CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO` are already set
   for Release.
4. **Notarise.** An app-specific password from appleid.apple.com, then:
   ```bash
   xcrun notarytool store-credentials "AC_PASSWORD" \
     --apple-id <apple-id> --team-id <paid-team-id> --password <app-specific>
   xcrun notarytool submit ItsPaint.dmg --keychain-profile "AC_PASSWORD" --wait
   xcrun stapler staple ItsPaint.dmg
   ```
5. **CI.** `release.yml` does the whole thing when the secrets are present:

   | Secret | What it is |
   |---|---|
   | `MACOS_CERTIFICATE_P12` | base64 of a `.p12` holding the certificate **and** its private key |
   | `MACOS_CERTIFICATE_PASSWORD` | the password that `.p12` was exported with |
   | `NOTARY_APPLE_ID` | the Apple ID holding the membership |
   | `NOTARY_PASSWORD` | an app-specific password, **not** the account password |
   | `NOTARY_TEAM_ID` | optional; derived from the certificate when unset |

   Both stages degrade rather than lie. With no certificate the build is
   ad-hoc and the verification asserts *ad-hoc*; with a certificate but no
   notary credentials it is signed but unstapled and says so. The install
   instructions in the release notes are composed from what actually
   happened, so a build can never tell people to clear a quarantine flag it
   does not set.

Stapling matters: it writes the notarisation ticket into the disk image so a
first launch works without a network round-trip to Apple.

**Renewal.** Notarising new builds requires an active membership. An expired
one does not break software already notarised and stapled, but nothing new can
be submitted — so if auto-renew is off, the renewal date is a release deadline.
