#!/usr/bin/env bash
# install.sh — build kcc and symlink into /usr/local/bin
# Usage: ./install.sh [PREFIX]
#   PREFIX defaults to /usr/local; binary lands at $PREFIX/bin/kcc

set -euo pipefail

PREFIX="${1:-/usr/local}"
BIN_DIR="$PREFIX/bin"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Build (build.sh does its own dep checks and smoke test)
./build.sh

# Symlink so future `./build.sh` runs are picked up automatically
if [[ ! -d "$BIN_DIR" ]]; then
    echo "creating $BIN_DIR (sudo)..."
    sudo mkdir -p "$BIN_DIR"
fi

link() {
    local src="$1" dst="$2"
    if [[ -w "$BIN_DIR" ]]; then
        ln -sf "$src" "$dst"
    else
        sudo ln -sf "$src" "$dst"
    fi
}
# The driver is the compiled kcc.ks (KryptScript) native binary, per platform.
# No C, no bash — kcc.sh was removed (commit 0c0dc57b).
case "$(uname -s 2>/dev/null)" in
    Linux*)  _OS=linux ;;
    Darwin*) _OS=macos ;;
    *)       _OS=windows ;;
esac
case "$(uname -m 2>/dev/null)" in
    x86_64|amd64)  _ARCH=x86_64 ;;
    aarch64|arm64) _ARCH=aarch64 ;;
    *)             _ARCH=$(uname -m) ;;
esac
KCC_DRIVER="$SCRIPT_DIR/bootstrap/kcc_driver_${_OS}_${_ARCH}"

if [[ -x "$KCC_DRIVER" ]]; then
    link "$KCC_DRIVER" "$BIN_DIR/kcc"          # kcc → compiled kcc.ks driver (no C, no bash)
    KCC_TARGET="$KCC_DRIVER"
else
    echo "install: no native kcc driver for ${_OS}_${_ARCH} (expected $KCC_DRIVER)." >&2
    if [[ "$_OS" == "linux" && "$_ARCH" == "aarch64" ]]; then
        echo "  Linux aarch64 is supported via cross-compile from an x86_64 host:" >&2
        echo "    on x86_64:  ./kcc --arm64 prog.k -o prog   # produces an aarch64 ELF" >&2
        echo "  A native aarch64-hosted driver seed is not yet shipped." >&2
    fi
    exit 1
fi
[[ -f "$SCRIPT_DIR/kls" ]] && link "$SCRIPT_DIR/kls" "$BIN_DIR/kls"  # LSP server (if built)

echo ""
echo "installed:"
echo "  $BIN_DIR/kcc     -> $KCC_TARGET"
[[ -f "$SCRIPT_DIR/kls" ]] && echo "  $BIN_DIR/kls     -> $SCRIPT_DIR/kls       (LSP server)"
echo ""
echo "verify: kcc --version"
