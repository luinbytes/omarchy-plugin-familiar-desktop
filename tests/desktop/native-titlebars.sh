#!/usr/bin/env bash
# Sourced only by the disposable VM session; uses the exact source-bound bundle.
[[ ${FAMILIAR_DISPOSABLE_SMOKE:-} == 1 && $HOME == /home/familiar-smoke ]] || return 2
phase=native-source
plugin="$HOME/.config/omarchy/plugins/io.github.tcballard.familiar-desktop"
bundle="$SMOKE_ROOT/desktop-bundle"
(cd "$bundle" && sha256sum --check --strict SHA256SUMS)
jq -e --arg sha "$SOURCE_SHA" '.commit == $sha and .channel == "development"' "$bundle/DEV-BUILD.json"
cp "$bundle/DEV-BUILD.json" "$EVIDENCE/tested-build.json"
git init "$plugin"
git -C "$plugin" fetch --depth 1 https://github.com/tcballard/omarchy-plugin-familiar-desktop.git "$SOURCE_SHA"
git -C "$plugin" checkout --detach FETCH_HEAD
[[ $(git -C "$plugin" rev-parse HEAD) == "$SOURCE_SHA" ]]
install -Dm755 "$bundle/familiar-desktop-linux-x86_64" "$plugin/bin/familiar-desktop"
helper="$plugin/bin/familiar-desktop"
phase=native-migration
"$helper" titlebars migrate | tee "$EVIDENCE/migrate.json" | jq -e '.state == "ready"'
"$helper" titlebars apply --mode mac --owner 200-native | jq -e '.state == "configured"'
# Initially tiled: Familiar must not force Core to load the renderer.
hyprctl -j plugin list | jq -e 'length == 0'
mkdir -p "$HOME/.local/state/omarchy/workspace-layouts"
echo 'o.workspace_mode({ default = "floating" })' > "$HOME/.local/state/omarchy/workspace-layouts/default.lua"
hyprctl reload
native_ready() { hyprctl eval "assert(familiar_titlebars and familiar_titlebars.state == 'active')" | grep -Fxq ok; }
wait_for native_ready
hyprctl -j plugin list | tee "$EVIDENCE/native-plugins.json" | jq -e 'length == 1 and .[0].name == "hyprbars"'
foot --app-id=familiar-native-a --title='Familiar titlebar A' sleep 500 > "$EVIDENCE/foot-a.log" 2>&1 &
foot --app-id=familiar-native-b --title='Familiar titlebar B' sleep 500 > "$EVIDENCE/foot-b.log" 2>&1 &
two_windows() { hyprctl -j clients | jq -e 'length == 2' >/dev/null; }
wait_for two_windows
a=$(hyprctl -j clients | jq -r '.[] | select(.class == "familiar-native-a") | .address')
b=$(hyprctl -j clients | jq -r '.[] | select(.class == "familiar-native-b") | .address')
probe="$EVIDENCE/input-probe"
mkdir -p "$probe"
wayland-scanner client-header "$SMOKE_ROOT/tests/desktop/wlr-virtual-pointer-unstable-v1.xml" "$probe/pointer.h"
wayland-scanner private-code "$SMOKE_ROOT/tests/desktop/wlr-virtual-pointer-unstable-v1.xml" "$probe/pointer-protocol.c"
cc -D_DEFAULT_SOURCE -I "$probe" -o "$probe/pointer" "$SMOKE_ROOT/tests/desktop/pointer.c" "$probe/pointer-protocol.c" -lwayland-client
place_windows() {
  hyprctl dispatch "hl.dsp.window.resize({ x = 450, y = 320, window = 'address:$a' })"
  hyprctl dispatch "hl.dsp.window.move({ x = 60, y = 320, window = 'address:$a' })"
  hyprctl dispatch "hl.dsp.window.resize({ x = 450, y = 320, window = 'address:$b' })"
  hyprctl dispatch "hl.dsp.window.move({ x = 690, y = 320, window = 'address:$b' })"
}
minimized_a() { hyprctl -j clients | jq -e --arg a "$a" 'any(.[]; .address == $a and .workspace.name == "special:minimized")' >/dev/null; }
restored_a() { hyprctl -j clients | jq -e --arg a "$a" 'any(.[]; .address == $a and .workspace.name == "1")' >/dev/null; }
maximized_a() { hyprctl -j clients | jq -e --arg a "$a" 'any(.[]; .address == $a and .fullscreen == 1)' >/dev/null; }
normal_a() { hyprctl -j clients | jq -e --arg a "$a" 'any(.[]; .address == $a and .fullscreen == 0)' >/dev/null; }
phase=native-mac
place_windows
# For left alignment: first button x=padding+radius; second +size+gap.
# The bar is above the content origin. Mac defaults: 34px high, 18px buttons.
"$probe/pointer" 106 303 1280 800 272
wait_for minimized_a
hyprctl -j clients | jq -e --arg b "$b" 'any(.[]; .address == $b and .workspace.name == "1")'
"$helper" dock activate-instance "$a"
wait_for restored_a
place_windows
"$probe/pointer" 133 303 1280 800 272
wait_for maximized_a
"$helper" titlebars action maximize --window "$a"
wait_for normal_a
place_windows
grim "$EVIDENCE/native-mac.png"
phase=native-windows
"$helper" titlebars apply --mode windows --size large --owner 200-native --background '#fafafa' --foreground '#121212' | jq -e '.state == "configured"'
wait_for native_ready
place_windows
# Right alignment reverses drawing order: close right, maximize, minimize.
# Content right=510, padding10, radius13, spacing35.
"$probe/pointer" 417 298 1280 800 272
wait_for minimized_a
"$helper" dock activate-instance "$a"
wait_for restored_a
place_windows
"$probe/pointer" 452 298 1280 800 272
wait_for maximized_a
"$helper" titlebars action maximize --window "$a"
wait_for normal_a
place_windows
grim "$EVIDENCE/native-windows.png"
phase=native-targeted-actions
# Focus the other window before the helper executes; explicit target must win.
hyprctl dispatch "hl.dsp.focus({ window = 'address:$b' })"
"$helper" titlebars action minimize --window "$a"
wait_for minimized_a
"$helper" dock activate-instance "$a"
wait_for restored_a
# Actual close button through the stock renderer's %WINDOW% substitution.
place_windows
"$probe/pointer" 487 298 1280 800 272
only_b() { hyprctl -j clients | jq -e --arg b "$b" 'length == 1 and .[0].address == $b' >/dev/null; }
wait_for only_b
phase=native-disable-reload
"$helper" titlebars disable --owner 100-stale --if-owner
wait_for native_ready
"$helper" titlebars disable --owner 200-native --if-owner | jq -e '.state == "managed"'
hyprctl eval "assert(familiar_titlebars == nil and hl.get_config('plugin.hyprbars.bar_height') == 30)"
# Repeated reloads must not duplicate buttons or introduce another backend.
for style in mac windows mac; do
  "$helper" titlebars apply --mode "$style" --owner 200-native
  hyprctl reload
  wait_for native_ready
  hyprctl -j plugin list | jq -e 'length == 1'
