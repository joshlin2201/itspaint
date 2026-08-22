#!/bin/bash
# Archives ItsPaint for the Mac App Store and exports the signed installer pkg.
# The Developer ID release path lives in .github/workflows/release.yml and is
# untouched by this script.
#
# Needs, once, on the machine that runs it:
#   - Xcode signed in to the team account (Settings → Accounts)
#   - An "Apple Distribution" and a "Mac Installer Distribution" certificate
#     (Settings → Accounts → Manage Certificates… → +)
# The Mac App Store provisioning profile is fetched automatically when run
# with --allow-provisioning (which lets xcodebuild register the app ID and
# create the profile in the developer account).
#
# Modes:
#   scripts/appstore-archive.sh                      distribution-signed export
#   scripts/appstore-archive.sh --allow-provisioning …and let Xcode fetch/create
#                                                    the profile it needs
#   scripts/appstore-archive.sh --validate-only      ad-hoc archive + structural
#                                                    asserts, no account needed
#   scripts/appstore-archive.sh --upload             …and send it to App Store
#                                                    Connect when the export is
#                                                    done
set -euo pipefail
cd "$(dirname "$0")/.."

# No baked-in default.
#
# The team ID used to be hardcoded here as a fallback. It is also the value of
# the NOTARY_TEAM_ID secret, and GitHub masks secret values in public logs — so
# the repository's own script defeated that masking in plaintext. The ID is
# recoverable from any signed release with `codesign -dv`, so the impact is
# small, but a mitigation the project believes it has and does not is worth more
# than the inconvenience of setting a variable.
if [[ -z "${ITSPAINT_TEAM_ID:-}" ]]; then
  echo "Set ITSPAINT_TEAM_ID to your Apple Developer team ID." >&2
  echo "Find it with: security find-identity -v -p codesigning | grep 'Developer ID Application'" >&2
  exit 2
fi
TEAM="$ITSPAINT_TEAM_ID"
ARCHIVE=dist/appstore/ItsPaint.xcarchive
EXPORT=dist/appstore/export

MODE=distribution
UPLOAD=false
EXTRA=(-allowProvisioningUpdates)
# Every argument, not just the first.
#
# This used to `case "${1:-}"`, so the documented-looking
# `--allow-provisioning --upload` matched the first flag, dropped the second,
# and exported a pkg while reporting "Re-run with --upload". A release step that
# silently does less than it was asked is worse than one that refuses: the run
# went green and nothing had been delivered.
for arg in "$@"; do
  case "$arg" in
    --allow-provisioning) ;;
    --upload) UPLOAD=true ;;
    --validate-only) MODE=validate; EXTRA=() ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done
if [[ "$MODE" == "validate" && "$UPLOAD" == "true" ]]; then
  echo "--validate-only skips the distribution export, so there is nothing to upload." >&2
  exit 2
fi

# CODE_SIGN_IDENTITY has to be overridden explicitly: project.yml pins it to "-"
# for local builds, and that pin outranks CODE_SIGN_STYLE=Automatic, so without
# this the archive signs ad-hoc and exportArchive fails with the thoroughly
# unhelpful "No Team Found in Archive".
#
# It has to be "Apple Development", not "Apple Distribution". Automatic signing
# archives with the development identity and exportArchive re-signs for
# distribution; naming the distribution identity here is the "conflicting
# provisioning settings" error instead.
SIGNING=(
  CODE_SIGN_STYLE=Automatic
  DEVELOPMENT_TEAM="$TEAM"
  CODE_SIGN_IDENTITY="Apple Development"
  PROVISIONING_PROFILE_SPECIFIER=
)
if [[ "$MODE" == "validate" ]]; then
  SIGNING=(CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=-)
fi

rm -rf dist/appstore
mkdir -p dist/appstore

xcodebuild archive \
  -project ItsPaint.xcodeproj -scheme ItsPaint -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  "${SIGNING[@]}" ${EXTRA[@]+"${EXTRA[@]}"}

# The asserts that App Store validation would otherwise fail remotely.
APP="$ARCHIVE/Products/Applications/ItsPaint.app"
INFO="$APP/Contents/Info.plist"
ENTITLEMENTS="$(mktemp)"

lipo "$APP/Contents/MacOS/ItsPaint" -verify_arch arm64 x86_64
codesign -d --entitlements :- "$APP" > "$ENTITLEMENTS" 2>/dev/null
test "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$ENTITLEMENTS")" = true
if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$ENTITLEMENTS" >/dev/null 2>&1; then
  echo "Archive must not contain get-task-allow" >&2
  exit 1
fi
test -f "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
test "$(/usr/libexec/PlistBuddy -c 'Print :LSApplicationCategoryType' "$INFO")" = public.app-category.graphics-design
test "$(/usr/libexec/PlistBuddy -c 'Print :ITSAppUsesNonExemptEncryption' "$INFO")" = false
/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$INFO" >/dev/null
rm -f "$ENTITLEMENTS"
echo "Archive structure OK: universal, sandboxed, no get-task-allow, manifest + icon + category present."

if [[ "$MODE" == "validate" ]]; then
  echo "Validate-only mode: skipping the distribution export (needs the team's certificates)."
  exit 0
fi

# Assert the archive carries a real team identity. Everything above passes on an
# ad-hoc archive too, and an ad-hoc archive cannot be exported — better to say
# so here than to read "No Team Found in Archive" from exportArchive. The
# distribution identity is applied by the export below, not here.
SIGNATURE="$(codesign -dv --verbose=4 "$APP" 2>&1)"
if [[ "$SIGNATURE" == *"Signature=adhoc"* || "$SIGNATURE" != *"TeamIdentifier=$TEAM"* ]]; then
  echo "Archive is not signed by team $TEAM. Got:" >&2
  echo "$SIGNATURE" | grep -E 'Authority|Signature|TeamIdentifier' >&2
  exit 1
fi
echo "Archive signed by team $TEAM; the export re-signs it for distribution."

cat > dist/appstore/ExportOptions.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>export</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist dist/appstore/ExportOptions.plist \
  -exportPath "$EXPORT" ${EXTRA[@]+"${EXTRA[@]}"}

PKG="$EXPORT/ItsPaint.pkg"
test -f "$PKG"
pkgutil --check-signature "$PKG"

if [[ "$UPLOAD" != "true" ]]; then
  echo
  echo "Ready to upload: $PKG"
  echo "Re-run with --upload, or use Xcode Organizer / Transporter — see"
  echo "docs/APP_STORE.md for the App Store Connect steps."
  exit 0
fi

# Uploading needs no API key: `destination: upload` authenticates as whichever
# account Xcode is signed in to. A second export rather than `altool` on the
# pkg above, because altool is the path that wants its own credentials.
sed 's|<string>export</string>|<string>upload</string>|' \
  dist/appstore/ExportOptions.plist > dist/appstore/UploadOptions.plist

xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist dist/appstore/UploadOptions.plist \
  -exportPath dist/appstore/upload ${EXTRA[@]+"${EXTRA[@]}"}

echo
echo "Uploaded. The build appears in App Store Connect once Apple finishes"
echo "processing it — usually minutes. Attach it on the version page."
