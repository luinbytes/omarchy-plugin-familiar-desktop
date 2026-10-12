#!/usr/bin/env bash
# Run from the installed plugin. Never delete personal configuration or restore
# whole-file backups over edits made since installation.
set -euo pipefail
plugin_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
helper="$plugin_dir/bin/familiar-desktop"
plugin_id='io.github.tcballard.familiar-desktop'
[[ $# == 0 ]] || { echo 'Usage: bash uninstall.sh' >&2; exit 2; }
installed_dir="$HOME/.config/omarchy/plugins/$plugin_id"
[[ -d "$installed_dir" && "$(cd -- "$installed_dir" && pwd -P)" == "$(cd -- "$plugin_dir" && pwd -P)" ]] || {
  echo 'Run uninstall.sh from the installed Familiar plugin, not another checkout.' >&2; exit 1;
}
[[ -x "$helper" ]] || { echo 'Familiar helper is missing; reinstall the candidate before cleanup.' >&2; exit 1; }
trap 'echo "Familiar removal stopped. The plugin has not been intentionally deleted before cleanup. Resolve the error and rerun this command; retained backups are for manual recovery." >&2' ERR

# Recover the journal while the dock is still available. Unknown/shared
# minimised windows require the user to restore them rather than guessing.
"$helper" desktop prepare-remove
"$helper" taskbar reset
omarchy plugin disable "$plugin_id"
"$helper" caps-lock reset
"$helper" input-preference command reset
"$helper" input-preference resize reset
"$helper" gestures reset
"$helper" window-mode reset
"$helper" titlebars remove
# Only delete the plugin after owned hooks are removed and reload is verified.
omarchy plugin remove "$plugin_id" --yes
# The development receipt binds binaries to the checkout just removed. Kept, it
# makes a later stable installation fail setup readiness and refuse in-app setup.
# Development snapshots remain for manual recovery.
rm -f -- "${XDG_STATE_HOME:-$HOME/.local/state}/familiar-desktop/dev-build.json"
echo 'Familiar removed. Personal configuration is preserved; preferences and recovery backups are retained.'
