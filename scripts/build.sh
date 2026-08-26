#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
build_dir="$project_dir/build"
app_dir="$build_dir/iScreenBar Studio Display Sync.app"
executable_dir="$app_dir/Contents/MacOS"

mkdir -p "$executable_dir"

xcrun swiftc -O \
  -framework AppKit \
  -framework CoreGraphics \
  -framework IOKit \
  "$project_dir/Sources/main.swift" \
  -o "$executable_dir/iScreenBarStudioSync"

install -m 644 "$project_dir/Info.plist" "$app_dir/Contents/Info.plist"
codesign --force --deep --sign - "$app_dir"

echo "Built: $app_dir"

