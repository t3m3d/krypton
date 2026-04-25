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

if [[ -w "$BIN_DIR" ]]; then
    ln -sf "$SCRIPT_DIR/kcc" "$BIN_DIR/kcc"
else
    sudo ln -sf "$SCRIPT_DIR/kcc" "$BIN_DIR/kcc"
fi

echo ""
echo "kcc installed: $BIN_DIR/kcc -> $SCRIPT_DIR/kcc"
echo "verify: kcc --version"
