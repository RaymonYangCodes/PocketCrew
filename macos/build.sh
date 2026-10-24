#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
BUILD_DIR="$PROJECT_DIR/.build"
DIST_DIR="$PROJECT_DIR/dist"
APP_DIR="$DIST_DIR/PocketCrew.app"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"

cd "$PROJECT_DIR"
mkdir -p "$BUILD_DIR/module-cache"
env CLANG_MODULE_CACHE_PATH="$BUILD_DIR/module-cache" SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_DIR/module-cache" SDKROOT="$SDK_PATH" \
  xcrun swift build --disable-sandbox -c release --scratch-path "$BUILD_DIR/swiftpm-release"

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$ICONSET_DIR"
cp "$BUILD_DIR/swiftpm-release/release/PocketCrew" "$APP_DIR/Contents/MacOS/PocketCrew"
cp "$PROJECT_DIR/macos/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/Sources/PocketCrew/Resources/PrivacyInfo.xcprivacy" "$APP_DIR/Contents/Resources/PrivacyInfo.xcprivacy"
cp "$PROJECT_DIR/macos/CloudConfig.plist" "$APP_DIR/Contents/Resources/CloudConfig.plist"

RESOURCE_BUNDLE="$BUILD_DIR/swiftpm-release/release/PocketCrew_PocketCrew.bundle"
if [[ -d "$RESOURCE_BUNDLE" ]]; then
  cp -R "$RESOURCE_BUNDLE" "$APP_DIR/Contents/Resources/"
fi

sips -s format png "$PROJECT_DIR/macos/AppIcon.svg" --out "$BUILD_DIR/AppIcon-1024.png" >/dev/null
for spec in "16:icon_16x16.png" "32:icon_16x16@2x.png" "32:icon_32x32.png" "64:icon_32x32@2x.png" "128:icon_128x128.png" "256:icon_128x128@2x.png" "256:icon_256x256.png" "512:icon_256x256@2x.png" "512:icon_512x512.png" "1024:icon_512x512@2x.png"; do
  size="${spec%%:*}"
  name="${spec##*:}"
  sips -z "$size" "$size" "$BUILD_DIR/AppIcon-1024.png" --out "$ICONSET_DIR/$name" >/dev/null
done
iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/AppIcon.icns"

codesign --force --deep --sign - "$APP_DIR"
ditto -c -k --norsrc --keepParent "$APP_DIR" "$DIST_DIR/PocketCrew-macOS.zip"
echo "$APP_DIR"
