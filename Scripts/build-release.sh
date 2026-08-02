#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
VERSION="1.0.4"
BUILD_DIR="$PROJECT_DIR/.build"
DIST_DIR="$PROJECT_DIR/dist"
APP_DIR="$DIST_DIR/MacErnet.app"
CONTENTS_DIR="$APP_DIR/Contents"
ICON_SOURCE="$PROJECT_DIR/Resources/MenuIcons/WiredNetwork.png"
ICONSET_DIR="$BUILD_DIR/MacErnet.iconset"

cd "$PROJECT_DIR"
/usr/bin/swift build -c release --arch arm64 --arch x86_64

/bin/rm -rf "$DIST_DIR" "$ICONSET_DIR"
/bin/mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources" "$ICONSET_DIR"
/usr/bin/ditto "$BUILD_DIR/apple/Products/Release/MacErnet" "$CONTENTS_DIR/MacOS/MacErnet"
/usr/bin/ditto "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
/usr/bin/ditto "$PROJECT_DIR/Resources/MenuIcons" "$CONTENTS_DIR/Resources/MenuIcons"

for size in 16 32 128 256 512; do
  /usr/bin/sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
  double_size=$((size * 2))
  /usr/bin/sips -z "$double_size" "$double_size" "$ICON_SOURCE" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$CONTENTS_DIR/Resources/MacErnet.icns"
/usr/bin/codesign --force --deep --sign - "$APP_DIR"

DMG_ROOT="$BUILD_DIR/dmg-root"
/bin/rm -rf "$DMG_ROOT"
/bin/mkdir -p "$DMG_ROOT"
/usr/bin/ditto "$APP_DIR" "$DMG_ROOT/MacErnet.app"
/bin/ln -s /Applications "$DMG_ROOT/Applications"
/usr/bin/hdiutil create -volname "MacErnet $VERSION" -srcfolder "$DMG_ROOT" -ov -format UDZO "$DIST_DIR/MacErnet-$VERSION-universal.dmg" >/dev/null
(cd "$DIST_DIR" && /usr/bin/shasum -a 256 "MacErnet-$VERSION-universal.dmg" > "MacErnet-$VERSION-universal.dmg.sha256")

echo "Built $DIST_DIR/MacErnet-$VERSION-universal.dmg"
