#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
DIST_DIR="$PROJECT_DIR/dist"
STAGE_DIR="$(mktemp -d /tmp/pocketcrew-ios-handoff.XXXXXX)"
HANDOFF_DIR="$STAGE_DIR/PocketCrew-iOS"

mkdir -p "$DIST_DIR" "$HANDOFF_DIR/Sources/PocketCrew"
ditto "$PROJECT_DIR/ios" "$HANDOFF_DIR/ios"

for file in Models.swift FinanceEngine.swift DemoData.swift Repository.swift CredentialVault.swift AppStore.swift Theme.swift CloudServices.swift CloudViews.swift ShoppingViews.swift; do
  ditto "$PROJECT_DIR/Sources/PocketCrew/$file" "$HANDOFF_DIR/Sources/PocketCrew/$file"
done
ditto "$PROJECT_DIR/Sources/PocketCrew/Resources" "$HANDOFF_DIR/Sources/PocketCrew/Resources"
ditto "$PROJECT_DIR/supabase" "$HANDOFF_DIR/supabase"
ditto "$PROJECT_DIR/README.md" "$HANDOFF_DIR/README.md"
ditto "$PROJECT_DIR/CLOUD_SETUP.md" "$HANDOFF_DIR/CLOUD_SETUP.md"
ditto "$PROJECT_DIR/GOOGLE_SHOPPING_SETUP.md" "$HANDOFF_DIR/GOOGLE_SHOPPING_SETUP.md"
ditto "$PROJECT_DIR/Package.resolved" "$HANDOFF_DIR/Package.resolved"

ditto -c -k --norsrc --keepParent "$HANDOFF_DIR" "$DIST_DIR/PocketCrew-iOS-Xcode.zip"
echo "$DIST_DIR/PocketCrew-iOS-Xcode.zip"
