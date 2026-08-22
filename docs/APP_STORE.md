# Mac App Store submission

Everything the App Store Connect forms ask for, staged here so submission is
transcription rather than composition. The Developer ID release path
(`.github/workflows/release.yml`) is unchanged; the Mac App Store is a second
channel, not a replacement.

## Status

**Apple ID 6796493980.** Which version is on sale, and which is being prepared
behind it, is not written down here: it moves every release and a transcribed
version number is stale the day after it is typed. `GET
/v1/apps/6796493980/appStoreVersions` answers it, and the release tooling prints
it before every publication.

Updating an existing app is a shorter loop than the first submission: the app
record, privacy label, pricing, age rating, categories and review contact are
all already set and carry across versions. Per version you need a new version
number, What's New, a build, and the submission.

```bash
scripts/appstore-archive.sh --upload
```

Then either the web UI — **+** beside "macOS App" → the new version number →
paste What's New → attach the build once Apple finishes processing it → Add
for Review — or the API, which does the same thing without a browser.

## Submitting from the command line

The whole update loop is App Store Connect API calls with an ES256 JWT signed
by an API key. No Xcode GUI step, no web portal step, no password. The order:

1. `POST /v1/appStoreVersions` — `versionString`, `platform: MAC_OS`,
   related to the app.
2. `PATCH /v1/appStoreVersions/{id}/relationships/build` — attach the build
   once it reports `VALID`.
3. `PATCH /v1/appStoreVersionLocalizations/{id}` — `whatsNew`. **Check which
   locales the app actually has.** This one has `en-GB` only, and writing to a
   locale that does not exist is a 404 rather than a create.
4. `PATCH /v1/builds/{id}` — `usesNonExemptEncryption: false`, if the build
   predates the Info.plist key below.
5. `POST /v1/reviewSubmissions`, then `POST /v1/reviewSubmissionItems` to put
   the version *in* it, then `PATCH` the submission with `submitted: true`.

Three things that each cost a failed attempt:

- **`usesNonExemptEncryption` lives on the build, not the version.** Sending
  it on `appStoreVersions` returns "unknown attribute". Shipping
  `ITSAppUsesNonExemptEncryption` in Info.plist — which this app now does —
  answers it at upload time and skips the call entirely.
- **A review submission can reach `READY_FOR_REVIEW` with zero items.**
  Creating one is not submitting anything; the item attach is a separate call
  that fails independently. Check that `/items` is non-empty before you
  believe a submission exists.
- **The Issuer ID is on a web page and in no file and no API.** It is printed
  under Users and Access ▸ Integrations ▸ App Store Connect API. Save it with
  the key.

`-allowProvisioningUpdates` on the export creates the distribution certificate
and profile itself. `security find-identity` listing only Development and
Developer ID does **not** mean the distribution identity is missing, and the
archive step falling back to "Sign to Run Locally" does not mean the export
will. The build reaching `VALID` after upload is the only proof that counts.

## Build

```bash
scripts/appstore-archive.sh --allow-provisioning
```

Archives Release as universal, asserts the things App Store validation would
otherwise fail remotely (sandbox, no `get-task-allow`, privacy manifest, icon,
category, export-compliance key), exports `dist/appstore/export/ItsPaint.pkg`
signed for the App Store, and prints the upload instructions.
`--validate-only` runs the archive and the asserts without needing the team's
certificates.

Screenshots regenerate with `scripts/appstore-screenshots.sh` into
`docs/appstore/` — four 2880×1800 PNGs, which is Apple's 16:10 Retina size.

## Listing

The fields that do not change per release:

| Field | Value |
|---|---|
| Name | ItsPaint |
| Primary category | Graphics & Design |
| Secondary category | Productivity |
| Price | Free |
| Bundle ID | com.joshlin.itspaint |
| SKU | itspaint |
| Copyright | Josh Lin |
| Locales | `en-GB` only — writing to a locale the app does not have is a 404, not a create |

The repository's voice is British English ("colours", "licence"); keep it in
the listing rather than half-translating it.

**The listing copy itself is not transcribed here any more.** The subtitle, the
promotional text, the keywords, the description and the support and marketing
URLs are held as data in the release tooling, applied field by field, and
verified by reading the listing back from Apple rather than by trusting the
`200`.

That is a deliberate deletion, and this is what it cost to learn. This section
held a second copy of all six on 2026-08-17, and every one of them disagreed
with the listing it described: the subtitle was the one retired the day before,
the support URL was the pre-domain host, the marketing URL was this repository
rather than the site, the keyword string was two terms short of the one Apple
was serving, and the description said **"Twelve tools"** while `ToolKind` had
thirteen. What it had lost was Clone and Spotlight — and the 0.11.0 release
note further down this same file says "Thirteen tools" correctly, so the file
contradicted itself as well as the app.

None of that was catchable. The repository's number-checker reads markdown and
these were quotations inside a document; the listing lives at Apple, which it
cannot see at all.

The count is now measured out of `ToolKind.swift` before the description can be
written anywhere, so a tool added or removed fails the publication rather than
quietly making the store page wrong.

### What's New

