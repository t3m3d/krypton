#!/usr/bin/env bash
# qemu_linux_parity.sh — local Linux x86_64 parity VM harness.
#
# Commands:
#   init [image-url]       Download cloud image, make overlay disk + seed ISO.
#   boot                  Start VM on localhost SSH port 2222.
#   wait                  Wait until SSH is ready.
#   sync                  Copy this checkout into the VM.
#   smoke                 Run Linux parity smoke inside the VM.
#   run                   boot + wait + sync + smoke.
#   ssh                   Open an SSH shell.
#   stop                  Ask VM to power off.
#
# Defaults are intentionally local-only. VM assets live under .qemu/ and are
# ignored by git. The default image is Ubuntu 24.04 LTS amd64 cloud image.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VM_DIR="${KRYPTON_QEMU_DIR:-$ROOT/.qemu/linux-x86_64}"
DEFAULT_IMAGE_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
IMAGE_URL="$DEFAULT_IMAGE_URL"
BASE_IMG="$VM_DIR/base.img"
DISK_IMG="$VM_DIR/disk.qcow2"
SEED_DIR="$VM_DIR/seed"
SEED_ISO="$VM_DIR/seed.iso"
SSH_KEY="$VM_DIR/id_ed25519"
SSH_PORT="${KRYPTON_QEMU_SSH_PORT:-2222}"
SSH_USER="${KRYPTON_QEMU_USER:-krypton}"
VM_MEM="${KRYPTON_QEMU_MEM:-4096}"
VM_CPUS="${KRYPTON_QEMU_CPUS:-4}"
PID_FILE="$VM_DIR/qemu.pid"
LOG_FILE="$VM_DIR/qemu.log"
REMOTE_DIR="${KRYPTON_QEMU_REMOTE_DIR:-/home/$SSH_USER/krypton}"

usage() {
  cat <<'USAGE'
qemu_linux_parity.sh — local Linux x86_64 parity VM harness.

Commands:
  init [image-url]       Download cloud image, make overlay disk + seed ISO.
  boot                   Start VM on localhost SSH port 2222.
  wait                   Wait until SSH is ready.
  sync                   Copy this checkout into the VM.
  smoke                  Run Linux parity smoke inside the VM.
  run                    boot + wait + sync + smoke.
  ssh                    Open an SSH shell.
  stop                   Ask VM to power off.
USAGE
}

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing tool: $1" >&2
    exit 1
  }
}

ssh_base() {
  ssh -i "$SSH_KEY" -p "$SSH_PORT" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile="$VM_DIR/known_hosts" \
    -o ConnectTimeout=5 \
    "$SSH_USER@127.0.0.1" "$@"
}

make_key() {
  if [[ ! -f "$SSH_KEY" ]]; then
    need ssh-keygen
    ssh-keygen -q -t ed25519 -N "" -f "$SSH_KEY"
  fi
}

make_seed_iso() {
  need hdiutil
  rm -rf "$SEED_DIR"
  mkdir -p "$SEED_DIR"
  cat > "$SEED_DIR/meta-data" <<META
instance-id: krypton-linux-x86-64
local-hostname: krypton-linux
META
  cat > "$SEED_DIR/user-data" <<USERDATA
#cloud-config
users:
  - name: $SSH_USER
    groups: sudo
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - $(cat "$SSH_KEY.pub")
ssh_pwauth: false
package_update: true
packages:
  - ca-certificates
  - rsync
  - git
  - curl
runcmd:
  - [ sh, -lc, "systemctl enable --now ssh || systemctl enable --now sshd || true" ]
USERDATA
  rm -f "$SEED_ISO"
  hdiutil makehybrid -quiet -iso -joliet -default-volume-name cidata \
    -o "$SEED_ISO" "$SEED_DIR"
}

init_vm() {
  need qemu-img
  need curl
  mkdir -p "$VM_DIR"
  make_key
  if [[ ! -f "$BASE_IMG" ]]; then
    echo "download $IMAGE_URL"
    curl -L --fail --progress-bar "$IMAGE_URL" -o "$BASE_IMG"
  fi
  if [[ ! -f "$DISK_IMG" ]]; then
    qemu-img create -f qcow2 -F qcow2 -b "$BASE_IMG" "$DISK_IMG" 40G >/dev/null
  fi
  make_seed_iso
  echo "ready: $VM_DIR"
}

