# ItsPaint 0.16.4 Performance Release Implementation Plan

> **For Josh:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task by task.

**Goal:** Publish a focused 0.16.4 Mac App Store update with concise human-written listing copy, lower peak memory while drawing and sharing, and file export work kept off the main thread.

**Architecture:** Preserve the existing bitmap, codec, document, and release paths. Draw Core Graphics operations directly into `Bitmap.pixels`, route share output through the codec's existing direct-file writer, and capture export settings plus canvas pixels into a sendable snapshot before encoding in a user-initiated detached task. Keep App Store copy release-specific and apply it directly in App Store Connect.

**Tech Stack:** Swift 6, Core Graphics, AppKit, Swift Testing, Swift Package Manager, XcodeGen, xcodebuild, App Store Connect.

---

### Task 1: Establish the clean baseline

**Files:**
- Verify: `Packages/PaintKit/Tests/PaintKitTests/`
- Verify: `AppTests/`

- [ ] **Step 1: Run the debug engine suite**

Run: `swift test`

Expected: all engine and demo tests pass.

- [ ] **Step 2: Run the release engine suite**

Run: `swift test -c release`

Expected: all tests and throughput budgets pass.

- [ ] **Step 3: Run the app suite**

Run: `xcodebuild -project ItsPaint.xcodeproj -scheme ItsPaint -destination 'platform=macOS' test`

Expected: the app-hosted test suite passes without a host restart.

### Task 2: Remove redundant Core Graphics bitmap copies

**Files:**
- Modify: `Packages/PaintKit/Tests/PaintKitTests/CodecTests.swift`
- Modify: `Packages/PaintKit/Tests/PaintKitTests/PerformanceTests.swift`
- Modify: `Packages/PaintKit/Sources/PaintKit/Codec/CoreGraphicsBridge.swift`

- [ ] **Step 1: Add a behavior test for direct Core Graphics drawing**

Add a test that starts with a hand-built transparent bitmap, draws a small opaque rectangle through `drawWithCoreGraphics`, and checks literal top-left and bottom-left pixels. The test must catch removal of the coordinate flip or failure to write through to the bitmap.

- [ ] **Step 2: Add a generous large-draw release guard**

Time repeated Core Graphics marks on a large bitmap in `PerformanceTests.swift`. Apply the budget only in release builds and set it high enough to catch the old scratch-buffer plus result-array path without policing normal machine variance.

- [ ] **Step 3: Verify RED**

Temporarily express the intended zero-extra-copy contract through a narrow internal instrumentation hook available only to tests, or use the release budget if it fails reliably on the old implementation. Run the smallest affected tests and confirm the failure is caused by the existing two-copy path. Remove any test-only implementation probe before shipping; the permanent regression guard must assert real pixels or elapsed behavior.

Run: `swift test --filter CodecTests`

Run: `swift test -c release --filter PerformanceTests`

Expected: the new regression test fails for the old implementation's behavior or budget, while existing tests remain green.

- [ ] **Step 4: Draw into the bitmap's mutable storage**

Replace the scratch array and second `[RGBA8]` construction with one `pixels.withUnsafeMutableBytes` scope. Create the bitmap context over that storage, keep the existing vertical flip, invoke the drawing closure before the pointer expires, and let Swift's copy-on-write preserve shared undo snapshots.

- [ ] **Step 5: Verify GREEN**

Run: `swift test --filter CodecTests`

Run: `swift test -c release --filter PerformanceTests`

Expected: the new pixel and throughput guards pass.

### Task 3: Write shared images directly to disk

**Files:**
- Modify: `AppTests/DocumentTests.swift`
- Modify: `App/Document/DocumentCommands.swift`

- [ ] **Step 1: Add a share-output behavior test**

Create an `EditorModel` with literal pixels and a display name containing unsafe filename characters. Ask the share helper for its file URL, decode the written PNG, and assert that the pixels match, the filename is safe, and no encoded `Data` is exposed by the helper.

- [ ] **Step 2: Verify RED**

Run: `xcodebuild -project ItsPaint.xcodeproj -scheme ItsPaint -destination 'platform=macOS' test -only-testing:ItsPaintTests/DocumentTests`

Expected: the test fails because the share writer is private or does not yet provide the testable direct-file contract.

- [ ] **Step 3: Route sharing through `ImageCodec.write`**

Extract the smallest internal share-file helper needed by the command and test. Keep the existing temporary-directory and safe-name behavior, but call `ImageCodec.write(_:to:as:)` instead of first allocating an encoded `Data` value.

- [ ] **Step 4: Verify GREEN**

Run the focused app test command again.

Expected: the PNG exists, decodes to the captured pixels, and uses the sanitized name.

