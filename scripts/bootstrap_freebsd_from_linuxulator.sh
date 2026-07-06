#!/usr/bin/env sh
# Build first FreeBSD x86_64 seeds from existing Linux x86_64 seeds.
# Requires FreeBSD/GhostBSD linuxulator able to run Linux ELF binaries.
set -eu

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

LINUX_FE="$ROOT/compiler/linux_x86/kcc-x64"
LINUX_SEED="$ROOT/bootstrap/kcc_seed_linux_x86_64"
LINUX_ELF_HOST="$ROOT/bootstrap/elf_host_linux_x86_64"

die() {
    echo "bootstrap_freebsd: $*" >&2
    exit 1
}

[ -f "$LINUX_SEED" ] || die "missing $LINUX_SEED"
[ -f "$LINUX_ELF_HOST" ] || die "missing $LINUX_ELF_HOST"

mkdir -p "$ROOT/compiler/linux_x86" "$ROOT/compiler/freebsd_x86" "$ROOT/bootstrap"

if [ ! -x "$LINUX_FE" ]; then
    cp "$LINUX_SEED" "$LINUX_FE"
    chmod +x "$LINUX_FE"
fi
chmod +x "$LINUX_ELF_HOST"

if ! KRYPTON_ROOT="$ROOT" "$LINUX_FE" --version >/dev/null 2>&1; then
    die "Linux seed did not run. Enable FreeBSD linuxulator, then rerun."
fi

TMPDIR="$(mktemp -d /tmp/krypton-freebsd-seed.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT INT TERM

FREEBSD_EMITTER_LINUX="$TMPDIR/freebsd_elf_host_linux"

echo "bootstrap_freebsd: emit FreeBSD backend IR"
KRYPTON_ROOT="$ROOT" "$LINUX_FE" --ir compiler/freebsd_x86/elf.k > "$TMPDIR/freebsd_elf.kir"

echo "bootstrap_freebsd: build Linux-hosted FreeBSD emitter"
"$LINUX_ELF_HOST" "$TMPDIR/freebsd_elf.kir" "$FREEBSD_EMITTER_LINUX" >/dev/null
chmod +x "$FREEBSD_EMITTER_LINUX"

echo "bootstrap_freebsd: build FreeBSD kcc seed"
KRYPTON_ROOT="$ROOT" "$LINUX_FE" --ir compiler/compile.k > "$TMPDIR/compile.kir"
"$FREEBSD_EMITTER_LINUX" "$TMPDIR/compile.kir" "$ROOT/bootstrap/kcc_seed_freebsd_x86_64" >/dev/null
chmod +x "$ROOT/bootstrap/kcc_seed_freebsd_x86_64"

echo "bootstrap_freebsd: build FreeBSD kcc driver"
KRYPTON_ROOT="$ROOT" "$LINUX_FE" --ir kcc.ks > "$TMPDIR/kcc_driver.kir"
"$FREEBSD_EMITTER_LINUX" "$TMPDIR/kcc_driver.kir" "$ROOT/bootstrap/kcc_driver_freebsd_x86_64" >/dev/null
chmod +x "$ROOT/bootstrap/kcc_driver_freebsd_x86_64"

echo "bootstrap_freebsd: build FreeBSD backend host"
"$FREEBSD_EMITTER_LINUX" "$TMPDIR/freebsd_elf.kir" "$ROOT/bootstrap/elf_host_freebsd_x86_64" >/dev/null
chmod +x "$ROOT/bootstrap/elf_host_freebsd_x86_64"

if [ -f "$ROOT/compiler/optimize.k" ]; then
    echo "bootstrap_freebsd: build FreeBSD optimizer host"
    KRYPTON_ROOT="$ROOT" "$LINUX_FE" --ir compiler/optimize.k > "$TMPDIR/optimize.kir"
    "$FREEBSD_EMITTER_LINUX" "$TMPDIR/optimize.kir" "$ROOT/bootstrap/optimize_host_freebsd_x86_64" >/dev/null
    chmod +x "$ROOT/bootstrap/optimize_host_freebsd_x86_64"
fi

cp "$ROOT/bootstrap/kcc_seed_freebsd_x86_64" "$ROOT/compiler/freebsd_x86/kcc-x64"
cp "$ROOT/bootstrap/elf_host_freebsd_x86_64" "$ROOT/compiler/freebsd_x86/elf_host"
chmod +x "$ROOT/compiler/freebsd_x86/kcc-x64" "$ROOT/compiler/freebsd_x86/elf_host"

if [ -f "$ROOT/bootstrap/optimize_host_freebsd_x86_64" ]; then
    cp "$ROOT/bootstrap/optimize_host_freebsd_x86_64" "$ROOT/compiler/freebsd_x86/optimize_host"
    chmod +x "$ROOT/compiler/freebsd_x86/optimize_host"
fi

echo "bootstrap_freebsd: seeds ready"
echo "bootstrap_freebsd: now run ./build.sh"
