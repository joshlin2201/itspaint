# ItsPaint 0.16.4 performance release

## Outcome

Ship the existing 0.16.4 App Store draft as a focused large-image
responsiveness release. Replace the current App Store description with short,
specific copy and remove the prose patterns that make it read as generated.

## App Store copy

Keep the current subtitle, `Paste, mark up, and send.` It is short and names the
workflow.

Use this promotional text:

> Paste a screenshot, add arrows, text or numbered steps, crop it, and drag the
> finished image straight into another app.

Use this description:

> ItsPaint is a fast, native image editor for Mac. Paste or open a screenshot,
> mark it up, crop it, and drag the finished image straight into another app.
>
> Add arrows, shapes, text, highlights, numbered steps, pixelation, Spotlight,
> Clone, and Soften. Remove a plain background, add a signature, rotate, resize,
> or adjust the canvas without building a project first.
>
> ItsPaint can open new screenshots automatically. You can also use a global
> shortcut to turn an image on the clipboard into a new document.
>
> Open PNG, JPEG, TIFF, BMP, GIF, and HEIC. Export to PNG, JPEG, TIFF, BMP, GIF,
> HEIC, AVIF, PDF, and ICO. Save editable work as an .itspaint document.
>
> No account, ads, telemetry, or cloud service. ItsPaint runs in the Mac sandbox
> and contains no network code. Your images stay on your Mac.
>
> Requires macOS 14 or later. Runs natively on Apple silicon and Intel.

The listing and release notes must contain no references to AI, models, generated
images, or competing products. They must contain no em dashes or double hyphens.
The description should explain jobs and outcomes instead of cataloguing every
control.

## Performance changes

### Core Graphics drawing

`Bitmap.drawWithCoreGraphics` currently copies the full raster into a byte
buffer, draws into that buffer, copies the result into a second array, then
replaces the original pixels. Draw directly into the bitmap array while its
mutable buffer is valid. Swift copy on write preserves any snapshot held by undo,
so this removes the redundant copy without weakening document history.

This shared change covers text, arbitrary rotation, and skew. Preserve the canvas
coordinate flip, colour layout, antialiasing controls, and existing pixel output.

### Share output

`DrawingDocument.exportedImageURL` currently creates an encoded PNG in memory and
then writes it to a temporary file. Route it through `ImageCodec.write`, which
already encodes directly to a file and replaces the destination atomically. The
share sheet keeps its existing file name and fallback behaviour.

### Export responsiveness

The export panel currently scales and encodes on the main actor after the user
chooses a destination. Capture the immutable canvas, background colour, and export
settings on the main actor, then scale and write them in a detached user initiated
task. Return only success or an actionable error to the main actor. The document
must stay editable while the export runs, and the exported file must represent the
snapshot taken when the user confirmed the panel.

## Tests and measurements

Add focused checks that prove:

1. Direct Core Graphics drawing preserves pixels outside the drawn region and
   produces the same orientation and colour output as before.
2. A large bitmap can complete a Core Graphics text or path draw inside a generous
   release budget that catches restoration of the two-copy path.
3. Shared PNG output writes the current canvas, leaves no scratch file, and keeps
   the requested file name.
4. Background export writes the captured snapshot even if the live document changes
   before the task completes.

Run the PaintKit debug and release suites, the full Xcode app suite, a Release
build, and the existing benchmark command. Compare the new benchmark to the
recorded baseline from this design pass:

```text
brush stamp x1000                 2.08 ms
freehand stroke, 490 segments     5.39 ms
shape preview, 120 frames        79.29 ms
flood fill, 3M pixels            40.55 ms
makeCGImage x60                   0.03 ms
extract 64x64 patch x1000         0.94 ms
```

## Release

Bump the public source to 0.16.4 and increment the build number above every build
already uploaded to Apple. Update the changelog with user-facing release notes.
Build and validate the Mac App Store archive, upload it, attach the processed build
to the existing 0.16.4 version, apply the new listing copy, and read each field back.
Submit the version for App Review with manual release enabled.

Push the tested source commit and tag to the public remote. The private archive has
a separate, older history and remains untouched in this release.
