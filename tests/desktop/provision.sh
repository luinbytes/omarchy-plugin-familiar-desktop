#!/usr/bin/env bash
set -Eeuo pipefail
[[ $(id -u) == 0 && $(uname -n) == familiar-smoke ]] || exit 2
: "${SOURCE_SHA:?}" "${OMARCHY_SHA:?}"
: "${ARCH_SNAPSHOT:?}" "${EXPECTED_QT:?}" "${EXPECTED_QUICKSHELL:?}"
root=/opt/familiar-smoke
mkdir -p "$root/smoke-evidence"
printf 'Server = https://archive.archlinux.org/repos/%s/$repo/os/$arch\n' "$ARCH_SNAPSHOT" > /etc/pacman.d/mirrorlist
retry() { local n; for n in 1 2 3; do "$@" && return; sleep 5; done; return 1; }
retry pacman -Syyuu --noconfirm
retry pacman -S --needed --noconfirm git jq nodejs dbus sudo socat curl inotify-tools hyprland quickshell \
  mesa foot grim gcc wayland qt6-declarative qt6-wayland qt6-multimedia qt6-svg qt6-imageformats ttf-dejavu
if [[ ${NATIVE_TITLEBARS:-0} == 1 ]]; then
  retry pacman -S --needed --noconfirm cmake pkgconf make glaze
  # Exact upstream archive from omarchy-pkgs #964, built against real headers.
  # No source modification or bypass of the compositor's ABI check.
  curl --fail --location --retry 3 --max-time 120 https://github.com/omacom/omarchy-hyprland-titlebars/archive/refs/tags/v0.2.1.tar.gz -o "$root/titlebars.tar.gz"
  echo '73320b611eb768a18d61f2ed7ace8f5a94f523a7cbcce132b1db246288efd5b8  '"$root/titlebars.tar.gz" | sha256sum --check --strict
  sha256sum "$root/titlebars.tar.gz" > "$root/smoke-evidence/official-titlebars-source.sha256"
  tar --no-same-owner -xzf "$root/titlebars.tar.gz" -C "$root"
  cmake -S "$root/omarchy-hyprland-titlebars-0.2.1" -B "$root/titlebar-build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr
  cmake --build "$root/titlebar-build" -j2
  cmake --install "$root/titlebar-build"
  sha256sum /usr/lib/omarchy-hyprland-titlebars/titlebars.so > "$root/smoke-evidence/official-titlebars.sha256"
fi
pacman -Q > "$root/smoke-evidence/packages.txt"
qt_version=$(pacman -Q qt6-base | cut -d ' ' -f 2)
qs_version=$(pacman -Q quickshell | cut -d ' ' -f 2)
[[ $qt_version == "$EXPECTED_QT"-* && $qs_version == "$EXPECTED_QUICKSHELL"-* ]] || {
  echo "Unexpected Qt/Quickshell runtime: $qt_version / $qs_version" >&2; exit 1;
}
jq -n --arg qt "$qt_version" --arg quickshell "$qs_version" --arg archive "$ARCH_SNAPSHOT" \
  '{qt:$qt,quickshell:$quickshell,archive:$archive}' > "$root/smoke-evidence/runtime.json"
uname -a > "$root/smoke-evidence/kernel.txt"
ls -l /dev/dri > "$root/smoke-evidence/virtual-gpu.txt"
# Match Omarchy’s installed path, including absolute QML imports in stable Familiar.
ln -s "$root/upstream-omarchy" /usr/share/omarchy
loginctl enable-linger familiar-smoke
chown familiar-smoke:familiar-smoke "$root/smoke-evidence"
systemctl stop getty@tty1.service
cat > /etc/systemd/system/familiar-desktop-smoke.service <<UNIT
[Unit]
After=systemd-user-sessions.service
[Service]
Type=oneshot
User=familiar-smoke
PAMName=login
TTYPath=/dev/tty1
StandardInput=tty-force
StandardOutput=journal
StandardError=journal
TTYReset=yes
TTYVHangup=yes
Environment=FAMILIAR_DISPOSABLE_SMOKE=1
Environment=NATIVE_TITLEBARS=${NATIVE_TITLEBARS:-0}
Environment=SOURCE_SHA=$SOURCE_SHA
Environment=OMARCHY_SHA=$OMARCHY_SHA
Environment=SMOKE_ROOT=$root
Environment=EXPECTED_QT=$EXPECTED_QT
ExecStart=/usr/bin/dbus-run-session -- /bin/bash $root/tests/desktop/session.sh
TimeoutStartSec=600
KillMode=control-group
UNIT
systemctl daemon-reload
