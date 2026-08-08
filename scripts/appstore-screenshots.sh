#!/bin/bash
# Regenerates docs/appstore/*.png — the Mac App Store screenshots.
#
# Three of the four window captures are the committed docs/images/*-window.png.
# The marked-up deploy-settings window is not committed anywhere at full
# resolution (the README reel ships as a GIF), so it is captured fresh here via
# WindowCaptureTests, then paint-demo composes everything onto 2880×1800.
#
# The TEST_RUNNER_ prefix is how xcodebuild forwards environment variables to
# the test process, and it only works from xcodebuild's own environment — as a
# KEY=VALUE build-settings argument it is silently ignored. The sandbox is
# disabled for this run only, so the test can write outside the container.
set -euo pipefail
cd "$(dirname "$0")/.."

REEL_DIR="$(mktemp -d "${TMPDIR:-/tmp}/itspaint-reel.XXXXXX")"
trap 'rm -rf "$REEL_DIR"' EXIT

TEST_RUNNER_ITSPAINT_REEL_DIR="$REEL_DIR" xcodebuild \
  -project ItsPaint.xcodeproj -scheme ItsPaint -destination 'platform=macOS' \
  ENABLE_APP_SANDBOX=NO CODE_SIGN_ENTITLEMENTS= \
  test -only-testing:ItsPaintTests/WindowCaptureTests

swift run -c release --package-path Packages/PaintKit paint-demo \
  --appstore "$REEL_DIR/frame-09.png" docs/appstore

# App Store Connect wants one of 1280×800, 1440×900, 2560×1600, or 2880×1800,
# fully opaque. Fail here rather than at upload.
for shot in docs/appstore/*.png; do
  size="$(sips -g pixelWidth -g pixelHeight "$shot" \
    | awk '/pixel/ {printf "%s ", $2}')"
  if [[ "$size" != "2880 1800 " ]]; then
    echo "$shot is ${size% }, expected 2880 1800" >&2
    exit 1
  fi
done
echo "Screenshots ready in docs/appstore/"
