#!/bin/bash
set -euo pipefail
# Run in an isolated build-machine copy. This does not install or launch any app.
library_dir="$(cd "$(dirname "$0")/.." && pwd)"
: "${TAURI_IOS_API_PATH:?Set to tauri-2.x/mobile/ios-api from the Cargo registry}"
: "${LAYOUT_SIMULATOR_ID:?Set to an available simulator UUID (compile only)}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p "$library_dir/.tauri" "$library_dir/verification/build"
if [ ! -e "$library_dir/.tauri/tauri-api" ]; then
  ln -s "$TAURI_IOS_API_PATH" "$library_dir/.tauri/tauri-api"
fi
xcodegen generate --spec "$library_dir/verification/project.yml" --project "$library_dir/verification"
xcodebuildmcp simulator build \
  --project-path "$library_dir/verification/LayoutPluginCheck.xcodeproj" \
  --scheme LayoutPluginCheck --simulator-id "$LAYOUT_SIMULATOR_ID" \
  --derived-data-path "$library_dir/verification/build/DerivedData" \
  --extra-args 'CODE_SIGNING_ALLOWED=NO' 'IPHONEOS_DEPLOYMENT_TARGET=17.0' \
  --output json
