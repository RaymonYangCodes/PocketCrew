#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
APP_PATH="$PROJECT_DIR/dist/PocketCrew.app"
OUTPUT_DIR="$PROJECT_DIR/download-site/public/downloads"
STAGE_DIR="$(mktemp -d /tmp/pocketcrew-dmg.XXXXXX)"
codesign --verify --deep --strict "$APP_PATH"
mkdir -p "$OUTPUT_DIR"
ditto "$APP_PATH" "$STAGE_DIR/PocketCrew.app"
cp "$PROJECT_DIR/macos/INSTALL.txt" "$STAGE_DIR/Read me.txt"
ln -s /Applications "$STAGE_DIR/Applications"
hdiutil create -volname PocketCrew -srcfolder "$STAGE_DIR" -format UDZO \
  -ov "$OUTPUT_DIR/PocketCrew.dmg"
hdiutil verify "$OUTPUT_DIR/PocketCrew.dmg"
cp "$PROJECT_DIR/dist/PocketCrew-iOS-Xcode.zip" "$OUTPUT_DIR/PocketCrew-iOS-Xcode.zip"
echo "Packaged downloads in $OUTPUT_DIR"
