#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
CHECK_DIR="$PROJECT_DIR/.build/engine-checks"

mkdir -p "$CHECK_DIR/module-cache"
cd "$PROJECT_DIR"
xcrun swiftc \
  -sdk "$SDK_PATH" \
  -module-cache-path "$CHECK_DIR/module-cache" \
  -parse-as-library \
  Sources/PocketCrew/Models.swift \
  Sources/PocketCrew/FinanceEngine.swift \
  Sources/PocketCrew/DemoData.swift \
  Sources/PocketCrew/CredentialVault.swift \
  Sources/PocketCrew/SessionMemoryStorage.swift \
  Tests/EngineChecks.swift \
  -o "$CHECK_DIR/engine-checks"
"$CHECK_DIR/engine-checks"

xcrun swiftc \
  -sdk "$SDK_PATH" \
  -module-cache-path "$CHECK_DIR/module-cache" \
  -parse-as-library \
  Sources/PocketCrew/Models.swift \
  Sources/PocketCrew/FinanceEngine.swift \
  Sources/PocketCrew/DemoData.swift \
  Sources/PocketCrew/Repository.swift \
  Sources/PocketCrew/CredentialVault.swift \
  Sources/PocketCrew/AppStore.swift \
  Tests/AccessChecks.swift \
  -o "$CHECK_DIR/access-checks"
"$CHECK_DIR/access-checks"