boot_vm() {
  need qemu-system-x86_64
  [[ -f "$DISK_IMG" && -f "$SEED_ISO" ]] || init_vm "$IMAGE_URL"
  if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "already running: pid $(cat "$PID_FILE"), ssh port $SSH_PORT"
    return 0
  fi
  qemu-system-x86_64 \
    -name krypton-linux-x86_64 \
    -m "$VM_MEM" \
    -smp "$VM_CPUS" \
    -drive "file=$DISK_IMG,if=virtio,format=qcow2" \
    -drive "file=$SEED_ISO,media=cdrom,readonly=on" \
    -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:$SSH_PORT-:22" \
    -device virtio-net-pci,netdev=net0 \
    -display none \
    -serial "file:$LOG_FILE" \
    -daemonize \
    -pidfile "$PID_FILE"
  echo "booted: pid $(cat "$PID_FILE"), ssh port $SSH_PORT"
}

wait_vm() {
  local tries="${1:-90}"
  local i=0
  while (( i < tries )); do
    if ssh_base "echo ready" >/dev/null 2>&1; then
      echo "ssh ready"
      return 0
    fi
    sleep 2
    i=$((i + 1))
  done
  echo "ssh not ready; see $LOG_FILE" >&2
  exit 1
}

sync_repo() {
  need rsync
  wait_vm 5
  ssh_base "mkdir -p $(dirname "$REMOTE_DIR")"
  rsync -az --delete \
    -e "ssh -i $SSH_KEY -p $SSH_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=$VM_DIR/known_hosts" \
    --exclude .git \
    --exclude .qemu \
    --exclude releases \
    --exclude web/site/dist \
    "$ROOT/" "$SSH_USER@127.0.0.1:$REMOTE_DIR/"
  echo "synced: $REMOTE_DIR"
}

smoke_vm() {
  wait_vm 5
  ssh_base "set -euo pipefail
cd '$REMOTE_DIR'
uname -a
./build.sh
KRYPTON_ROOT=\"\$PWD\" ./bootstrap/kcc_driver_linux_x86_64 --version
KRYPTON_ROOT=\"\$PWD\" ./bootstrap/kcc_driver_linux_x86_64 examples/fibonacci.k -o /tmp/krypton_fib
/tmp/krypton_fib
KRYPTON_ROOT=\"\$PWD\" ./bootstrap/kcc_driver_linux_x86_64 web/kweb.htk -o /tmp/kweb_linux
/tmp/kweb_linux
./scripts/build_tarball_linux.sh
ls -lh releases/krypton-*-linux-x86_64.tar.gz
pkg=\$(ls releases/krypton-*-linux-x86_64.tar.gz | sort | tail -1)
rm -rf /tmp/krypton-release-test /tmp/krypton-install-test /tmp/krypton-bin-test
mkdir -p /tmp/krypton-release-test /tmp/krypton-bin-test
tar -xzf \"\$pkg\" -C /tmp/krypton-release-test
pkgdir=\$(find /tmp/krypton-release-test -mindepth 1 -maxdepth 1 -type d -name 'krypton-*' | head -1)
BINDIR=/tmp/krypton-bin-test \"\$pkgdir/install.sh\" /tmp/krypton-install-test
/tmp/krypton-bin-test/kcc --version
/tmp/krypton-bin-test/kweb
"
}

stop_vm() {
  if ssh_base "sudo poweroff" >/dev/null 2>&1; then
    echo "poweroff sent"
  elif [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    kill "$(cat "$PID_FILE")"
    echo "killed pid $(cat "$PID_FILE")"
  else
    echo "not running"
  fi
}

cmd="${1:-help}"
shift || true
case "$cmd" in
  init) IMAGE_URL="${1:-$IMAGE_URL}"; init_vm ;;
  boot) boot_vm ;;
  wait) wait_vm "${1:-90}" ;;
  sync) sync_repo ;;
  smoke) smoke_vm ;;
  run) boot_vm; wait_vm 90; sync_repo; smoke_vm ;;
  ssh) wait_vm 5; ssh_base ;;
  stop) stop_vm ;;
  help|-h|--help) usage ;;
  *) echo "unknown command: $cmd" >&2; usage; exit 1 ;;
esac
