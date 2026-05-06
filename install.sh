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
link "$SCRIPT_DIR/kcc"    "$BIN_DIR/kcc"       # dispatcher → platform binary
link "$SCRIPT_DIR/kcc.sh" "$BIN_DIR/kcc.sh"    # full driver with --native, etc.
[[ -f "$SCRIPT_DIR/kls" ]] && link "$SCRIPT_DIR/kls" "$BIN_DIR/kls"  # LSP server (if built)

echo ""
echo "installed:"
echo "  $BIN_DIR/kcc     -> $SCRIPT_DIR/kcc       (compiler dispatcher)"
echo "  $BIN_DIR/kcc.sh  -> $SCRIPT_DIR/kcc.sh    (driver: kcc.sh hello.k -o hello)"
[[ -f "$SCRIPT_DIR/kls" ]] && echo "  $BIN_DIR/kls     -> $SCRIPT_DIR/kls       (LSP server)"
echo ""
echo "verify: kcc --version"
