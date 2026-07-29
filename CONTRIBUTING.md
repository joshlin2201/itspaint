# Contributing

Thanks for looking. This is a small, deliberately-scoped app; the fastest way
to get a change merged is to keep it in that spirit.

## Getting set up

```bash
git clone https://github.com/joshlin2201/itspaint.git
cd itspaint
open ItsPaint.xcodeproj        # Xcode 16 or later
```

The generated project is committed, so a clone needs nothing but Xcode. If you
change `project.yml`, regenerate with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen && xcodegen generate
```

## Running the tests

```bash
swift test --package-path Packages/PaintKit               # engine
swift test -c release --package-path Packages/PaintKit    # + throughput guards
xcodebuild -project ItsPaint.xcodeproj -scheme ItsPaint \
           -destination 'platform=macOS' test             # app integration
```

The engine suite is where most coverage lives and it runs in a fifth of a
second — run it constantly. The app suite drives real AppKit views offscreen,
so it needs a logged-in GUI session.

## Read first

- [docs/PHILOSOPHY.md](docs/PHILOSOPHY.md) — the five rules the app is held to.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — where code goes, with recipes
  for adding a tool, a shape or an export format.
- [docs/TESTING.md](docs/TESTING.md) — the four tests a new tool needs, and the
  app-host traps.

## What a good change looks like

- **The engine stays UI-free.** `PaintKit` has no AppKit, no SwiftUI and no
  third-party dependencies. That is what makes the whole tool matrix testable
  in milliseconds. New drawing behaviour belongs there; new *chrome* belongs in
  `App/`.
- **Every mutating engine call returns its dirty rect.** Redraw and undo capture
  are both scoped to it. Returning the whole canvas is how a large document
  starts dropping frames.
- **Tests assert pixels, not screenshots.** `#expect(canvas.pixel(at: p) == …)`
  names the pixel that moved; an image diff shows two similar-looking PNGs.
- **The rail lists jobs, not variations.** Fifteen shapes live inside one Shape
  tool. If a feature wants a new rail button, check first whether it is really
  an option of an existing tool — a guard test fails the build past fourteen.
- **Comments explain the decision, not the code.** Why this approach and what
  it costs; the code already says what it does.

## Reporting a bug

Include the macOS version, what you did, what happened, and what you expected.
A `.itspaint` file or a screenshot that reproduces it is worth a paragraph of
description. GitHub issues are public, so remove private artwork, filenames,
credentials, and personal information before attaching either one.

## Licence

By contributing you agree that your work ships under the [MIT licence](LICENSE).
