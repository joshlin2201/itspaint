## What this changes

<!-- One or two sentences. Link the issue if there is one. -->

## Why

<!-- The decision and its cost, the way the comments in this repo do it. -->

## Checks

- [ ] `swift test --package-path Packages/PaintKit` passes
- [ ] `xcodebuild -project ItsPaint.xcodeproj -scheme ItsPaint -destination 'platform=macOS' test` passes
- [ ] New behaviour has a test that fails without the change
- [ ] No new rail buttons, dependencies, or UI-layer code inside `PaintKit`
