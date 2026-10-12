#!/usr/bin/env bash
# Explicit, user-started setup. Never reload the shell hosting the setup screen.
set -Eeuo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
mode="${1:-status}"
style="${2:-windows}"
[[ "$mode" == status || "$mode" == install ]] || exit 2
[[ "$style" == windows || "$style" == mac ]] || exit 2
state="${XDG_STATE_HOME:-$HOME/.local/state}/familiar-desktop"
config="${XDG_CONFIG_HOME:-$HOME/.config}"
architecture="$(uname -m)"
abi="$(hyprctl version | sed -n 's/^Version ABI string: //p')"
[[ "$(uname -s)" == Linux && ( "$architecture" == x86_64 || "$architecture" == aarch64 ) && "$abi" =~ ^[a-zA-Z0-9_.-]+$ ]] || { echo 'Unsupported desktop or missing Hyprland ABI.'; exit 3; }
backend_asset="familiar-desktop-linux-$architecture"
titlebars_asset="hyprbars-linux-$architecture-$abi.so"
library="$root/bin/hyprbars/$abi/hyprbars.so"
helper="$root/bin/familiar-desktop"
official_library=/usr/lib/omarchy-hyprland-titlebars/titlebars.so
for tool in sha256sum awk jq flock timeout; do
  command -v "$tool" >/dev/null || { echo "Required system tool is missing: $tool. Update Omarchy and retry."; exit 1; }