done
phase=native-remove
"$helper" titlebars remove | jq -e '.state == "removed"'
hyprctl eval "assert(familiar_titlebars == nil and hl.get_config('plugin.hyprbars.bar_height') == 30)"
test -f /usr/lib/omarchy-hyprland-titlebars/titlebars.so
# Returning to tiling unloads this config-loaded renderer. A manually loaded
# renderer has a different lifetime, exercised separately below.
echo 'o.workspace_mode({ default = "dwindle" })' > "$HOME/.local/state/omarchy/workspace-layouts/default.lua"
hyprctl reload
unloaded() { hyprctl -j plugin list | jq -e 'length == 0' >/dev/null; }
wait_for unloaded

phase=native-retained-renderer
# Establish the maximized client geometry with no renderer at all. These are
# disposable test windows, not the user's desktop or personal configuration.
hyprctl dispatch "hl.dsp.window.float({ action = 'enable', window = 'address:$b' })"
hyprctl dispatch "hl.dsp.window.fullscreen({ mode = 'maximized', action = 'set', window = 'address:$b' })"
maximized_b() { hyprctl -j clients | jq -e --arg b "$b" 'any(.[]; .address == $b and .floating and .fullscreen == 1)' >/dev/null; }
wait_for maximized_b
hyprctl -j clients | jq -e --arg b "$b" '.[] | select(.address == $b) | {at, size}' > "$EVIDENCE/native-no-renderer-geometry.json"

# CLI-loaded plugins survive when config stops asking for them. Load before
# Core requests it so the test cannot pass just because Core unloaded the .so.
"$helper" titlebars migrate | tee "$EVIDENCE/native-retained-migrate.json" | jq -e '.state == "ready"'
"$helper" titlebars apply --mode mac --owner 300-retained | jq -e '.state == "configured"'
hyprctl plugin load /usr/lib/omarchy-hyprland-titlebars/titlebars.so
renderer_loaded() { hyprctl -j plugin list | jq -e 'length == 1 and .[0].name == "hyprbars"' >/dev/null; }
wait_for renderer_loaded
echo 'o.workspace_mode({ default = "floating" })' > "$HOME/.local/state/omarchy/workspace-layouts/default.lua"
hyprctl reload
wait_for native_ready
hyprctl -j plugin list > "$EVIDENCE/native-retained-plugins.json"
bar_space_reserved() {
  hyprctl -j clients | jq -e --arg b "$b" --slurpfile baseline "$EVIDENCE/native-no-renderer-geometry.json" \
    'any(.[]; .address == $b and .fullscreen == 1 and .at[1] > $baseline[0].at[1] and .size[1] < $baseline[0].size[1])' >/dev/null
}
wait_for bar_space_reserved

