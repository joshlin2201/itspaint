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

# A build number the caller can raise without moving a tag.
#
# Apple refuses a build number it has already seen for a marketing version, and
# the tag that pins the marketing version cannot be moved or deleted. Without
# this, correcting a rejected upload costs a whole version number.
BUILD_OVERRIDE=()
if [[ -n "${ITSPAINT_BUILD_NUMBER:-}" ]]; then
  BUILD_OVERRIDE=(CURRENT_PROJECT_VERSION="$ITSPAINT_BUILD_NUMBER")
  echo "Build number overridden to $ITSPAINT_BUILD_NUMBER" >&2
fi

rm -rf dist/appstore
mkdir -p dist/appstore

xcodebuild archive \
  -project ItsPaint.xcodeproj -scheme ItsPaint -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  "${SIGNING[@]}" ${BUILD_OVERRIDE[@]+"${BUILD_OVERRIDE[@]}"} ${EXTRA[@]+"${EXTRA[@]}"}

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

# Manual signing when the distribution identities are in the keychain.
#
# Automatic signing asks Xcode's account for anything it is missing, and on a
# machine where Xcode has never been signed in that is every certificate: the
# export fails with `No signing certificate "Mac App Distribution" found` and
# `No Accounts`, after a successful archive, which reads like a build problem
# and is an account problem. Naming the identities and the profile needs no
# account at all. Both certificates can be created from the App Store Connect
# API with nothing but openssl — see docs/APP_STORE.md.
APP_ID_NAME="3rd Party Mac Developer Application: "
INSTALLER_NAME="3rd Party Mac Developer Installer: "
APP_CERT="$(security find-identity -v | sed -n "s/.*\"\(${APP_ID_NAME}[^\"]*\)\".*/\1/p" | head -1)"
INSTALLER_CERT="$(security find-identity -v | sed -n "s/.*\"\(${INSTALLER_NAME}[^\"]*\)\".*/\1/p" | head -1)"

{
  cat <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>export</string>
PLIST
  if [[ -n "$APP_CERT" && -n "$INSTALLER_CERT" ]]; then
    echo "Signing manually as: $APP_CERT" >&2
    printf '\t<key>teamID</key>\n\t<string>%s</string>\n' "$TEAM"
    printf '\t<key>signingStyle</key>\n\t<string>manual</string>\n'
    printf '\t<key>signingCertificate</key>\n\t<string>%s</string>\n' "$APP_CERT"
    printf '\t<key>installerSigningCertificate</key>\n\t<string>%s</string>\n' "$INSTALLER_CERT"
    printf '\t<key>provisioningProfiles</key>\n\t<dict>\n\t\t<key>com.joshlin.itspaint</key>\n\t\t<string>ItsPaint Mac App Store</string>\n\t</dict>\n'
  else
    echo "No Mac distribution identities in the keychain; falling back to automatic signing, which needs Xcode signed in." >&2
  fi
  printf '</dict>\n</plist>\n'
} > dist/appstore/ExportOptions.plist

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

# Two routes, and the one that used to be the only one needs an account.
#
# `destination: upload` authenticates as whichever account Xcode is signed in
# to, which is nothing on a machine where it has never been signed in. altool
# takes an App Store Connect API key instead, reading the .p8 from
# ~/.appstoreconnect/private_keys, and is preferred here for exactly that
# reason. The key is the same one the rest of the release tooling uses.
if [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]]; then
  xcrun altool --upload-app -f "$PKG" -t macos \
    --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
else
  echo "ASC_KEY_ID/ASC_ISSUER_ID unset; uploading as the account Xcode is signed in to." >&2
  sed 's|<string>export</string>|<string>upload</string>|' \
    dist/appstore/ExportOptions.plist > dist/appstore/UploadOptions.plist
  xcodebuild -exportArchive -archivePath "$ARCHIVE" \
    -exportOptionsPlist dist/appstore/UploadOptions.plist \
    -exportPath dist/appstore/upload ${EXTRA[@]+"${EXTRA[@]}"}
fi

echo
echo "Uploaded. The build appears in App Store Connect once Apple finishes"
echo "processing it — usually minutes. Attach it on the version page."
