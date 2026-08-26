#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
account_name=$(id -un)
account_uid=$(id -u)
user_home_dir=$(dscl . -read "/Users/$account_name" NFSHomeDirectory | awk '{print $2}')
source_app="$project_dir/build/iScreenBar Studio Display Sync.app"
installed_app="$user_home_dir/Applications/iScreenBar Studio Display Sync.app"
launch_agents_dir="$user_home_dir/Library/LaunchAgents"
launch_agent="$launch_agents_dir/local.qiu.iScreenBarStudioSync.plist"
logs_dir="$user_home_dir/Library/Logs"
log_file="$logs_dir/iScreenBarStudioSync.log"
label="local.qiu.iScreenBarStudioSync"

"$script_dir/build.sh"

launchctl bootout "gui/$account_uid/$label" 2>/dev/null || true
mkdir -p "$user_home_dir/Applications" "$launch_agents_dir" "$logs_dir"
ditto "$source_app" "$installed_app"

escaped_executable=${installed_app//&/&amp;}
escaped_log=${log_file//&/&amp;}

{
  print '<?xml version="1.0" encoding="UTF-8"?>'
  print '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
  print '<plist version="1.0"><dict>'
  print '<key>Label</key><string>local.qiu.iScreenBarStudioSync</string>'
  print '<key>ProgramArguments</key><array>'
  print "<string>$escaped_executable/Contents/MacOS/iScreenBarStudioSync</string>"
  print '</array>'
  print '<key>RunAtLoad</key><true/>'
  print '<key>KeepAlive</key><true/>'
  print "<key>StandardOutPath</key><string>$escaped_log</string>"
  print "<key>StandardErrorPath</key><string>$escaped_log</string>"
  print '</dict></plist>'
} > "$launch_agent"

plutil -lint "$launch_agent"
launchctl bootstrap "gui/$account_uid" "$launch_agent"

echo "Installed and running. A green dot should appear in the macOS menu bar."
echo "Log: $log_file"