phase=native-unconfigured-renderer
config="$HOME/.config/hypr/hyprland.lua"
cp "$config" "$EVIDENCE/native-configured.lua"
# Omit both configuration consumers; leave the loaded library alone. No
# explicit enabled=false: 0.2.1's safe default is the behaviour under test.
sed -e '/^require("hypr.looknfeel")$/d' -e '/^require("default.hypr.workspace-layouts")$/d' \
  "$EVIDENCE/native-configured.lua" > "$config"
hyprctl reload
renderer_unconfigured() {
  hyprctl eval "assert(hl.get_config('plugin.hyprbars.enabled') == false and hl.get_config('plugin.hyprbars.workspace_tag') == '')" | grep -Fxq ok
}
wait_for renderer_unconfigured
hyprctl -j plugin list | tee "$EVIDENCE/native-unconfigured-plugins.json" | jq -e 'length == 1 and .[0].name == "hyprbars"'
cmp "$EVIDENCE/native-retained-plugins.json" "$EVIDENCE/native-unconfigured-plugins.json"
no_bar_space() {
  hyprctl -j clients | jq -e --arg b "$b" --slurpfile baseline "$EVIDENCE/native-no-renderer-geometry.json" \
    'any(.[]; .address == $b and .fullscreen == 1 and {at, size} == $baseline[0])' >/dev/null
}
wait_for no_bar_space
hyprctl -j clients > "$EVIDENCE/native-unconfigured-clients.json"
grim "$EVIDENCE/native-unconfigured.png"