Rewritten per release from CHANGELOG.md, in user-facing terms — what changed
for someone using the app, not how it was done. 4,000 characters.

**0.12.0**

> Remove Background
> Image ▸ Remove Background keys the page out from behind your subject in one
> command — no model, no network, nothing to sign in to. If the image is too
> flat to key safely it says so and changes nothing, rather than erasing your
> picture.
>
> Signature capture
> Tools ▸ Signature… (⌃⌘S). Sign with a trackpad, mouse or tablet, or import a
> photo of a signature on paper. Either way the ink is keyed to transparent and
> trimmed to itself, so it lands on the artwork instead of dropping a white
> patch over it, and it arrives as floating content you position like a paste.
> Signatures are saved for reuse.
>
> Fixed
> • Editing an imported image and quitting no longer throws the edit away in
> silence. Every document now autosaves as the type it was opened as.
> • Saving a large screenshot no longer needs most of a gigabyte of memory, or
> holds the window while it works.
> • Undo history now scales with the canvas instead of reserving 512 MB per
> document, so a screenshot cannot quietly retain a gigabyte of pixels.
> • The canvas is no longer copied whole on every repaint, save and export.
> • Trimming borders is faster, and the canvas shadow no longer re-renders the
> artwork offscreen to find its own outline.
> • The Place / Crop / Discard bar no longer lingers over content that undo has
> already taken away.
>
> Still no account, no telemetry, and no network code at all. The README now
> carries the three commands that check that against an installed build.

**0.11.0 (first release)**

> First Mac App Store release. Thirteen tools, fifteen shapes, automatic step
> badges, pixelation, Instant Alpha, and export to nine formats.

### Screenshots

`scripts/appstore-screenshots.sh` writes `docs/appstore/01-hero.png` through
`04-export.png`, in that order — 2880×1800, Apple's 16:10 Retina size, fully
opaque. If App Store Connect ever objects to the PNG alpha channel, flatten
with `sips -s format jpeg <in> --out <out>` and upload the JPEGs.

They are **generated, not committed**: they show the interface at whatever
version produced them, so a stale set in the repository is worse than none —
it looks current and is not. Regenerate before a submission that changed
anything visible. `docs/appstore/` is gitignored.

## App Privacy (nutrition label)

- "Do you or your third-party partners collect data from this app?" — **No,
  we do not collect data from this app.** The label publishes as **Data Not
  Collected**.
- Tracking: none.

This is verifiable, not aspirational: the app has no network entitlement, no
`URLSession`/`NWConnection` anywhere in the source, and no third-party code.
`App/Resources/PrivacyInfo.xcprivacy` declares the two Required-Reason APIs
(file timestamps, UserDefaults) with their standard reason codes.

Age rating questionnaire: every category **None** → rates 4+. Content rights:
the app contains no third-party content.

## Verified against Mac App Store requirements

| Check | State |
|---|---|
| App Sandbox | On; only `files.user-selected.read-write` + app-scoped bookmarks |
| `get-task-allow` | Stripped from Release (`CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO`) |
| Privacy manifest | `PrivacyInfo.xcprivacy` bundled in Resources |
| Private API | None — verified in docs/MAC_ESSENTIALS.md |
| Self-updater | None (no Sparkle; MAS forbids self-update) |
| Third-party dependencies | None |
| Export compliance | `ITSAppUsesNonExemptEncryption` = false in Info.plist |
| Category | `public.app-category.graphics-design` in Info.plist |
| Version / build | `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in project.yml, then `xcodegen generate` — the committed `.xcodeproj` is what `xcodebuild` reads, and a re-upload of the same version needs a new build number |
| Upload toolchain | Xcode 26+ required by Apple since 2026-04-28; 26.6 installed |
| Universal | arm64 + x86_64, asserted by the archive script |

## Already done

Certificates (Apple Distribution and Mac Installer Distribution, created by
`--allow-provisioning`), the App ID, the app record, the privacy label,
pricing, availability, age rating, content rights, categories, and the App
Review contact details. None of it needs redoing per version.

## What still needs a person

Submission does not. Archive, upload, version record, release notes and review
submission all run from the command line — that is how 0.13.0 went out. What
is left is the part that is a legal declaration rather than an API call:

1. **EU trader status**, if EU distribution matters — App Information ▸
   Digital Services Act ▸ Set Up. Identity verification attached to a real
   person; without it the app cannot be distributed in the EU.
2. **Trademark clearance.** docs/PLAN.md records that the ItsPaint name passed
   a practical USPTO knock-out search, and that counsel-led clearance was named
   the gate for an App Store launch. That gate has not been closed.

Release is **`AFTER_APPROVAL`**, so an approval puts the version on the store by
itself. This document said "manual" until 0.17.0, when the API was actually
read: `asc.py create_version` has always sent `releaseType: AFTER_APPROVAL`, and
every shipped 0.16.x version carries it. Pass `MANUAL` there, or PATCH the
version, if a release ever needs to be held behind an approval — and check the
field rather than this sentence.

Nothing in this app touches the usual Mac rejection reasons — no updater, no
broad file access, no private API, no undeclared data collection.