### Task 4: Encode exports from an immutable background snapshot

**Files:**
- Modify: `AppTests/DocumentTests.swift`
- Modify: `App/Document/DrawingDocument.swift`

- [ ] **Step 1: Add an export snapshot test**

Create a tiny bitmap with a literal pixel, capture an export job, mutate the live bitmap, write the job to a temporary PNG, and assert that the decoded output contains the original pixel. This catches accidentally reading live document state after the save panel closes.

- [ ] **Step 2: Verify RED**

Run the focused `DocumentTests` command.

Expected: the test fails because an immutable export job does not exist yet.

- [ ] **Step 3: Add the sendable export job**

Add an internal `Sendable` value carrying `Bitmap`, format, scale, quality, and matte. Move scaling and direct-file writing into it while preserving the existing size validation and codec errors. Keep `ExportOptions.scaled(_:)` as a thin compatibility path for its existing tests.

- [ ] **Step 4: Move encoding off the main actor**

When the save panel is accepted, capture the URL and export job on the main actor. Run the job with `Task.detached(priority: .userInitiated)`, convert any thrown error into sendable message text inside the detached task, and present an error only after returning to the main actor.

- [ ] **Step 5: Verify GREEN**

Run the focused `DocumentTests` command.

Expected: snapshot, scaling, and document tests pass.

### Task 5: Prepare version 0.16.4 and its listing

**Files:**
- Modify: `project.yml`
- Regenerate: `ItsPaint.xcodeproj/project.pbxproj`
- Modify: `CHANGELOG.md`
- Reference: `docs/superpowers/specs/2026-08-21-itspaint-0164-performance-design.md`

- [ ] **Step 1: Choose a fresh build number**

Read the highest processed or uploaded ItsPaint build in App Store Connect and choose the next integer. Do not reuse a build number even if a previous build was rejected or expired.

- [ ] **Step 2: Bump the project version**

Set `MARKETING_VERSION` to `0.16.4` and `CURRENT_PROJECT_VERSION` to the chosen build in `project.yml`, then run `xcodegen generate` so the checked-in project matches its source.

- [ ] **Step 3: Add concise release notes**

Add a 0.16.4 changelog entry covering faster drawing memory behavior, responsive background export, and concise App Store copy. Do not add AI/model comparisons, competitor references, em dashes, or double hyphens to the App Store text.

- [ ] **Step 4: Audit the exact listing copy**

Use the subtitle, promotional text, and description from the approved design. Check that each field is within App Store limits and that the listing/release notes contain no `AI`, model names, generated-content framing, competitor references, em dash, en dash, or `--`.

### Task 6: Verify, commit, push, and publish

**Files:**
- Verify: all changed files
- Build output: `dist/appstore/`

- [ ] **Step 1: Run the complete local gates**

Run: `swift test`

Run: `swift test -c release`

Run: `xcodebuild -project ItsPaint.xcodeproj -scheme ItsPaint -destination 'platform=macOS' test`

Run: `xcodebuild -project ItsPaint.xcodeproj -scheme ItsPaint -configuration Release -destination 'generic/platform=macOS' build`

Run: `swift run -c release paint-demo --bench`

Expected: all suites pass, the release app builds, and benchmark results are recorded against the baseline.

- [ ] **Step 2: Review the exact diff**

Inspect `git diff --check`, scan changed files for secrets and placeholders, and perform both correctness and senior-maintainability reviews. Fix findings and rerun affected checks.

- [ ] **Step 3: Commit and push the tested source**

Commit on `codex/itspaint-0164-performance`, push that branch to `public`, and verify the remote SHA equals the tested local SHA. Do not alter the stale private archive checkout.

- [ ] **Step 4: Run CI to terminal success**

Wait for every required GitHub Actions check on the pushed SHA. Inspect logs and fix any failure; do not treat an in-progress check as success.

- [ ] **Step 5: Archive and upload the exact build**

Run: `ITSPAINT_TEAM_ID=<verified team> scripts/appstore-archive.sh --upload`

Expected: the universal sandboxed archive passes structural assertions, exports with the team identity, and App Store Connect accepts the upload.

- [ ] **Step 6: Configure App Store Connect**

Wait for processing, attach the new build to macOS 0.16.4, apply the approved subtitle, promotional text, description, and concise release notes, then read each field back. Resolve any compliance prompts without changing app behavior claims.

- [ ] **Step 7: Submit for review and publish**

Submit version 0.16.4 for App Review with automatic release after approval. Record the submission state precisely; call it live only after the public App Store page reports 0.16.4.

- [ ] **Step 8: Tag only after the release source is final**

Create and push signed tag `v0.16.4` at the verified release SHA, then confirm the public branch and tag resolve to the intended source.
