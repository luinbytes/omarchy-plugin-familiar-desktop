#!/usr/bin/env bash
# CI uses the pinned Arch snapshot. --local builds against the running desktop.
set -Eeuo pipefail
expected_abi='efb50993780079460b0cbed1363e2166a2de1d9f_aq_0.15_hu_0.14_hg_0.5_hc_0.1_hlg_0.6'
plugin_commit='7644cecdb947060682891a0db2a0cdc5c0b9e704'
root_dir="$(pwd)"
architecture="$(uname -m)"
case "$architecture" in x86_64) elf_machine='Advanced Micro Devices X86-64';; aarch64) elf_machine='AArch64';; *) echo "Unsupported architecture: $architecture" >&2; exit 1;; esac
local_build=false
if [[ "${1:-}" == --local && $# == 1 ]]; then
  local_build=true
  expected_abi="$(hyprctl version | sed -n 's/^Version ABI string: //p')"
  [[ "$expected_abi" =~ ^[a-zA-Z0-9_.-]+$ ]] || { echo 'Cannot read the running Hyprland ABI.' >&2; exit 1; }
elif [[ $# != 0 ]]; then
  echo 'Usage: build-hyprbars.sh [--local]' >&2; exit 2
fi
work_dir="$(mktemp -d)"
trap 'rm -rf -- "$work_dir"' EXIT
# This is the installed package, including generated headers, rather than a
# locally fabricated version.h or an override of Hyprland's compatibility check.
if [[ "$local_build" == false ]]; then test "$(pkg-config --modversion hyprland)" = 0.56.2; fi
# Preprocess the real plugin header, then compile only its ABI function. Including
# the whole header in an executable also instantiates compositor-only globals.
printf '#include <hyprland/src/plugins/PluginAPI.hpp>\n' > "$work_dir/header.cpp"
# shellcheck disable=SC2046
c++ -std=c++23 $(pkg-config --cflags hyprland) -dM -E "$work_dir/header.cpp" > "$work_dir/macros"
{
  echo '#include <format>'
  echo '#include <string>'
  echo '#include <string_view>'
  echo '#include <iostream>'
  grep -E '^#define (GIT_COMMIT_HASH|AQUAMARINE_VERSION|HYPRUTILS_VERSION|HYPRGRAPHICS_VERSION|HYPRCURSOR_VERSION|HYPRLANG_VERSION) ' "$work_dir/macros"
  sed -n '/^APICALL inline EXPORT const char\* __hyprland_api_get_client_hash()/,/^}/p' /usr/include/hyprland/src/plugins/PluginAPI.hpp | sed 's/APICALL inline EXPORT //'
  echo 'int main() { std::cout << __hyprland_api_get_client_hash(); }'
} > "$work_dir/abi.cpp"
c++ -std=c++23 "$work_dir/abi.cpp" -o "$work_dir/abi"
test "$("$work_dir/abi")" = "$expected_abi"
git init "$work_dir/plugins"
git -C "$work_dir/plugins" remote add origin https://github.com/hyprwm/hyprland-plugins.git
git -C "$work_dir/plugins" fetch --depth 1 origin "$plugin_commit"
git -C "$work_dir/plugins" checkout --detach FETCH_HEAD
test "$(git -C "$work_dir/plugins" rev-parse HEAD)" = "$plugin_commit"
git -C "$work_dir/plugins" apply --check "$root_dir/scripts/hyprbars/vector-controls.patch"
git -C "$work_dir/plugins" apply "$root_dir/scripts/hyprbars/vector-controls.patch"
cp "$root_dir/scripts/hyprbars/FamiliarIcons.hpp" "$work_dir/plugins/hyprbars/"
# GCC's spelling is -fno-gnu-unique (the upstream makefile uses a linker spelling).
make -C "$work_dir/plugins/hyprbars" EXTRA_FLAGS="-fno-gnu-unique $(pkg-config --cflags cairo)" LIBS="$(pkg-config --libs cairo)"
mkdir -p "$root_dir/hyprbars-assets"
asset="hyprbars-linux-$architecture-$expected_abi.so"
install -m644 "$work_dir/plugins/hyprbars/hyprbars.so" "$root_dir/hyprbars-assets/$asset"
readelf -h "$root_dir/hyprbars-assets/$asset" | tee "$root_dir/hyprbars-assets/HYPRBARS-ELF.txt"
grep -q "$elf_machine" "$root_dir/hyprbars-assets/HYPRBARS-ELF.txt"
cp "$work_dir/plugins/LICENSE" "$root_dir/hyprbars-assets/HYPRBARS-LICENSE.txt"
{
  printf 'Hyprbars upstream: https://github.com/hyprwm/hyprland-plugins/tree/%s\nABI: %s\nArchitecture: %s\n' "$plugin_commit" "$expected_abi" "$architecture"
  if [[ "$local_build" == true ]]; then echo 'Build environment: local installed packages (not the release snapshot)'; else echo 'Arch snapshot: 2026/09/30'; fi
  sha256sum "$root_dir/scripts/hyprbars/vector-controls.patch" "$root_dir/scripts/hyprbars/FamiliarIcons.hpp"
  c++ --version
  pacman -Q
} > "$root_dir/hyprbars-assets/HYPRBARS-BUILD.txt"
