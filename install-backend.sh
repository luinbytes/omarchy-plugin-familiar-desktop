#!/usr/bin/env bash
# Release binary installer. Development builds remain explicit in build.sh.
set -Eeuo pipefail
main() {
  local release='v0.1.5'
  local root_dir architecture asset base expected actual version
  root_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  [[ "$(uname -s)" == Linux ]] || { echo 'Familiar requires Linux.' >&2; return 1; }
  architecture="$(uname -m)"
  case "$architecture" in x86_64|aarch64) ;; *) echo "Unsupported Linux architecture: $architecture." >&2; return 1;; esac
  for tool in curl sha256sum; do
    command -v "$tool" >/dev/null || { echo "Missing $tool; install curl and coreutils." >&2; return 1; }
  done
  asset="familiar-desktop-linux-$architecture"
  base="https://github.com/tcballard/omarchy-plugin-familiar-desktop/releases/download/$release"
  mkdir -p "$root_dir/bin"
  backend_staging="$(mktemp -d "$root_dir/bin/.download.XXXXXX")"
  trap 'rm -rf -- "$backend_staging"' EXIT
  echo "Downloading Familiar $release backend (no Rust toolchain required)."
  [[ -f "$root_dir/release-binaries.sha256" && ! -L "$root_dir/release-binaries.sha256" ]] || { echo 'Missing reviewed binary digests.' >&2; return 1; }
  expected="$(awk -v name="$asset" '$2 == name {print $1}' "$root_dir/release-binaries.sha256")"
  [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || { echo 'Missing or ambiguous backend checksum in reviewed source.' >&2; return 1; }
  if ! curl --fail --show-error --silent --location --proto '=https' --proto-redir '=https' --retry 3 --connect-timeout 20 --max-time 180 "$base/$asset" -o "$backend_staging/$asset"; then
    printf 'Backend download failed: %s\nCheck that the release and this asset are published: https://github.com/tcballard/omarchy-plugin-familiar-desktop/releases/tag/%s\nIf they are missing, the release is incomplete; retry after a corrected release exists.\n' "$base/$asset" "$release" >&2
    return 1
  fi
  actual="$(sha256sum "$backend_staging/$asset")"
  [[ "${actual%% *}" == "$expected" ]] || { echo 'Backend checksum mismatch; existing backend kept.' >&2; return 1; }
  chmod 755 "$backend_staging/$asset"
  version="$("$backend_staging/$asset" --version)"
  [[ "$version" == "familiar-desktop ${release#v}" ]] || { echo "Wrong backend version: $version; existing backend kept." >&2; return 1; }
  mv -f -- "$backend_staging/$asset" "$root_dir/bin/familiar-desktop"
  echo "$version installed and SHA-256 verified."
}
main "$@"
