#!/usr/bin/env bash
# This intentionally cannot run against a developer's normal desktop.
set -Eeuo pipefail
[[ ${FAMILIAR_DISPOSABLE_SMOKE:-} == 1 && $HOME == /home/familiar-smoke && $(id -un) == familiar-smoke ]] || {
  echo 'Requires the disposable CI account, not a personal desktop.' >&2; exit 2;
}
: "${SMOKE_ROOT:?}" "${SOURCE_SHA:?}" "${OMARCHY_SHA:?}"
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export OMARCHY_PATH="$SMOKE_ROOT/upstream-omarchy"
export PATH="$OMARCHY_PATH/bin:$PATH"
export XDG_CURRENT_DESKTOP=Hyprland LIBGL_ALWAYS_SOFTWARE=1 QT_QPA_PLATFORM=wayland
export QS_DISABLE_FILE_WATCHER=1 QS_NO_RELOAD_POPUP=1
export EVIDENCE="$SMOKE_ROOT/smoke-evidence"
mkdir -p "$XDG_RUNTIME_DIR" "$HOME/.config/hypr" "$HOME/.config/omarchy/current" "$HOME/.local/state"
chmod 700 "$XDG_RUNTIME_DIR"
exec > >(tee "$EVIDENCE/session.log") 2>&1
phase=bootstrap
collect() {
  local code=$?
  trap - EXIT
  jq -n --arg phase "$phase" --argjson exitCode "$code" --arg source "$SOURCE_SHA" \
    --arg omarchy "$OMARCHY_SHA" '{source:$source,omarchy:$omarchy,phase:$phase,exitCode:$exitCode}' > "$EVIDENCE/result.json"
  if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
    timeout 5 hyprctl -j clients > "$EVIDENCE/final-clients.json" 2>&1 || true
    timeout 5 hyprctl -j layers > "$EVIDENCE/final-layers.json" 2>&1 || true
    timeout 5 hyprctl configerrors > "$EVIDENCE/config-errors.txt" 2>&1 || true
    timeout 10 grim "$EVIDENCE/final.png" || true
  fi
  jobs -pr | xargs -r kill 2>/dev/null || true
  exit "$code"
}
trap collect EXIT
wait_for() {
  local deadline=$((SECONDS + 60))
  until "$@"; do
    (( SECONDS < deadline )) || { echo "Timed out in $phase: $*"; return 1; }
    sleep 0.3
  done
}
# The VM supplies a real virtio DRM device; there is no parent compositor.
cat > "$HOME/.config/hypr/looknfeel.lua" <<'LUA'
-- Owned by the disposable test account; Familiar may add its normal hook here.
LUA
cat > "$HOME/.config/hypr/hyprland.lua" <<'LUA'
hl.monitor({ output = "", mode = "1280x800@60", position = "auto", scale = 1 })
hl.config({ general = { layout = "dwindle" }, animations = { enabled = false } })
dofile(os.getenv("HOME") .. "/.config/hypr/looknfeel.lua")
LUA
if [[ ${NATIVE_TITLEBARS:-0} == 1 ]]; then
  cat > "$HOME/.config/hypr/hyprland.lua" <<'LUA'
dofile(os.getenv("OMARCHY_PATH") .. "/default/hypr/bootstrap.lua")
hl.monitor({ output = "", mode = "1280x800@60", position = "auto", scale = 1 })
hl.config({ general = { layout = "dwindle" }, animations = { enabled = false } })
require("hypr.looknfeel")
require("default.hypr.workspace-layouts")
LUA
fi
phase=hyprland
AQ_BACKENDS=drm HYPRLAND_ALLOW_SOFTWARE=1 \
  Hyprland --config "$HOME/.config/hypr/hyprland.lua" > "$EVIDENCE/hyprland.log" 2>&1 &
