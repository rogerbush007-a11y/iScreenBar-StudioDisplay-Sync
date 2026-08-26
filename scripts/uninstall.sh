#!/bin/zsh
set -euo pipefail

account_name=$(id -un)
account_uid=$(id -u)
user_home_dir=$(dscl . -read "/Users/$account_name" NFSHomeDirectory | awk '{print $2}')
installed_app="$user_home_dir/Applications/iScreenBar Studio Display Sync.app"
launch_agent="$user_home_dir/Library/LaunchAgents/local.qiu.iScreenBarStudioSync.plist"
trash_dir="$user_home_dir/.Trash"
timestamp=$(date +%Y%m%d-%H%M%S)
label="local.qiu.iScreenBarStudioSync"

launchctl bootout "gui/$account_uid/$label" 2>/dev/null || true
mkdir -p "$trash_dir"

if [[ -e "$installed_app" ]]; then
  mv "$installed_app" "$trash_dir/iScreenBar Studio Display Sync-$timestamp.app"
fi
if [[ -e "$launch_agent" ]]; then
  mv "$launch_agent" "$trash_dir/local.qiu.iScreenBarStudioSync-$timestamp.plist"
fi

echo "Stopped and moved installed files to Trash. The log file was preserved."

