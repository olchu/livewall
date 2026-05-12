#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="LiveWall"
PROJECT_PATH="$ROOT_DIR/LiveWall.xcodeproj"
SCHEME="${SCHEME:-LiveWall}"
CONFIGURATION="${CONFIGURATION:-Release}"
SIGNING="${SIGNING:-local}"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$BUILD_DIR/DerivedData}"
DIST_DIR="${DIST_DIR:-$BUILD_DIR/dist}"
STAGING_DIR="$BUILD_DIR/dmg-staging"
SIGNING_ARGS=()

case "$SIGNING" in
    local)
        SIGNING_ARGS=(
            CODE_SIGN_STYLE=Manual
            CODE_SIGN_IDENTITY=-
            DEVELOPMENT_TEAM=
        )
        ;;
    automatic)
        ;;
    none)
        SIGNING_ARGS=(CODE_SIGNING_ALLOWED=NO)
        ;;
    *)
        echo "Unknown SIGNING mode: $SIGNING" >&2
        echo "Use SIGNING=local, SIGNING=automatic, or SIGNING=none." >&2
        exit 2
        ;;
esac

echo "Building $APP_NAME ($CONFIGURATION, signing: $SIGNING)..."
BUILD_COMMAND=(
    xcodebuild
    -project "$PROJECT_PATH"
    -scheme "$SCHEME"
    -configuration "$CONFIGURATION"
    -derivedDataPath "$DERIVED_DATA_PATH"
)
if [[ ${#SIGNING_ARGS[@]} -gt 0 ]]; then
    BUILD_COMMAND+=("${SIGNING_ARGS[@]}")
fi
BUILD_COMMAND+=(build)
"${BUILD_COMMAND[@]}"

APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"
if [[ ! -d "$APP_PATH" ]]; then
    echo "App bundle was not found at: $APP_PATH" >&2
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "dev")"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"
VOLUME_NAME="$APP_NAME $VERSION"

echo "Preparing DMG staging folder..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR" "$DIST_DIR"
ditto "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

echo "Creating $DMG_PATH..."
rm -f "$DMG_PATH"
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -format UDZO \
    -ov \
    "$DMG_PATH"

echo
echo "DMG created:"
echo "$DMG_PATH"
echo
echo "SHA-256:"
shasum -a 256 "$DMG_PATH"
