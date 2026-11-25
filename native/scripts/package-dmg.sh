#!/bin/sh
# Builds Burrow for Mac (Release, universal) and packages it as a disk image
# with an Applications shortcut: native/build/Burrow-<version>.dmg.
# Copied from Daybook's mac/scripts/package-dmg.sh; the same signing and notarizing.
#
#   native/scripts/package-dmg.sh
#   DEVELOPER_ID="Developer ID Application: … (TEAMID)" NOTARY_PROFILE=daybook native/scripts/package-dmg.sh
#
# Signing: with DEVELOPER_ID set the app is signed with it and the hardened runtime,
# and so are the helpers inside Sparkle.framework (the updater). With notary
# credentials too the image is notarized and stapled, so it opens without a
# Gatekeeper prompt. The first of these that is set is used:
#   NOTARY_PROFILE                            a `xcrun notarytool store-credentials` profile
#                                             (this Mac has "daybook"; it notarizes any app of the team)
#   NOTARY_KEY, NOTARY_KEY_ID, NOTARY_ISSUER  an App Store Connect API key (.p8 path; the
#                                             issuer ID is left out for an individual key)
#   NOTARY_APPLE_ID, NOTARY_PASSWORD, NOTARY_TEAM_ID   an Apple ID and app-specific password
# Without them the app is ad-hoc signed: macOS 15+ says it "could not verify"
# Burrow (Done / Move to Trash), and each person has to choose Done, then System
# Settings → Privacy & Security → Open Anyway (see native/README.md).
#
#   NOTARIZE_ONLY=1 … package-dmg.sh   notarizes and staples the image already in
#                                       native/build (after a notary failure), without rebuilding.
# .github/workflows/mac-release.yml runs this for each burrow-v* tag.
set -eu

cd "$(dirname "$0")/.."
OUT=build
DD="$OUT/dd"
STAGE="$OUT/dmg"
APP="$DD/Build/Products/Release/Burrow.app"
VERSION=$(sed -n 's/^MARKETING_VERSION = //p' Config/Shared.xcconfig)
DMG="$OUT/Burrow-$VERSION.dmg"

notarize() {
  # The script takes no arguments, so its own argument list holds notarytool's credentials.
  if [ -n "${NOTARY_PROFILE:-}" ]; then
    set -- --keychain-profile "$NOTARY_PROFILE"
  elif [ -n "${NOTARY_KEY:-}" ]; then
    set -- --key "$NOTARY_KEY" --key-id "${NOTARY_KEY_ID:?NOTARY_KEY needs NOTARY_KEY_ID}"
    if [ -n "${NOTARY_ISSUER:-}" ]; then set -- "$@" --issuer "$NOTARY_ISSUER"; fi
  elif [ -n "${NOTARY_APPLE_ID:-}" ]; then
    set -- --apple-id "$NOTARY_APPLE_ID" \
      --password "${NOTARY_PASSWORD:?NOTARY_APPLE_ID needs NOTARY_PASSWORD}" \
      --team-id "${NOTARY_TEAM_ID:?NOTARY_APPLE_ID needs NOTARY_TEAM_ID}"
  else
    set --
  fi
  if [ $# -gt 0 ]; then
    # notarytool can exit 0 for a rejected image, so read the verdict instead.
    xcrun notarytool submit "$DMG" "$@" --wait --output-format json > "$OUT/notary.json" 2> "$OUT/notary.err" || true
    STATUS=$(plutil -extract status raw -o - "$OUT/notary.json" 2>/dev/null || echo "no result")
    if [ "$STATUS" != Accepted ]; then
      echo "Notarization: $STATUS" >&2
      cat "$OUT/notary.json" "$OUT/notary.err" >&2
      ID=$(plutil -extract id raw -o - "$OUT/notary.json" 2>/dev/null || true)
      if [ -n "$ID" ]; then xcrun notarytool log "$ID" "$@" >&2 || true; fi
      echo "The image is signed but not notarized. Once fixed: NOTARIZE_ONLY=1 NOTARY_PROFILE=… $0" >&2
      exit 1
    fi
    xcrun stapler staple "$DMG"
  fi
}

if [ "${NOTARIZE_ONLY:-}" = 1 ]; then
  [ -f "$DMG" ] || { echo "no $DMG to notarize; build it first" >&2; exit 1; }
  notarize
  xcrun stapler validate "$DMG"
  shasum -a 256 "$DMG"
  exit 0
fi

rm -rf "$STAGE" "$DMG" "$OUT/notary.json" "$OUT/notary.err"
mkdir -p "$OUT"

# Xcode adds get-task-allow (debugger access) to every `build` unless told not
# to, and the notary service rejects an app that has it.
build() {
  xcodebuild -workspace Burrow.xcworkspace -scheme Burrow -configuration Release \
    -derivedDataPath "$DD" -destination 'generic/platform=macOS' \
    ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO "$@" build -quiet
}

if [ -n "${DEVELOPER_ID:-}" ]; then
  # Each setting is its own argument, so an identity with spaces stays whole.
  # The team comes from the identity's "(TEAMID)".
  TEAM=$(printf '%s\n' "$DEVELOPER_ID" | sed -n 's/.*(\([A-Z0-9]*\))$/\1/p')
  build "CODE_SIGN_IDENTITY=$DEVELOPER_ID" ${TEAM:+"DEVELOPMENT_TEAM=$TEAM"} CODE_SIGN_STYLE=Manual \
    ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS=--timestamp
else
  build CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=
fi

if [ -n "${DEVELOPER_ID:-}" ]; then
  # Sparkle's installer, downloader and helper apps come ad-hoc signed, and Xcode
  # re-signs only the framework around them, which the notary service rejects.
  # Sign each one, inside out in the order Sparkle documents, then the app again,
  # keeping the entitlements Xcode resolved. Never --deep.
  SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
  sign() { codesign --force --sign "$DEVELOPER_ID" --options runtime --timestamp "$@"; }
  sign "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
  sign --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
  sign "$SPARKLE/Versions/B/Autoupdate"
  sign "$SPARKLE/Versions/B/Updater.app"
  sign "$SPARKLE"
  sign --preserve-metadata=entitlements "$APP"
  codesign --verify --deep --strict "$APP"
fi

# The window the image opens in: paper, the Tunnel mark's arrow to Applications
# (dmg/settings.py, dmg/background.tiff). dmgbuild writes it without scripting
# Finder, so it works on CI too; it comes from uvx or pipx. Without either, a plain window.
if command -v uvx > /dev/null 2>&1; then
  DMGBUILD="uvx --from dmgbuild==1.6.7 dmgbuild"
elif command -v pipx > /dev/null 2>&1; then
  DMGBUILD="pipx run --spec dmgbuild==1.6.7 dmgbuild"
else
  DMGBUILD=""
fi
if [ -n "$DMGBUILD" ]; then
  $DMGBUILD -s dmg/settings.py -D app="$APP" -D background="$(pwd)/dmg/background.tiff" Burrow "$DMG"
else
  echo "warning: no uvx or pipx, so the image opens in a plain window" >&2
  mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname Burrow -srcfolder "$STAGE" -ov -format UDZO "$DMG" -quiet
  # The staging folder links to /Applications; don't leave it for tools that walk the repo.
  rm -rf "$STAGE"
fi

if [ -n "${DEVELOPER_ID:-}" ]; then
  codesign --sign "$DEVELOPER_ID" --timestamp "$DMG"
  notarize
fi

shasum -a 256 "$DMG"
echo "Built $DMG ($(du -h "$DMG" | cut -f1)), version $(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString)"
