#!/usr/bin/env bash
# Download only: never invoke hyprpm or build tools on the user's desktop.
set -Eeuo pipefail
main() {
  if [[ -e /usr/lib/omarchy-hyprland-titlebars/titlebars.so ]]; then
    echo "Omarchy's titlebar package is installed. Familiar will not download a competing backend. Official-package migration is pending (issue #74); keep your existing settings and use the dock independently." >&2
    return 1
  fi
  local release='v0.1.5'
  local root_dir architecture abi asset base expected actual destination
  root_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  [[ "$(uname -s)" == Linux ]] || { echo 'Window controls require Linux.' >&2; return 1; }
  architecture="$(uname -m)"
  case "$architecture" in x86_64|aarch64) ;; *) echo "Unsupported Linux architecture: $architecture." >&2; return 1;; esac
  abi="$(hyprctl version | sed -n 's/^Version ABI string: //p')"
  [[ "$abi" =~ ^[a-zA-Z0-9_.-]+$ ]] || { echo 'Could not determine the running Hyprland ABI.' >&2; return 1; }
  asset="hyprbars-linux-$architecture-$abi.so"
  [[ -f "$root_dir/release-binaries.sha256" && ! -L "$root_dir/release-binaries.sha256" ]] || { echo 'Missing reviewed binary digests.' >&2; return 1; }
  expected="$(awk -v name="$asset" '$2 == name {print $1}' "$root_dir/release-binaries.sha256")"
  [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || {
    printf 'No reviewed window controls for Linux %s, Hyprland ABI: %s\nThis release has no matching binary pin. No source build or configuration change was attempted.\n' "$architecture" "$abi" >&2
    return 1
  }
  if [[ "${1:-}" == --check ]]; then return 0; fi
  [[ $# == 0 ]] || { echo 'Usage: install-titlebars.sh [--check]' >&2; return 1; }
  base="https://github.com/tcballard/omarchy-plugin-familiar-desktop/releases/download/$release"
  destination="$root_dir/bin/hyprbars/$abi"
  mkdir -p "$destination"
  titlebars_staging="$(mktemp -d "$destination/.download.XXXXXX")"
  trap 'rm -rf -- "$titlebars_staging"' EXIT
  if ! curl --fail --show-error --silent --location --proto '=https' --proto-redir '=https' --retry 3 --connect-timeout 20 --max-time 180 "$base/$asset" -o "$titlebars_staging/hyprbars.so"; then
    printf 'Window-controls download failed: %s\nCheck that the release and this asset are published: https://github.com/tcballard/omarchy-plugin-familiar-desktop/releases/tag/%s\nIf they are missing, the release is incomplete; retry after a corrected release exists.\n' "$base/$asset" "$release" >&2
    return 1
  fi
  actual="$(sha256sum "$titlebars_staging/hyprbars.so")"
  [[ "${actual%% *}" == "$expected" ]] || { echo 'Hyprbars checksum mismatch; existing library kept.' >&2; return 1; }
  chmod 644 "$titlebars_staging/hyprbars.so"
  mv -f -- "$titlebars_staging/hyprbars.so" "$destination/hyprbars.so"
  printf '%s\n' "$destination/hyprbars.so"
}
main "$@"