phase=native-reenable-retained-renderer
cp "$EVIDENCE/native-configured.lua" "$config"
hyprctl reload
wait_for native_ready
wait_for bar_space_reserved
hyprctl eval "assert(hl.get_config('plugin.hyprbars.enabled') == true and hl.get_config('plugin.hyprbars.bar_height') == 34)" | grep -Fxq ok
hyprctl dispatch "hl.dsp.window.fullscreen({ mode = 'maximized', action = 'unset', window = 'address:$b' })"
hyprctl dispatch "hl.dsp.window.resize({ x = 450, y = 320, window = 'address:$b' })"
hyprctl dispatch "hl.dsp.window.move({ x = 60, y = 320, window = 'address:$b' })"
# Real pointer input proves the restored Familiar control is functional.
"$probe/pointer" 106 303 1280 800 272
minimized_b() { hyprctl -j clients | jq -e --arg b "$b" 'any(.[]; .address == $b and .workspace.name == "special:minimized")' >/dev/null; }
wait_for minimized_b
"$helper" dock activate-instance "$b"
restored_b() { hyprctl -j clients | jq -e --arg b "$b" 'any(.[]; .address == $b and .workspace.name == "1")' >/dev/null; }
wait_for restored_b
grim "$EVIDENCE/native-reenabled.png"
"$helper" titlebars remove | jq -e '.state == "removed"'
echo 'o.workspace_mode({ default = "dwindle" })' > "$HOME/.local/state/omarchy/workspace-layouts/default.lua"
hyprctl reload
wait_for renderer_unconfigured
wait_for renderer_loaded
# Only the disposable test owns this manual load and its matching cleanup.
hyprctl plugin unload /usr/lib/omarchy-hyprland-titlebars/titlebars.so
wait_for unloaded
echo 'PASS: retained renderer defaults off without configuration, reserves no titlebar space, and restores working Familiar controls when re-enabled.'
hyprctl -j configerrors | jq -e 'all(.[]; . == "")'
# Exercise the production installer on an enabled, unfinished v0.1.5 checkout.
# The renderer checks above intentionally run without the shell's controller;
# these lifecycle checks now use the real shell and retain Core's native library.
phase=native-initial-shell
baseline=439f97480bb0803f32137dcb700fbb939dc959ff
plugin_id=io.github.tcballard.familiar-desktop
state="$HOME/.local/state/familiar-desktop"
rm -f "$helper"
# remove deliberately retains Core's delegation receipt. Archive that earlier
# test state to make this a genuinely fresh fixture, not a prior migrated owner.
jq -e '.backend == "omarchy"' "$HOME/.config/omarchy/familiar-titlebars/owner.json"
mv "$HOME/.config/omarchy/familiar-titlebars" "$EVIDENCE/renderer-phase-titlebars"
git -C "$plugin" fetch --depth 1 https://github.com/tcballard/omarchy-plugin-familiar-desktop.git "$baseline"
git -C "$plugin" checkout --detach "$baseline"
node "$SMOKE_ROOT/tests/desktop/configure.cjs" "$OMARCHY_PATH" "$HOME"
ln -s "$OMARCHY_PATH/themes/tokyo-night" "$HOME/.config/omarchy/current/theme"
omarchy-launch-shell > "$EVIDENCE/shell-launcher.log" 2>&1 &
shell_ready() { [[ $(timeout 3 omarchy-shell shell ping 2>/dev/null) == ok ]]; }
familiar_ready() { [[ $(timeout 3 omarchy-shell "$plugin_id" ping 2>/dev/null) == ok ]]; }
wait_for shell_ready
omarchy-shell shell rescanPlugins
wait_for omarchy plugin enable "$plugin_id"
wait_for familiar_ready
cp "$HOME/.config/omarchy/shell.json" "$EVIDENCE/native-before-initial-shell.json"
phase=native-initial-staging
bash "$bundle/install-dev.sh" --initial
[[ $(git -C "$plugin" rev-parse HEAD) == "$SOURCE_SHA" ]]
[[ -f "$state/setup-pending" && ! -e "$plugin/bin/hyprbars" ]]
diff -u <(jq -S . "$EVIDENCE/native-before-initial-shell.json") <(jq -S . "$HOME/.config/omarchy/shell.json")
wait_for familiar_ready
if bash "$plugin/setup-in-app.sh" status; then echo 'Initial setup must remain pending'; exit 1; fi
# Use the real setup entry point; this does not claim a graphical wizard click.
bash "$plugin/setup-in-app.sh" install mac
bash "$plugin/setup-in-app.sh" status
[[ ! -e "$plugin/bin/hyprbars" ]]
phase=native-initial-rollback
omarchy plugin disable "$plugin_id"
omarchy restart shell
# Core disables third-party widgets by removing their placement. disabledPlugins
# is primarily for implicit first-party services; inspect Core's public state.
familiar_disabled() {
  omarchy-shell shell listPlugins | jq -e --arg id "$plugin_id" 'any(.[]; .id == $id and .enabled == false)' >/dev/null
}
wait_for familiar_disabled
cp "$HOME/.config/omarchy/shell.json" "$EVIDENCE/native-disabled-shell.json"
"$helper" titlebars migrate | jq -e '.state == "ready"'
echo 'o.workspace_mode({ default = "floating" })' > "$HOME/.local/state/omarchy/workspace-layouts/default.lua"
hyprctl reload
"$helper" titlebars apply --mode mac --owner 300-rollback | jq -e '.state == "configured"'
wait_for native_ready
bash "$bundle/install-dev.sh" --rollback
[[ $(git -C "$plugin" rev-parse HEAD) == "$baseline" ]]
[[ ! -e "$helper" && ! -e "$state/dev-build.json" && ! -e "$plugin/bin/hyprbars" ]]
jq -e '.backend == "omarchy"' "$HOME/.config/omarchy/familiar-titlebars/owner.json"
diff -u <(jq -S . "$EVIDENCE/native-disabled-shell.json") <(jq -S . "$HOME/.config/omarchy/shell.json")
wait_for familiar_disabled
hyprctl eval "assert(familiar_titlebars == nil and hl.get_config('plugin.hyprbars.bar_height') == 30)" | grep -Fxq ok
test -f /usr/lib/omarchy-hyprland-titlebars/titlebars.so
hyprctl -j configerrors | jq -e 'all(.[]; . == "")'
# A preserved, hook-free Core delegation must allow another explicit initial
# staging attempt, including recovery from that still-unfinished installation.
bash "$bundle/install-dev.sh" --initial
[[ -f "$state/setup-pending" ]]
bash "$bundle/install-dev.sh" --rollback
[[ $(git -C "$plugin" rev-parse HEAD) == "$baseline" && ! -e "$helper" ]]
diff -u <(jq -S . "$EVIDENCE/native-disabled-shell.json") <(jq -S . "$HOME/.config/omarchy/shell.json")
wait_for familiar_disabled
echo 'PASS: official renderer, Core floating scope, Mac/Windows pointer controls, targeted actions, restore, reload, disable/removal, initial staging/setup and disabled-state rollback.'