done
mkdir -p "$state"
chmod 700 "$state"
exec 9>"$state/setup.lock"
flock -n 9 || { echo 'Setup is already running. Waiting for it to finish…'; exit 4; }
verified() {
  local file="$1" asset="$2" expected actual
  [[ -f "$file" && ! -L "$file" && -f "$root/release-binaries.sha256" && ! -L "$root/release-binaries.sha256" ]] || return 1
  # Explicit development installs carry their own source-bound receipt. Never
  # modify the stable release pins or silently download stable bytes over it.
  if [[ -e "$state/dev-build.json" ]]; then
    [[ -f "$state/dev-build.json" && ! -L "$state/dev-build.json" ]] || return 1
    [[ "$(git -C "$root" status --porcelain --untracked-files=all)" == '' ]] || return 1
    expected="$(jq -er --arg source "$root" --arg sha "$(git -C "$root" rev-parse HEAD)" --arg asset "$asset" \
      'select(.schemaVersion == 1 and .channel == "development" and .sourceDirectory == $source and .commit == $sha) | .assets[$asset]' "$state/dev-build.json")" || return 1
    [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || return 1
    actual="$(sha256sum "$file")"
    [[ "${actual%% *}" == "$expected" ]]
    return
  fi
  expected="$(awk -v name="$asset" '$2 == name {print $1}' "$root/release-binaries.sha256")"
  [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || return 1
  actual="$(sha256sum "$file")"
  [[ "${actual%% *}" == "$expected" ]]
}
ready() {
  [[ ! -e "$state/setup-pending" && -x "$helper" ]] || return 1
  verified "$helper" "$backend_asset" || return 1
  # Core owns the package and its ABI. The dock/setup need only our helper;
  # the controls page provides an explicit handoff for an existing private hook.
  [[ ! -f "$official_library" ]] || return 0
  if jq -e '.backend == "omarchy"' "$config/omarchy/familiar-titlebars/owner.json" >/dev/null 2>&1; then return 0; fi
  verified "$library" "$titlebars_asset" || return 1
  jq -e --arg source "$root" --arg library "$library" '.source == $source and .library == $library and .hookVersion == 2' "$config/omarchy/familiar-titlebars/owner.json" >/dev/null 2>&1 || return 1
  grep -qF -- '-- BEGIN Familiar Desktop title bars' "$config/hypr/looknfeel.lua" 2>/dev/null
}
if [[ "$mode" == status ]]; then
  if [[ -f "$official_library" ]] || jq -e '.backend == "omarchy"' "$config/omarchy/familiar-titlebars/owner.json" >/dev/null 2>&1; then
    echo 'Omarchy manages window controls.'
  fi
  if ready; then echo 'Familiar is ready.'; exit 0; fi
  echo 'Set up Familiar to enable the dock and window controls.'
  exit 3
fi
development=false
if [[ -e "$state/dev-build.json" ]]; then
  if ! verified "$helper" "$backend_asset" ||
      { [[ ! -f "$official_library" ]] && ! verified "$library" "$titlebars_asset"; }; then
    echo 'Development bytes or source do not match their receipt; reinstall the development bundle.'; exit 1
  fi
  if [[ ! -e "$state/setup-pending" ]]; then
    echo 'Development build installed. Use its install-dev.sh to update or roll back; in-app release repair is disabled.'
    exit 1
  fi
  development=true
fi
for tool in curl git hyprctl; do
  command -v "$tool" >/dev/null || { echo "Required system tool is missing: $tool. Update Omarchy and retry."; exit 1; }
done
installed="$HOME/.config/omarchy/plugins/io.github.tcballard.familiar-desktop"
[[ -d "$installed/.git" && ! -L "$installed" && "$(cd "$installed" && pwd -P)" == "$root" ]] || { echo 'Setup must run from the installed Familiar plugin.'; exit 1; }
source_status="$(git -C "$root" status --porcelain --untracked-files=normal)" || { echo 'Could not inspect the installed source. Retry after restoring the Git checkout.'; exit 1; }
[[ -z "$source_status" ]] || { echo 'The installed plugin has local changes. Restore the reviewed source before setup.'; exit 1; }
log="$(mktemp "$state/setup-log.XXXXXX")"
finish() {
  local code=$?
  if (( code != 0 )); then
    echo 'Setup could not finish. Your personal settings have been kept. Retry below.'
    tail -c 2400 "$log"
    printf '\n'
    if verified "$helper" "$backend_asset" && [[ -x "$helper" ]]; then
      timeout --foreground --kill-after=2 15 "$helper" titlebars disable >/dev/null 2>&1 || true
    fi
  fi
  rm -f "$log"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
source "$root/bar-placement.sh"
familiar_prepare_bar_placement
# A persisted incomplete marker survives shell restart and prevents partial activation.
printf 'pending\n' > "$state/setup-pending"
echo 'Checking your desktop…'
if [[ "$development" == false && ! -f "$official_library" ]]; then
  timeout --foreground --kill-after=5 30 bash "$root/install-titlebars.sh" --check >"$log" 2>&1
fi
# Only execute an existing backend after checking it against the reviewed source.
if verified "$helper" "$backend_asset" && [[ -x "$helper" ]]; then
  timeout --foreground --kill-after=5 30 "$helper" desktop restore >"$log" 2>&1
  timeout --foreground --kill-after=5 30 "$helper" titlebars disable >"$log" 2>&1
fi
if [[ "$development" == false ]]; then
  echo 'Downloading and verifying the Familiar backend…'
  timeout --foreground --kill-after=5 240 bash "$root/install-backend.sh" >"$log" 2>&1
fi
verified "$helper" "$backend_asset"
if [[ -f "$official_library" ]]; then
  # Selection is made on the controls page; setup never assumes style consent.
  rm -f "$state/setup-pending"
  ready
  familiar_apply_bar_placement
  echo 'Familiar is ready. Choose Use Familiar controls in Window controls.'
  exit 0
fi
if [[ "$development" == false ]]; then
  echo 'Downloading and verifying window controls…'
  timeout --foreground --kill-after=5 240 bash "$root/install-titlebars.sh" >"$log" 2>&1
fi
verified "$library" "$titlebars_asset"
echo 'Setting up your window controls…'
timeout --foreground --kill-after=5 40 "$helper" titlebars setup --library "$library" --enable --style "$style" >"$log" 2>&1
jq -e '.state == "ready"' "$log" >/dev/null
echo 'Activating Familiar…'
timeout --foreground --kill-after=5 40 "$helper" titlebars apply --style "$style" --mode "$style" >"$log" 2>&1
jq -e '.state == "active" or .state == "off"' "$log" >/dev/null
rm -f "$state/setup-pending"
ready
familiar_apply_bar_placement
echo 'Familiar is ready.'
