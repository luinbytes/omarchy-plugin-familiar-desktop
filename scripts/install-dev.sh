#!/usr/bin/env bash
# Explicit opt-in testing of a GitHub Actions artifact, never a release installer.
set -Eeuo pipefail
umask 077
source_sha='@SOURCE_SHA@'
bundle="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
plugin_id='io.github.tcballard.familiar-desktop'
plugin="$HOME/.config/omarchy/plugins/$plugin_id"
state="${XDG_STATE_HOME:-$HOME/.local/state}/familiar-desktop"
architecture="$(uname -m)"
abi="$(hyprctl version | sed -n 's/^Version ABI string: //p')"
backend_asset="familiar-desktop-linux-$architecture"
asset="hyprbars-linux-$architecture-$abi.so"
library="$plugin/bin/hyprbars/$abi/hyprbars.so"
receipt="$state/dev-build.json"
mode="${1:-install}"
initial=false
if [[ "$mode" == --initial && $# == 1 ]]; then initial=true; mode=install; fi
[[ ( "$mode" == install && $# -le 1 ) || ( "$mode" == --rollback && $# -le 2 ) ]] || { echo 'Usage: bash install-dev.sh [--initial | --rollback [SNAPSHOT]]'; exit 2; }
official_library=/usr/lib/omarchy-hyprland-titlebars/titlebars.so
official=false
[[ ! -f "$official_library" ]] || official=true
# v0.1.5 is the audited rollback baseline with a guarded private loader.
# Newer sources opt in through the handoff contract marker.
official_safe_source() {
  [[ "$1" == 439f97480bb0803f32137dcb700fbb939dc959ff ]] ||
    git -C "$plugin" show "$1:backend/src/titlebars.rs" 2>/dev/null | grep -F '// Familiar official-titlebar handoff v1' >/dev/null
}
for tool in git jq sha256sum flock omarchy hyprctl install; do
  command -v "$tool" >/dev/null || { echo "Missing $tool" >&2; exit 1; }
done
[[ "$(uname -s)" == Linux && ( "$architecture" == x86_64 || "$architecture" == aarch64 ) && "$abi" =~ ^[a-zA-Z0-9_.-]+$ ]] || { echo 'Unsupported architecture or Hyprland ABI; nothing changed.' >&2; exit 1; }
[[ -d "$plugin/.git" && ! -L "$plugin" ]] || { echo 'Install the Familiar plugin source first; use --initial for unfinished setup.' >&2; exit 1; }
[[ -z "$(git -C "$plugin" status --porcelain --untracked-files=all)" ]] || { echo 'Preserve local source changes before testing.' >&2; exit 1; }
while IFS= read -r ignored; do
  case "$ignored" in bin/familiar-desktop|bin/.familiar-desktop.dev|bin/hyprbars/*|backend/target/*) ;;
    *) echo "Unexpected ignored file: $ignored" >&2; exit 1;;
  esac
done < <(git -C "$plugin" ls-files --others --ignored --exclude-standard)
if [[ "$initial" == true ]]; then
  config="${XDG_CONFIG_HOME:-$HOME/.config}"
  for file in "$plugin/bin/familiar-desktop" "$plugin/bin/hyprbars" "$receipt"; do
    [[ ! -e "$file" && ! -L "$file" ]] || { echo 'Initial development setup requires an installation without native binaries or titlebar ownership.' >&2; exit 1; }
  done
  owner_file="$config/omarchy/familiar-titlebars/owner.json"
  if [[ -e "$owner_file" || -L "$owner_file" ]]; then
    # Official removal retains a delegation receipt to prevent a later private
    # resurrection. A hook-free receipt for this source is safe for setup retry;
    # private, foreign and symlinked ownership are not initial installations.
    [[ "$official" == true && -f "$owner_file" && ! -L "$owner_file" ]] &&
      jq -e --arg source "$plugin" '.source == $source and .backend == "omarchy"' "$owner_file" >/dev/null || {
        echo 'Existing titlebar ownership; initial setup refused.' >&2; exit 1;
      }
  fi
  ! grep -qF -- '-- BEGIN Familiar Desktop title bars' "$config/hypr/looknfeel.lua" || { echo 'Existing titlebar hook; initial setup refused.' >&2; exit 1; }
elif [[ "$mode" == install ]]; then
  installed_files=("$plugin/bin/familiar-desktop")
  [[ "$official" == true ]] || installed_files+=("$library")
  for file in "${installed_files[@]}"; do
    [[ -f "$file" && ! -L "$file" ]] || { echo "Missing or symlinked installed binary: $file" >&2; exit 1; }
  done
fi
mkdir -p "$state/dev-snapshots"
installed_ready() {
  if [[ "$official" == true ]]; then
    official_safe_source "$(git -C "$plugin" rev-parse HEAD)" || { echo 'This source predates safe official-titlebar coexistence; update Familiar first.' >&2; return 1; }
    local name file expected actual
    for name in "$backend_asset"; do
      file="$plugin/bin/familiar-desktop"
      [[ "$name" != "$asset" ]] || file="$library"
      if [[ -e "$receipt" ]]; then
        [[ -f "$receipt" && ! -L "$receipt" ]] || return 1
        expected="$(jq -er --arg source "$plugin" --arg sha "$(git -C "$plugin" rev-parse HEAD)" --arg name "$name" 'select(.schemaVersion == 1 and .channel == "development" and .sourceDirectory == $source and .commit == $sha) | .assets[$name]' "$receipt")" || return 1
      else
        expected="$(git -C "$plugin" show HEAD:release-binaries.sha256 | awk -v name="$name" '$2 == name {print $1}')" || return 1
      fi
      [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || return 1
      actual="$(sha256sum "$file")"
      [[ "${actual%% *}" == "$expected" ]] || return 1
    done
    return 0
  fi
  if [[ -f "$plugin/setup-in-app.sh" && ! -L "$plugin/setup-in-app.sh" ]]; then
    bash "$plugin/setup-in-app.sh" status
    return
  fi
  # Older verified installations predate in-app setup. Validate their recorded
  # binaries and ownership directly, including when rolling back to that source.
  [[ ! -e "$receipt" && ! -L "$receipt" && ! -e "$state/setup-pending" ]] || return 1
  local pins name file expected actual
  pins="$(git -C "$plugin" show HEAD:release-binaries.sha256)" || { echo 'Existing source has no reviewed binary pins; stop for repair.' >&2; return 1; }
  for name in "$backend_asset" "$asset"; do
    file="$plugin/bin/familiar-desktop"
    [[ "$name" != "$asset" ]] || file="$library"
    expected="$(awk -v name="$name" '$2 == name {print $1}' <<< "$pins")"
    [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || return 1
    actual="$(sha256sum "$file")"
    [[ "${actual%% *}" == "$expected" ]] || { echo "Existing binary differs from its source pin: $name" >&2; return 1; }
  done
  local config="${XDG_CONFIG_HOME:-$HOME/.config}"
  jq -e --arg source "$plugin" --arg library "$library" \
    '.source == $source and .library == $library' "$config/omarchy/familiar-titlebars/owner.json" >/dev/null || return 1
  grep -qF -- '-- BEGIN Familiar Desktop title bars' "$config/hypr/looknfeel.lua" || return 1
  echo 'Verified existing installation without in-app setup.'
}
if [[ "$mode" == install && "$initial" == false ]]; then
  # Existing install must be ready; this checks its stable pins or previous dev receipt.
  installed_ready
fi
exec 9>"$state/setup.lock"
flock -n 9 || { echo 'Another setup operation is running.' >&2; exit 1; }
current="$(git -C "$plugin" rev-parse HEAD)"
verify_assets() {
  local dir="$1" metadata="$2" name actual expected
  local names=("$backend_asset")
  [[ "$official" == true ]] || names+=("$asset")
  for name in "${names[@]}"; do
    [[ -f "$dir/$name" && ! -L "$dir/$name" ]] || return 1
    expected="$(jq -er --arg name "$name" '.assets[$name]' "$metadata")"
    [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || return 1
    actual="$(sha256sum "$dir/$name")"
    [[ "${actual%% *}" == "$expected" ]] || return 1
  done
}
if [[ "$mode" == install ]]; then
  [[ "$source_sha" =~ ^[0-9a-f]{40}$ ]] || { echo 'Use the installer from a CI development artifact.' >&2; exit 1; }
  (cd "$bundle" && sha256sum --check --strict SHA256SUMS)
  jq -e --arg sha "$source_sha" 'select(.schemaVersion == 1 and .channel == "development" and .commit == $sha and .repository == "tcballard/omarchy-plugin-familiar-desktop")' "$bundle/DEV-BUILD.json" >/dev/null
  verify_assets "$bundle" "$bundle/DEV-BUILD.json"
  git -C "$plugin" fetch --no-tags "${FAMILIAR_SOURCE_REPOSITORY:-https://github.com/tcballard/omarchy-plugin-familiar-desktop.git}" "$source_sha"
  [[ "$(git -C "$plugin" rev-parse 'FETCH_HEAD^{commit}')" == "$source_sha" ]] || exit 1
  snapshot="$(mktemp -d "$state/dev-snapshots/build-XXXXXXXX")"
  if [[ "$initial" == false ]]; then
    cp "$plugin/bin/familiar-desktop" "$snapshot/$backend_asset"
    [[ "$official" == true ]] || cp "$library" "$snapshot/$asset"
  else
    for marker in setup-pending bar-placement-pending; do
      [[ ! -e "$state/$marker" ]] || cp "$state/$marker" "$snapshot/$marker"
    done
    [[ ! -f "$owner_file" ]] || cp "$owner_file" "$snapshot/titlebar-owner.json"
  fi
  [[ ! -e "$receipt" ]] || cp "$receipt" "$snapshot/dev-build.json"
  jq -n --arg previous "$current" --arg target "$source_sha" --arg source "$plugin" --argjson initial "$initial" --argjson official "$official" \
    '{previous:$previous,target:$target,source:$source,initial:$initial,official:$official}' > "$snapshot/snapshot.json"
  (cd "$snapshot" && sha256sum ./* > SHA256SUMS)
  printf '%s\n' "$snapshot" > "$state/dev-rollback.new"
  mv "$state/dev-rollback.new" "$state/dev-rollback"
  target="$source_sha"
  bytes="$bundle"
else
  snapshot="${2:-$(cat "$state/dev-rollback")}"
  snapshot="$(realpath -e -- "$snapshot")"
  [[ "$snapshot" == "$state/dev-snapshots/"* && -d "$snapshot" && ! -L "$snapshot" ]] || { echo 'Unknown rollback snapshot.' >&2; exit 1; }
  (cd "$snapshot" && sha256sum --check --strict SHA256SUMS)
  if [[ "$official" != true ]] && jq -e '.official == true' "$snapshot/snapshot.json" >/dev/null; then
    echo 'This snapshot requires Omarchy titlebars. Restore the official package before rollback.' >&2; exit 1
  fi
  if ! jq -e '.initial == true' "$snapshot/snapshot.json" >/dev/null; then
    [[ -f "$snapshot/$backend_asset" && ! -L "$snapshot/$backend_asset" ]] || exit 1
    [[ "$official" == true || ( -f "$snapshot/$asset" && ! -L "$snapshot/$asset" ) ]] || exit 1
  fi
  jq -e --arg source "$plugin" --arg current "$current" 'select(.source == $source and (.target == $current or .previous == $current))' "$snapshot/snapshot.json" >/dev/null
  target="$(jq -er '.previous' "$snapshot/snapshot.json")"
  [[ "$target" =~ ^[0-9a-f]{40}$ ]] || exit 1
  git -C "$plugin" cat-file -e "$target^{commit}"
  bytes="$snapshot"
fi
if [[ "$official" == true ]]; then
  official_safe_source "$target" || { echo 'Rollback/source lacks the official-titlebar guard; nothing was activated. Keep Omarchy installed and use a compatible Familiar build.' >&2; exit 1; }
fi
printf 'Installing source %s\nRollback snapshot: %s\n' "$target" "$snapshot"
recovery_message() {
  local code=$?
  if (( code != 0 )); then
    printf 'Installation did not complete. Recover with: bash %q --rollback %q\n' "$bundle/install-dev.sh" "$snapshot" >&2
  fi
}
trap recovery_message EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# Reset taskbar placement with this bundle's verified helper, before replacing
# the installed backend (the previous stable version may not know taskbar).
# This helper operates only on the user's placement journal, not titlebar ownership.
if [[ -e "$HOME/.local/state/familiar-desktop/taskbar/placement.json" || -L "$HOME/.local/state/familiar-desktop/taskbar/placement.json" ]]; then
  (cd "$bundle" && sha256sum --check --strict SHA256SUMS)
  verify_assets "$bundle" "$bundle/DEV-BUILD.json"
  taskbar_helper="$(mktemp "$state/taskbar-helper.XXXXXXXX")"
  install -m 755 "$bundle/$backend_asset" "$taskbar_helper"
  taskbar_status=0
  "$taskbar_helper" taskbar reset || taskbar_status=$?
  rm -f "$taskbar_helper"
  [[ "$taskbar_status" == 0 ]] || exit "$taskbar_status"
fi
# Keep the owner's service/bar placement across disable/enable. Older Omarchy
# versions silently ignore bar placement when the id already exists in plugins;
# conversely re-enabling after removal inserts a new default bar widget.
shell_config="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/shell.json"
placement=''
[[ -f "$shell_config" && ! -L "$shell_config" ]] || { echo 'Cannot preserve plugin activation without a regular shell.json; nothing staged.' >&2; exit 1; }
if [[ -f "$shell_config" && ! -L "$shell_config" ]]; then
  if [[ "$mode" == install ]]; then
    placement="$snapshot/shell.json"
    cp "$shell_config" "$placement"
    (cd "$snapshot"; for file in ./*; do [[ "$file" == ./SHA256SUMS ]] || sha256sum "$file"; done > SHA256SUMS)
  elif [[ -f "$snapshot/shell.json" && ! -L "$snapshot/shell.json" ]] &&
      jq -e '.placementRestored != true' "$snapshot/snapshot.json" >/dev/null; then
    # Failed installation may have removed the entry; recover its saved place.
    placement="$snapshot/shell.json"
  else
    # A completed install (or legacy snapshot) keeps today's personal placement.
    placement="$(mktemp "$state/placement-recovery.XXXXXXXX")"
    cp "$shell_config" "$placement"
  fi
fi
restore_placement() {
  [[ -n "$placement" ]] || return 0
  local before after
  before="$(mktemp "$state/placement-current.XXXXXXXX")"
  after="$(mktemp "$shell_config.familiar.XXXXXXXX")"
  cp "$shell_config" "$before"
  jq --arg id "$plugin_id" --slurpfile original "$placement" '
    def key: if type == "object" then .id else . end;
    reduce [["plugins"], ["bar","layout","left"], ["bar","layout","center"],
            ["bar","layout","right"], ["disabledPlugins"]][] as $path (.;
      ($original[0] | getpath($path) // []) as $old |
      (getpath($path) // [] | map(select(key != $id))) as $current |
      (reduce range(0; $old|length) as $i ($current;
        if ($old[$i]|key) != $id then . else
          ($old[$i+1] | key) as $next |
          (if $i > 0 then ($old[$i-1]|key) else null end) as $prev |
          (map(key) | index($next)) as $n |
          (map(key) | index($prev)) as $p |
          (if $n != null then $n elif $p != null then $p+1 else ([$i,length]|min) end) as $at |
          .[:$at] + [$old[$i]] + .[$at:]
        end)) as $restored |
      if getpath($path) == null and ($restored|length) == 0 then .
      else setpath($path; $restored) end)
  ' "$before" > "$after"
  # Never overwrite a concurrent shell/config edit. The recovery copy remains.
  cmp -s "$shell_config" "$before" || { echo "Shell changed during placement restore; retained $placement" >&2; return 1; }
  mv "$after" "$shell_config"
  rm -f "$before"
}
# All source/binary mutations share this boundary, including unfinished setup.
# disable changes the shell's configuration; restart waits for the old QML
# instance and its teardown to exit before we replace anything it could read.
quiesce() {
  omarchy plugin disable "$plugin_id"
  omarchy restart shell
}
restore_activation() {
  # Restore only Familiar's entries, including disabledPlugins, so a previously
  # disabled plugin stays disabled. Do not transiently enable it or reset peers.
  flock -u 9
  restore_placement
  omarchy restart shell
  if [[ "$mode" == install ]]; then
    jq '.placementRestored = true' "$snapshot/snapshot.json" > "$snapshot/snapshot.json.new"
    mv "$snapshot/snapshot.json.new" "$snapshot/snapshot.json"
    (cd "$snapshot"; for file in ./*; do [[ "$file" == ./SHA256SUMS ]] || sha256sum "$file"; done > SHA256SUMS)
  fi
}
# ARM users cannot finish stable x86_64 setup first. Stage a source-bound local
# bundle explicitly, then let the normal setup screen apply the chosen style.
if [[ "$initial" == true ]]; then
  quiesce
  printf 'pending\n' > "$state/setup-pending"
  git -C "$plugin" checkout --detach "$target"
  [[ "$(git -C "$plugin" rev-parse HEAD)" == "$target" ]]
  mkdir -p "$plugin/bin"
  install -m 755 "$bytes/$backend_asset" "$plugin/bin/.familiar-desktop.dev"
  mv "$plugin/bin/.familiar-desktop.dev" "$plugin/bin/familiar-desktop"
  if [[ "$official" != true ]]; then
    mkdir -p "$(dirname "$library")"
    install -m 644 "$bytes/$asset" "$library.dev"
    mv "$library.dev" "$library"
  fi
  jq --arg source "$plugin" '. + {sourceDirectory:$source}' "$bundle/DEV-BUILD.json" > "$receipt.new"
  mv "$receipt.new" "$receipt"
  restore_activation
  echo 'Development binaries staged. Open Familiar and start setup to choose window controls.'
  printf 'Rollback: bash %q --rollback %q\n' "$bundle/install-dev.sh" "$snapshot"
  exit 0
fi
if [[ "$mode" == --rollback ]] && jq -e '.initial == true' "$snapshot/snapshot.json" >/dev/null; then
  config="${XDG_CONFIG_HOME:-$HOME/.config}"
  metadata="$receipt"
  if [[ ! -e "$receipt" ]]; then
    # An interrupted staging operation has never activated native controls.
    if [[ -f "$snapshot/titlebar-owner.json" ]]; then
      # An inert Core delegation may predate this attempt. It must still be
      # exactly the snapshot's receipt; never remove or rewrite later ownership.
      cmp -s "$snapshot/titlebar-owner.json" "$config/omarchy/familiar-titlebars/owner.json" || exit 1
    else
      [[ ! -e "$config/omarchy/familiar-titlebars/owner.json" ]] || exit 1
    fi
    ! grep -qF -- '-- BEGIN Familiar Desktop title bars' "$config/hypr/looknfeel.lua" || exit 1
    (cd "$bundle" && sha256sum --check --strict SHA256SUMS)
    verify_assets "$bundle" "$bundle/DEV-BUILD.json"
    metadata="$bundle/DEV-BUILD.json"
  else
    jq -e --arg source "$plugin" --arg sha "$current" 'select(.sourceDirectory == $source and .commit == $sha and .channel == "development")' "$receipt" >/dev/null
  fi
  # With no receipt, staging never activated controls. Discard partial files
  # without executing them; a failed copy need not be a complete binary.
  names=("$backend_asset")
  [[ "$official" == true ]] || names+=("$asset")
  for name in "${names[@]}"; do
    file="$plugin/bin/familiar-desktop"; [[ "$name" != "$asset" ]] || file="$library"
    if [[ ! -e "$receipt" ]]; then
      [[ ! -L "$file" ]] || exit 1
      continue
    fi
    [[ -f "$file" && ! -L "$file" ]] || exit 1
    expected="$(jq -er --arg name "$name" '.assets[$name]' "$metadata")"
    actual="$(sha256sum "$file")"
    [[ "$expected" =~ ^[0-9a-f]{64}$ && "${actual%% *}" == "$expected" ]] || { echo 'Installed development bytes are corrupt; reinstall the matching bundle before rollback.' >&2; exit 1; }
  done
  quiesce
  if [[ -e "$receipt" ]]; then
    if [[ "$official" == true ]]; then
      # Clear native actions with the verified new helper before retiring it.
      (cd "$bundle" && sha256sum --check --strict SHA256SUMS)
      verify_assets "$bundle" "$bundle/DEV-BUILD.json"
      install -m 755 "$bundle/$backend_asset" "$plugin/bin/.familiar-desktop.dev"
      mv "$plugin/bin/.familiar-desktop.dev" "$plugin/bin/familiar-desktop"
    fi
    "$plugin/bin/familiar-desktop" desktop restore
    "$plugin/bin/familiar-desktop" titlebars remove
  fi
  git -C "$plugin" checkout --detach "$target"
  rm -f -- "$plugin/bin/familiar-desktop" "$plugin/bin/.familiar-desktop.dev" "$receipt" "$receipt.new"
  if ! jq -e '.official == true' "$snapshot/snapshot.json" >/dev/null; then
    rm -f -- "$library" "$library.dev"
    rmdir -- "$(dirname "$library")" "$plugin/bin/hyprbars" 2>/dev/null || true
  fi
  for marker in setup-pending bar-placement-pending; do
    if [[ -f "$snapshot/$marker" ]]; then cp "$snapshot/$marker" "$state/$marker"; else rm -f -- "$state/$marker"; fi
  done
  restore_activation
  echo 'Initial development setup rolled back; personal settings retained.'
  exit 0
fi
# Do not run unverified partial binaries when recovering a failed install.
quiesce
if [[ "$official" == true ]]; then
  # Retire native button actions while the controls-v2 helper is still available.
  # An older rollback helper may not understand --window. Verify the bundle even
  # on recovery, and run at the installed path so ownership resolves correctly.
  (cd "$bundle" && sha256sum --check --strict SHA256SUMS)
  verify_assets "$bundle" "$bundle/DEV-BUILD.json"
  install -m 755 "$bundle/$backend_asset" "$plugin/bin/.familiar-desktop.dev"
  mv "$plugin/bin/.familiar-desktop.dev" "$plugin/bin/familiar-desktop"
  "$plugin/bin/familiar-desktop" titlebars disable
fi
if [[ "$mode" == install ]]; then
  "$plugin/bin/familiar-desktop" desktop restore
  if [[ "$official" != true ]]; then "$plugin/bin/familiar-desktop" titlebars disable; fi
else
  # The helper derives ownership from its executable path. Restore the verified
  # previous helper at that path before using it to recover a partial install.
  install -m 755 "$snapshot/$backend_asset" "$plugin/bin/.familiar-desktop.dev"
  mv "$plugin/bin/.familiar-desktop.dev" "$plugin/bin/familiar-desktop"
  "$plugin/bin/familiar-desktop" desktop restore
  if [[ "$official" != true ]]; then "$plugin/bin/familiar-desktop" titlebars disable; fi
fi
git -C "$plugin" checkout --detach "$target"
[[ "$(git -C "$plugin" rev-parse HEAD)" == "$target" ]]
install -m 755 "$bytes/$backend_asset" "$plugin/bin/.familiar-desktop.dev"
mv "$plugin/bin/.familiar-desktop.dev" "$plugin/bin/familiar-desktop"
if [[ "$official" != true ]]; then
  install -m 644 "$bytes/$asset" "$library.dev"
  mv "$library.dev" "$library"
fi
if [[ "$mode" == install ]]; then
  jq --arg source "$plugin" '. + {sourceDirectory:$source}' "$bundle/DEV-BUILD.json" > "$receipt.new"
  mv "$receipt.new" "$receipt"
elif [[ -f "$snapshot/dev-build.json" ]]; then
  cp "$snapshot/dev-build.json" "$receipt.new"
  mv "$receipt.new" "$receipt"
else
  rm -f "$receipt"
fi
# --enable is deliberately omitted: it overwrites dockEnabled, titlebarsEnabled
# and titlebarMode. The restarted controller reapplies the user's saved choices.
if [[ "$official" != true ]]; then
  "$plugin/bin/familiar-desktop" titlebars setup --library "$library"
fi
flock -u 9
installed_ready
restore_activation
printf '\nSource installed: %s\nRollback: bash %q --rollback %q\n' "$target" "$bundle/install-dev.sh" "$snapshot"
