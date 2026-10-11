#!/usr/bin/env bash
# GitHub-hosted VM only. No mounts/shares or personal keys enter the guest.
set -Eeuo pipefail
[[ ${GITHUB_ACTIONS:-} == true ]] || { echo 'Run this through the CI workflow.' >&2; exit 2; }
: "${SOURCE_SHA:?}" "${OMARCHY_SHA:?}" "${RUNNER_TEMP:?}"
: "${ARCH_SNAPSHOT:?}" "${EXPECTED_QT:?}" "${EXPECTED_QUICKSHELL:?}"
root=$(pwd)
evidence="$root/smoke-evidence"
mkdir -p "$evidence"
vm_dir=$(mktemp -d "$RUNNER_TEMP/familiar-vm.XXXXXXXX")
qemu_pid=''
ssh_ready=0
ssh_args=(-i "$vm_dir/client" -p 2222 -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$vm_dir/known_hosts" familiar-smoke@127.0.0.1)
remote() { timeout 900 ssh -o ServerAliveInterval=10 -o ServerAliveCountMax=3 "${ssh_args[@]}" "$@"; }
finish() {
  local code=$?
  trap - EXIT
  if (( ssh_ready )); then
    remote_collect || true
  fi
  [[ -z $qemu_pid ]] || kill "$qemu_pid" 2>/dev/null || true
  if [[ ! -f "$evidence/result.json" ]]; then
    jq -n --arg source "$SOURCE_SHA" --arg omarchy "$OMARCHY_SHA" --argjson code "$code" \
      '{source:$source,omarchy:$omarchy,phase:"vm-or-provisioning",exitCode:$code}' > "$evidence/result.json"
  fi
  # Ephemeral private keys and guest disks must never become CI artifacts.
  rm -rf -- "$vm_dir"
  exit "$code"
}
remote_short() { timeout 30 ssh -o ServerAliveInterval=5 -o ServerAliveCountMax=2 "${ssh_args[@]}" "$@"; }
remote_collect() {
  remote_short 'sudo journalctl --no-pager -u familiar-desktop-smoke' > "$evidence/guest-journal.log" 2>&1 || true
  remote_short 'sudo journalctl --no-pager -t omarchy-shell' > "$evidence/shell-journal.log" 2>&1 || true
  remote_short 'sudo tar -C /opt/familiar-smoke/smoke-evidence -cf - .' | tar -C "$evidence" -xf -
}
trap finish EXIT
[[ -c /dev/kvm ]] || { echo 'KVM is unavailable on this runner.' >&2; exit 1; }
sudo setfacl -m "u:$(id -un):rw" /dev/kvm
image_url=https://geo.mirror.pkgbuild.com/images/v20261001.604814/Arch-Linux-x86_64-cloudimg.qcow2
curl --fail --location --retry 3 --max-time 180 "$image_url" -o "$vm_dir/base.qcow2"
printf '%s  %s\n' 360f0fa49db6813bdc8e35bed230a2dc2ae3567b7b5ab74719c0a706e4e34e87 "$vm_dir/base.qcow2" | sha256sum --check --strict
qemu-img create -f qcow2 -F qcow2 -b "$vm_dir/base.qcow2" "$vm_dir/guest.qcow2" 16G
ssh-keygen -q -t ed25519 -N '' -f "$vm_dir/client"
ssh-keygen -q -t ed25519 -N '' -f "$vm_dir/host"
printf '[127.0.0.1]:2222 %s\n' "$(cat "$vm_dir/host.pub")" > "$vm_dir/known_hosts"
{
  echo '#cloud-config'
  echo 'users:'
  echo '  - name: familiar-smoke'
  echo '    groups: [wheel, video]'
  echo '    sudo: ["ALL=(ALL) NOPASSWD:ALL"]'
  echo '    shell: /bin/bash'
  echo '    lock_passwd: true'
  echo '    ssh_authorized_keys:'
  printf '      - %s\n' "$(cat "$vm_dir/client.pub")"
  echo 'ssh_pwauth: false'
  echo 'disable_root: true'
  echo 'ssh_keys:'
  echo '  ed25519_private: |'
  sed 's/^/    /' "$vm_dir/host"
  printf '  ed25519_public: %s\n' "$(cat "$vm_dir/host.pub")"
} > "$vm_dir/user-data"
printf 'instance-id: familiar-smoke\nlocal-hostname: familiar-smoke\n' > "$vm_dir/meta-data"
cloud-localds "$vm_dir/seed.img" "$vm_dir/user-data" "$vm_dir/meta-data"
qemu-system-x86_64 -enable-kvm -cpu host -smp 4 -m 8192 \
  -drive "file=$vm_dir/guest.qcow2,if=virtio,format=qcow2" \
  -drive "file=$vm_dir/seed.img,if=virtio,format=raw,readonly=on" \
  -netdev user,id=net0,hostfwd=tcp:127.0.0.1:2222-:22 -device virtio-net-pci,netdev=net0 \
  -vga none -device virtio-gpu-pci -device virtio-keyboard-pci -device virtio-mouse-pci \
  -display none -serial "file:$evidence/serial.log" -monitor none \
  > "$evidence/qemu.log" 2>&1 &
qemu_pid=$!
deadline=$((SECONDS + 180))
until remote true 2>/dev/null; do
  kill -0 "$qemu_pid" || { cat "$evidence/qemu.log"; exit 1; }
  (( SECONDS < deadline )) || { echo 'Guest SSH boot timeout.' >&2; exit 1; }
  sleep 2
done
ssh_ready=1
remote 'sudo mkdir -p /opt/familiar-smoke'
tar --exclude=.git -cf - tests/desktop desktop-bundle upstream-omarchy | remote 'sudo tar -C /opt/familiar-smoke -xf -'
remote "sudo env NATIVE_TITLEBARS=${NATIVE_TITLEBARS:-0} SOURCE_SHA=$SOURCE_SHA OMARCHY_SHA=$OMARCHY_SHA ARCH_SNAPSHOT=$ARCH_SNAPSHOT EXPECTED_QT=$EXPECTED_QT EXPECTED_QUICKSHELL=$EXPECTED_QUICKSHELL bash /opt/familiar-smoke/tests/desktop/provision.sh" \
  2>&1 | tee "$evidence/provision.log"
remote 'sudo systemctl start --no-block familiar-desktop-smoke'
deadline=$((SECONDS + 600))
while true; do
  state=$(remote 'systemctl show familiar-desktop-smoke -p ActiveState --value')
  [[ $state == active || $state == activating || $state == deactivating ]] || break
  (( SECONDS < deadline )) || { echo 'Desktop smoke timed out.' >&2; exit 1; }
  sleep 5
done
remote_collect
jq -e '.exitCode == 0 and .phase == "passed"' "$evidence/result.json"
[[ $(remote 'systemctl show familiar-desktop-smoke -p ExecMainStatus --value') == 0 ]]
