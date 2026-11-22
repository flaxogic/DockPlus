#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/DockPlus.xcodeproj"
SCHEME="DockPlus"
DERIVED_DATA="${TMPDIR:-/tmp}/DockPlusDerivedData"
DIST_DIR="$ROOT_DIR/dist"
APP_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      APP_PATH="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 [--app /path/to/DockPlus.app]" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$APP_PATH" ]]; then
  echo "==> Building Universal Release binary..."
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    build
  APP_PATH="$DERIVED_DATA/Build/Products/Release/DockPlus.app"
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "Error: App bundle not found at $APP_PATH" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
VOLUME_NAME="Dock+ $VERSION"
DMG_NAME="DockPlus-${VERSION}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dockplus-dmg.XXXXXX")"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH" "${DMG_PATH}.sha256"

echo "==> Staging DMG contents..."
cp -R "$APP_PATH" "$STAGING_DIR/DockPlus.app"
ln -s /Applications "$STAGING_DIR/Applications"

echo "==> Creating $DMG_PATH..."
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$DMG_PATH"

echo "==> Generating SHA-256 checksum..."
(cd "$DIST_DIR" && shasum -a 256 "$DMG_NAME" > "${DMG_NAME}.sha256")

echo ""
echo "Done!"
echo "  DMG:      $DMG_PATH"
echo "  SHA-256:  $(cat "${DMG_PATH}.sha256")"
