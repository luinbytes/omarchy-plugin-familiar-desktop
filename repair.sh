#!/usr/bin/env bash
# Repair only this installed source; never resolve a remote tag or replace code.
set -Eeuo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
plugin_id='io.github.tcballard.familiar-desktop'
installed="$HOME/.config/omarchy/plugins/$plugin_id"
style="${1:-windows}"
[[ $# -le 1 && ( "$style" == windows || "$style" == mac ) ]] || { echo 'Usage: bash repair.sh [windows|mac]' >&2; exit 1; }
[[ -d "$installed" && "$(cd -- "$installed" && pwd -P)" == "$root" ]] || { echo 'Run repair from the installed Familiar checkout.' >&2; exit 1; }
[[ -d "$root/.git" && ! -L "$installed" ]] || { echo 'Repair requires the installed Git checkout.' >&2; exit 1; }
[[ -z "$(git -C "$root" status --porcelain --untracked-files=normal)" ]] || { echo 'Local changes found; repair will not overwrite them.' >&2; exit 1; }
# Versioned installers check ABI/checksums and replace only owned binary files.
official_library=/usr/lib/omarchy-hyprland-titlebars/titlebars.so
if [[ ! -f "$official_library" ]]; then bash "$root/install-titlebars.sh" --check; fi
if [[ -x "$root/bin/familiar-desktop" ]]; then
  "$root/bin/familiar-desktop" desktop restore
  "$root/bin/familiar-desktop" titlebars disable
fi
omarchy plugin disable "$plugin_id"
trap 'echo "Repair stopped; complete repair before enabling Familiar." >&2' ERR
bash "$root/install-backend.sh"
if [[ ! -f "$official_library" ]]; then
  library="$(bash "$root/install-titlebars.sh")"
  "$root/bin/familiar-desktop" titlebars setup --library "$library" --enable --style "$style"
fi
# Enabling rewrites plugin files, so the shell briefly unloads the plugin while it
# reloads. Retry until its IPC target is back; fail if it never returns.
shell_call() {
  local attempt output
  for attempt in {1..25}; do
    if output="$(omarchy-shell "$plugin_id" "$@" 2>&1)"; then [[ -z "$output" ]] || printf '%s\n' "$output"; return 0; fi
    sleep 0.2
  done
  printf '%s\n' "$output" >&2
  echo "Familiar did not respond to '$*' after enabling; the shell may still be reloading." >&2
  return 1
}
omarchy plugin enable "$plugin_id"
shell_call refresh
shell_call refreshTitlebars
if [[ -f "$official_library" ]]; then
  echo 'Omarchy manages the renderer. Choose Use Familiar controls in Window controls; a private-renderer migration requires logout/login.'
fi