hypr_pid=$!
discover() {
  kill -0 "$hypr_pid" 2>/dev/null || { cat "$EVIDENCE/hyprland.log"; exit 1; }
  local socket
  socket=$(find "$XDG_RUNTIME_DIR/hypr" -name .socket.sock -print -quit 2>/dev/null) || return 1
  [[ -n $socket ]] || return 1
  export HYPRLAND_INSTANCE_SIGNATURE=$(basename "$(dirname "$socket")")
  local display
  for display in "$XDG_RUNTIME_DIR"/wayland-*; do
    [[ -S $display ]] || continue
    export WAYLAND_DISPLAY=${display##*/}
    timeout 3 hyprctl -j monitors | jq -e 'length > 0' >/dev/null && return 0
  done
  return 1
}
wait_for discover
hyprctl version | tee "$EVIDENCE/hyprland-version.txt"
hyprctl -j monitors > "$EVIDENCE/monitors.json"
if [[ ${NATIVE_TITLEBARS:-0} == 1 ]]; then
  source "$SMOKE_ROOT/tests/desktop/native-titlebars.sh"
  phase=passed
  exit 0
fi
# Disable unrelated first-party services; run the real shell and its real bar.
node "$SMOKE_ROOT/tests/desktop/configure.cjs" "$OMARCHY_PATH" "$HOME"
ln -s "$OMARCHY_PATH/themes/tokyo-night" "$HOME/.config/omarchy/current/theme"
phase=omarchy-shell
omarchy-launch-shell > "$EVIDENCE/shell-launcher.log" 2>&1 &
shell_ready() { [[ $(timeout 3 omarchy-shell shell ping 2>/dev/null) == ok ]]; }
wait_for shell_ready
phase=stable-fixture
plugin_id=io.github.tcballard.familiar-desktop
plugin="$HOME/.config/omarchy/plugins/$plugin_id"
baseline=9b948cd4d80e002eff88698d752f08268934b93c
git init "$plugin"
git -C "$plugin" fetch --depth 1 https://github.com/tcballard/omarchy-plugin-familiar-desktop.git "$baseline"
git -C "$plugin" checkout --detach "$baseline"
[[ $(git -C "$plugin" rev-parse HEAD) == "$baseline" ]]
# Bootstrap the signed-off stable fixture with production download/setup helpers.
# This is not a claim to have driven the graphical first-install wizard.
bash "$plugin/install-backend.sh"
library=$(bash "$plugin/install-titlebars.sh")
helper="$plugin/bin/familiar-desktop"
"$helper" titlebars setup --library "$library" --enable --style mac
omarchy-shell shell rescanPlugins
familiar_ready() { [[ $(timeout 3 omarchy-shell "$plugin_id" ping 2>/dev/null) == ok ]]; }
# Qt 6.12 cannot render the old release's bare Color references. Its binary/
# ownership fixture is used for installation, without claiming old UI acceptance.
if [[ $EXPECTED_QT == 6.11.2 ]]; then
  wait_for omarchy plugin enable "$plugin_id"
  wait_for familiar_ready
fi
phase=install-candidate
bundle="$SMOKE_ROOT/desktop-bundle"
(cd "$bundle" && sha256sum --check --strict SHA256SUMS)
jq -e --arg sha "$SOURCE_SHA" '.commit == $sha and .channel == "development"' "$bundle/DEV-BUILD.json"
cp "$bundle/DEV-BUILD.json" "$EVIDENCE/tested-build.json"
bash "$bundle/install-dev.sh"
[[ $(git -C "$plugin" rev-parse HEAD) == "$SOURCE_SHA" ]]
# Installation preserves placement. The Qt 6.12 fixture started disabled to
# avoid rendering the incompatible old UI, so enable the new candidate now.
if [[ $EXPECTED_QT == 6.12.0 ]]; then
  wait_for omarchy plugin enable "$plugin_id"
fi
wait_for familiar_ready
# Exercise the injected widget catalogue and a real shared-shell FloatingWindow.
# This is a disposable icon/identity fixture, not RSS networking acceptance.
phase=plugin-panel-icon
rss_id=io.github.tcballard.rss-feed
rss_fixture="$HOME/.config/omarchy/plugins/$rss_id"
cp -R "$SMOKE_ROOT/tests/desktop/panel-fixture" "$rss_fixture"
omarchy-shell shell rescanPlugins
wait_for omarchy plugin enable "$rss_id"
omarchy-shell shell summon "$rss_id" '{}'
rss_icon_ready() {
  timeout 3 omarchy-shell "$plugin_id" panelStatus | jq -e --arg id "$rss_id" \
    'any(.[]; .id == $id and .pluginId == $id and .glyph == "\uf09e" and .windows == 1)' >/dev/null
}
wait_for rss_icon_ready
omarchy-shell "$plugin_id" panelStatus > "$EVIDENCE/plugin-panel-icons.json"
rss_window=$(hyprctl -j clients | jq -er '.[] | select(.title == "RSS Feed") | .address')
"$helper" dock activate-instance "$rss_window"
rss_active() { omarchy-shell "$plugin_id" panelStatus | jq -e --arg id "$rss_id" 'any(.[]; .id == $id and .active == true)' >/dev/null; }
wait_for rss_active
omarchy-shell shell hide "$rss_id"
rss_closed() { omarchy-shell "$plugin_id" panelStatus | jq -e --arg id "$rss_id" 'all(.[]; .id != $id)' >/dev/null; }
wait_for rss_closed
omarchy plugin disable "$rss_id"
rm -rf "$rss_fixture"
omarchy-shell shell rescanPlugins
phase=palette
palette="$XDG_RUNTIME_DIR/palette-probe"
mkdir -p "$palette"
ln -s "$OMARCHY_PATH/shell/Commons" "$palette/Commons"
cp "$SMOKE_ROOT/tests/desktop/palette-probe.qml" "$palette/shell.qml"
timeout 15 qs -p "$palette/shell.qml" > "$EVIDENCE/palette-probe.log" 2>&1
grep -q 'PASS: qualified Commons palette' "$EVIDENCE/palette-probe.log"
phase=windows
foot --app-id familiar-smoke-a --title 'Familiar fixture A' sleep 600 > "$EVIDENCE/foot-a.log" 2>&1 &
foot --app-id familiar-smoke-b --title 'Familiar fixture B' sleep 600 > "$EVIDENCE/foot-b.log" 2>&1 &
two_windows() { timeout 3 hyprctl -j clients | jq -e '[.[] | select(.class | startswith("familiar-smoke-"))] | length == 2' >/dev/null; }
wait_for two_windows
a=$(hyprctl -j clients | jq -er '.[] | select(.class == "familiar-smoke-a") | .address')
b=$(hyprctl -j clients | jq -er '.[] | select(.class == "familiar-smoke-b") | .address')
"$helper" dock activate-instance "$a"
active_a() { timeout 3 hyprctl -j activewindow | jq -e --arg a "$a" '.address == $a' >/dev/null; }
wait_for active_a
phase=native-input
"$helper" gestures desktop | tee "$EVIDENCE/gestures-enable.json"
"$helper" input-preference command enable | tee "$EVIDENCE/shortcuts-enable.json"
hyprctl configerrors > "$EVIDENCE/native-input-config-errors.txt"
[[ -z "$(cat "$EVIDENCE/native-input-config-errors.txt")" ]]
hyprctl eval "dofile('$SMOKE_ROOT/tests/desktop/native-input-probe.lua')" | tee "$EVIDENCE/native-input-probe.txt"
grep -qx 'ok' "$EVIDENCE/native-input-probe.txt"
sleep 0.2
cp "$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/hyprland.log" "$EVIDENCE/native-input-hyprland.log"
! grep -Eq 'Runtime error in lua|dispatcher objects cannot be called' "$EVIDENCE/native-input-hyprland.log"
"$helper" input-preference command reset
"$helper" gestures reset
phase=windows
"$helper" dock minimize-instance "$a"
minimized_a() { timeout 3 hyprctl -j clients | jq -e --arg a "$a" 'any(.[]; .address == $a and .workspace.name == "special:minimized")' >/dev/null; }
wait_for minimized_a
hyprctl -j monitors | jq -e 'all(.[]; (.specialWorkspace.name // "") != "special:minimized")'
hyprctl -j clients | jq -e --arg b "$b" 'any(.[]; .address == $b and (.workspace.name | startswith("special:") | not))'
"$helper" dock activate-instance "$a"
wait_for active_a
hyprctl -j clients | jq -e --arg a "$a" 'any(.[]; .address == $a and (.workspace.name | startswith("special:") | not))'
phase=shell-restart
omarchy-shell "$plugin_id" setVisibilityMode hybrid
setting_saved() { jq -e '.visibilityMode == "hybrid"' "$HOME/.config/omarchy/familiar-desktop-settings.json" >/dev/null; }
wait_for setting_saved
# Seed a custom dock appearance before restart; a subsequent production write
# must preserve the value loaded by the new shell.
settings="$HOME/.config/omarchy/familiar-desktop-settings.json"
jq '.dockBackgroundOpacity = "50"' "$settings" > "$settings.tmp"
mv "$settings.tmp" "$settings"
cp "$settings" "$EVIDENCE/settings-before.json"
quickshell list -a -j > "$EVIDENCE/shell-before.json"
omarchy restart shell
wait_for familiar_ready
quickshell list -a -j > "$EVIDENCE/shell-after.json"
node "$SMOKE_ROOT/tests/desktop/assert-restart.cjs" "$EVIDENCE" "$OMARCHY_PATH/shell"
wait_for setting_saved
omarchy-shell "$plugin_id" setVisibilityMode always
opacity_saved() { jq -e '.visibilityMode == "always" and .dockBackgroundOpacity == "50"' "$settings" >/dev/null; }
wait_for opacity_saved
cp "$settings" "$EVIDENCE/settings-after.json"
wait_for two_windows
"$helper" dock minimize-instance "$a"
wait_for minimized_a
"$helper" dock activate-instance "$a"
wait_for active_a
timeout 10 grim "$EVIDENCE/candidate.png"
hyprctl -j layers > "$EVIDENCE/candidate-layers.json"
jq -e '[.. | objects | select(.namespace? == "familiar-desktop-dock")] | length > 0' "$EVIDENCE/candidate-layers.json"
phase=windows-taskbar
# Reproduce a combined service/widget already enabled outside bar.layout.
# enablePlugin on the XPS shell reports success without placing this entry.
shell_config="$HOME/.config/omarchy/shell.json"
jq --arg id "$plugin_id" '
  .bar.layout |= with_entries(.value |= map(select((if type == "object" then .id else . end) != $id))) |
  .plugins = ((.plugins // [] | map(select((if type == "object" then .id else . end) != $id))) + [{id:$id}])
' "$shell_config" > "$shell_config.tmp"
mv "$shell_config.tmp" "$shell_config"
omarchy-shell shell reloadConfig
omarchy plugin enable "$plugin_id" --section right --index 0
# Both tested shells must retain a service-only fixture before activation.
jq --arg id "$plugin_id" '.bar.layout |= with_entries(.value |= map(select((if type == "object" then .id else . end) != $id)))' \
  "$shell_config" > "$shell_config.tmp"
mv "$shell_config.tmp" "$shell_config"
omarchy-shell shell reloadConfig
cp "$HOME/.config/omarchy/shell.json" "$EVIDENCE/bar-before-taskbar.json"
cat "$HOME/.config/omarchy/shell.toml" > "$EVIDENCE/style-before-taskbar.toml" 2>/dev/null || :
omarchy-shell "$plugin_id" setProfile windows
taskbar_ready() { omarchy-shell "$plugin_id" taskbarStatus | jq -e '.active == true and .busy == false and .profile == "windows"' >/dev/null; }
wait_for taskbar_ready
bar_has_apps() { omarchy-shell shell debugBarGeometry | jq -e --arg id "$plugin_id" 'any(.[]; .id == $id and .visible == true and .width > 100 and .height >= 48)' >/dev/null; }
wait_for bar_has_apps
phase=windows-settings-button
probe="$EVIDENCE/input-probe"
mkdir -p "$probe"
wayland-scanner client-header "$SMOKE_ROOT/tests/desktop/wlr-virtual-pointer-unstable-v1.xml" "$probe/pointer.h"
wayland-scanner private-code "$SMOKE_ROOT/tests/desktop/wlr-virtual-pointer-unstable-v1.xml" "$probe/pointer-protocol.c"
cc -D_DEFAULT_SOURCE -I "$probe" -o "$probe/pointer" "$SMOKE_ROOT/tests/desktop/pointer.c" "$probe/pointer-protocol.c" -lwayland-client
settings_x=$(omarchy-shell shell debugBarGeometry | jq -r --arg id "$plugin_id" '.[] | select(.id == $id and .visible == true) | .x + 40')
bar_y=$(hyprctl -j layers | jq -r '[.. | objects | select(.namespace? == "omarchy-bar") | .y][0]')
"$probe/pointer" 640 500 1280 800 0
"$probe/pointer" "$settings_x" "$((bar_y + 24))" 1280 800 272
settings_open() { hyprctl -j layers | jq -e 'any(.. | objects; .namespace? == "familiar-desktop-settings")' >/dev/null; }
wait_for settings_open
# The backdrop intentionally does not dismiss this modal on every shell;
# close through the shell's supported bar-widget action after the real click.
omarchy-shell shell hide "$plugin_id"
settings_closed() { hyprctl -j layers | jq -e 'all(.. | objects; .namespace? != "familiar-desktop-settings")' >/dev/null; }
wait_for settings_closed
hyprctl -j layers > "$EVIDENCE/taskbar-layers.json"
jq -e '[.. | objects | select(.namespace? == "familiar-desktop-dock")] | length == 0' "$EVIDENCE/taskbar-layers.json"
omarchy-shell shell debugBarGeometry > "$EVIDENCE/taskbar-geometry.json"
timeout 10 grim "$EVIDENCE/taskbar.png"
omarchy restart shell
wait_for familiar_ready
wait_for taskbar_ready
wait_for bar_has_apps
omarchy-shell "$plugin_id" setProfile general
taskbar_restored() { omarchy-shell "$plugin_id" taskbarStatus | jq -e '.active == false and .busy == false and .profile == "general"' >/dev/null; }
wait_for taskbar_restored
jq -S '.bar' "$HOME/.config/omarchy/shell.json" > "$EVIDENCE/bar-after-taskbar.json"
jq -S '.bar' "$EVIDENCE/bar-before-taskbar.json" > "$EVIDENCE/bar-original.json"
cmp "$EVIDENCE/bar-original.json" "$EVIDENCE/bar-after-taskbar.json"
cmp "$EVIDENCE/style-before-taskbar.toml" "$HOME/.config/omarchy/shell.toml"
# Mac must restore the same service-only arrangement too.
omarchy-shell "$plugin_id" setProfile windows
wait_for taskbar_ready
omarchy-shell "$plugin_id" setProfile mac
mac_restored() { omarchy-shell "$plugin_id" taskbarStatus | jq -e '.active == false and .busy == false and .profile == "mac"' >/dev/null; }
wait_for mac_restored
jq -S '.bar' "$shell_config" > "$EVIDENCE/bar-after-mac.json"
cmp "$EVIDENCE/bar-original.json" "$EVIDENCE/bar-after-mac.json"
cmp "$EVIDENCE/style-before-taskbar.toml" "$HOME/.config/omarchy/shell.toml"
# Exercise the installed input-region component with a real Wayland pointer.
# The old item-based mask stayed at y=58 after its card animated to y=2,
# leaving the visible centre unclickable even though the dock layer existed.
phase=mac-dock-pointer
cp "$plugin/components/DockInputRegion.qml" "$probe/DockInputRegion.qml"
cp "$SMOKE_ROOT/tests/desktop/dock-input-probe.qml" "$probe/shell.qml"
"$probe/pointer" 100 400 1280 800 0
qs -p "$probe/shell.qml" > "$probe/qs.log" 2>&1 &
probe_pid=$!
probe_ready() { hyprctl -j layers | jq -e 'any(.. | objects; .namespace? == "familiar-input-probe")' >/dev/null; }
wait_for probe_ready
sleep 1
"$probe/pointer" 640 664 1280 800 272
pointer_ready() { grep -Fq 'FAMILIAR_INPUT_HOVER' "$probe/qs.log" && grep -Fq 'FAMILIAR_INPUT_CLICK' "$probe/qs.log"; }
wait_for pointer_ready
kill "$probe_pid"
wait "$probe_pid" || true
# Roll back while the taskbar is active: the bundle must undo its native placement.
omarchy-shell "$plugin_id" setProfile windows
wait_for taskbar_ready
phase=rollback
if [[ $EXPECTED_QT == 6.11.2 ]]; then
  bash "$bundle/install-dev.sh" --rollback
  [[ $(git -C "$plugin" rev-parse HEAD) == "$baseline" ]]
  [[ ! -e "$HOME/.local/state/familiar-desktop/dev-build.json" ]]
  [[ ! -e "$HOME/.local/state/familiar-desktop/taskbar/placement.json" ]]
  jq -S '.bar' "$HOME/.config/omarchy/shell.json" > "$EVIDENCE/bar-after-rollback.json"
  cmp "$EVIDENCE/bar-original.json" "$EVIDENCE/bar-after-rollback.json"
  cmp "$EVIDENCE/style-before-taskbar.toml" "$HOME/.config/omarchy/shell.toml"
else
  echo 'Qt 6.12: old-release UI/rollback compatibility is outside this candidate check.'
fi
wait_for familiar_ready
wait_for two_windows
phase=passed
echo 'PASS: real shell, source-matched installation, native palette/input, two windows, focus, minimise/restore, shell restart and dock layer.'
