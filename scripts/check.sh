#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}

plutil -lint "$project_dir/Info.plist"
zsh -n "$project_dir/scripts/build.sh"
zsh -n "$project_dir/scripts/install.sh"
zsh -n "$project_dir/scripts/uninstall.sh"
"$project_dir/scripts/build.sh"

if rg -n --hidden \
  -g '!build/**' \
  -g '!.git/**' \
  -g '!scripts/check.sh' \
  '(gho_[A-Za-z0-9]+|github_pat_[A-Za-z0-9_]+|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY|/Users/Qiu)' \
  "$project_dir"; then
  echo "Potential secret or machine-specific path found." >&2
  exit 1
fi

echo "Checks passed."
