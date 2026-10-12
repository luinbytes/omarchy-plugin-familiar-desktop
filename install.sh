#!/usr/bin/env bash
# Interactive terminal entry point, including when downloaded from a release.
set -Eeuo pipefail
update_started=false
trap 'printf "\nFamiliar setup stopped at line %s. Fix the error above and rerun this command.\n" "$LINENO" >&2; if [[ "$update_started" == true ]]; then echo "Familiar was disabled for this update. Complete setup before enabling it again." >&2; fi' ERR
main() {
plugin_id='io.github.tcballard.familiar-desktop'
plugin_dir="$HOME/.config/omarchy/plugins/$plugin_id"
repository='https://github.com/tcballard/omarchy-plugin-familiar-desktop.git'
release='v0.1.5'
# Release CI inserts the exact built commit into the standalone release asset.
# The repository template intentionally refuses to install without this pin.
release_sha='@SOURCE_SHA@'
[[ "$release_sha" =~ ^[0-9a-f]{40}$ ]] || { echo 'Invalid release source pin.' >&2; exit 1; }
style="${1:-mac}"
if [[ $# -gt 1 || ( "$style" != mac && "$style" != windows ) ]]; then
  echo 'Usage: bash install.sh [mac|windows]' >&2
  exit 1
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
step() { printf '\n[%s/5] %s\n' "$1" "$2"; }
step 1 'Checking Omarchy and download tools'
for tool in omarchy omarchy-shell hyprctl; do
  command -v "$tool" >/dev/null || { echo "Missing $tool. Run inside Omarchy Quattro." >&2; exit 1; }
done
hyprctl -j version >/dev/null
packages=()
for pair in 'git:git' 'curl:curl' 'sha256sum:coreutils'; do
  command -v "${pair%%:*}" >/dev/null || packages+=("${pair#*:}")
done
if (( ${#packages[@]} )); then
  echo 'Installing missing download tools; pacman may ask for your password.'
  sudo pacman -S --needed "${packages[@]}"
fi
step 2 "Installing Familiar Desktop $release"
# Check the release ABI before registration or changes to a running installation.
expected_abi='efb50993780079460b0cbed1363e2166a2de1d9f_aq_0.15_hu_0.14_hg_0.5_hc_0.1_hlg_0.6'
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || { echo 'Familiar requires Linux x86_64.' >&2; exit 1; }
abi="$(hyprctl version | sed -n 's/^Version ABI string: //p')"
[[ "$abi" == "$expected_abi" ]] || { printf 'Unsupported Hyprland ABI: %s\nExpected: %s\nNothing installed.\n' "$abi" "$expected_abi" >&2; exit 1; }
if [[ -L "$plugin_dir" || ( -e "$plugin_dir" && ! -d "$plugin_dir/.git" ) ]]; then
  echo "Refusing to replace an unmanaged directory: $plugin_dir" >&2; exit 1
fi
if [[ ! -d "$plugin_dir/.git" ]]; then
  # Register only an already verified detached checkout. Adding the remote URL
  # first would expose the moving default branch to the shell's plugin rescan.
  source_stage="$(mktemp -d)"
  trap 'rm -rf -- "$source_stage"' EXIT
  git init "$source_stage"
  git -C "$source_stage" fetch --no-tags "$repository" "$release_sha"
  [[ "$(git -C "$source_stage" rev-parse --verify 'FETCH_HEAD^{commit}')" == "$release_sha" ]] || { echo 'Fetched source does not match the pinned commit.' >&2; exit 1; }
  git -C "$source_stage" checkout --detach "$release_sha"
  [[ "$(git -C "$source_stage" rev-parse --verify HEAD)" == "$release_sha" ]] || { echo 'Staged source does not match the pinned commit.' >&2; exit 1; }
  omarchy plugin add "$source_stage" --yes
  git -C "$plugin_dir" remote set-url origin "$repository"
  [[ "$(git -C "$plugin_dir" rev-parse --verify HEAD)" == "$release_sha" ]] || { echo 'Registered source does not match the pinned commit.' >&2; exit 1; }
fi
[[ -d "$plugin_dir/.git" ]] || { echo "Expected a Git installation at $plugin_dir" >&2; exit 1; }
check_clean() {
  local status ignored_files ignored
  status="$(git -C "$plugin_dir" status --porcelain --untracked-files=all)"
  [[ -z "$status" ]] || { echo 'Familiar has local source changes or untracked files. Preserve them before updating.' >&2; return 1; }
  ignored_files="$(git -C "$plugin_dir" ls-files --others --ignored --exclude-standard)"
  while IFS= read -r ignored; do
    case "$ignored" in ''|bin/familiar-desktop|bin/hyprbars/*|backend/target/*) ;;
      *) printf 'Unexpected ignored file: %s. Preserve it before updating.\n' "$ignored" >&2; return 1;;
    esac
  done <<< "$ignored_files"
}
check_clean
git -C "$plugin_dir" fetch --no-tags "$repository" "$release_sha"
[[ "$(git -C "$plugin_dir" rev-parse --verify 'FETCH_HEAD^{commit}')" == "$release_sha" ]] || { echo 'Fetched source does not match the pinned release commit.' >&2; exit 1; }
# Restore windows and unload owned controls before changing source or binaries.
helper="$plugin_dir/bin/familiar-desktop"
if [[ -x "$helper" ]]; then
  previous_version="$("$helper" --version)"
  # Helpers since 0.1.0 can restore Show Desktop windows; 0.0.x predates the command.
  if [[ "$previous_version" != 'familiar-desktop 0.0.'* ]]; then
    "$helper" desktop restore
  fi
  "$helper" titlebars disable
fi
omarchy plugin disable "$plugin_id"
update_started=true
git -C "$plugin_dir" checkout --detach "$release_sha"
[[ "$(git -C "$plugin_dir" rev-parse --verify HEAD)" == "$release_sha" ]] || { echo 'Checked-out source does not match the pinned release commit; Familiar remains disabled for this update.' >&2; exit 1; }
check_clean
step 3 'Checking compatibility and installing the verified release backend'
bash "$plugin_dir/install-titlebars.sh" --check
bash "$plugin_dir/install-backend.sh"
step 4 'Installing verified prebuilt window controls'
helper="$plugin_dir/bin/familiar-desktop"
library="$(bash "$plugin_dir/install-titlebars.sh")"
source "$plugin_dir/bar-placement.sh"
familiar_prepare_bar_placement
"$helper" titlebars setup --library "$library" --enable --style "$style"
step 5 'Enabling the dock and window controls'
omarchy plugin enable "$plugin_id"
familiar_apply_bar_placement
shell_call refresh
shell_call refreshTitlebars
update_started=false
"$helper" --version
printf '\nFamiliar Desktop %s is installed. Open Familiar Desktop in the bar to adjust Window controls.\n' "$release"
}
main "$@"
