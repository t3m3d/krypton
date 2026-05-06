#!/usr/bin/env bash
# build_pkg.sh — build a macOS .pkg installer for Krypton (arm64).
#
# Output: releases/krypton-<version>-macos-arm64.pkg
#
# Install layout once the .pkg is run:
#   /usr/local/krypton/                payload (compiler, runtime, headers, LSP)
#   /usr/local/bin/{kcc,kcc.sh,kls}   symlinks → /usr/local/krypton/...
#
# Uses Apple's pkgbuild (ships with Xcode Command Line Tools — no extra deps).
# Run on a Mac after `./build.sh` has produced the platform binaries.

set -euo pipefail

cd "$(dirname "$0")/.."

# ── Pre-flight checks ──────────────────────────────────────────────────────
[[ "$(uname -s)" == "Darwin" ]] || { echo "build_pkg.sh: macOS only"; exit 1; }
[[ "$(uname -m)" == "arm64" ]]  || { echo "build_pkg.sh: arm64 only (this script bundles kcc-arm64)"; exit 1; }
command -v pkgbuild >/dev/null || { echo "build_pkg.sh: pkgbuild not found (install Xcode Command Line Tools)"; exit 1; }

[[ -x "kcc-arm64" ]] || { echo "build_pkg.sh: missing ./kcc-arm64 — run ./build.sh first"; exit 1; }
[[ -x "kcc" ]]       || { echo "build_pkg.sh: missing ./kcc dispatcher"; exit 1; }
[[ -x "kcc.sh" ]]    || { echo "build_pkg.sh: missing ./kcc.sh driver"; exit 1; }
[[ -x "kls" ]]       || { echo "build_pkg.sh: missing ./kls — build with: ./kcc --headers headers/ lsp/kls.k > /tmp/_kls.c && cc /tmp/_kls.c -o kls"; exit 1; }

# ── Version ────────────────────────────────────────────────────────────────
VERSION=$(./kcc --version 2>&1 | sed -E 's/^kcc version //;s/[[:space:]]+.*$//')
[[ -n "$VERSION" ]] || { echo "build_pkg.sh: could not detect kcc version"; exit 1; }

PKG_ID="org.krypton-lang.krypton"
PKG_FILE="releases/krypton-${VERSION}-macos-arm64.pkg"

# ── Stage payload ──────────────────────────────────────────────────────────
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE" "$SCRIPTS_DIR"' EXIT

PREFIX="/usr/local/krypton"
ROOT="$STAGE$PREFIX"
mkdir -p "$ROOT"

echo "staging payload..."
# Top-level binaries / wrappers
install -m 0755 kcc       "$ROOT/kcc"
install -m 0755 kcc-arm64 "$ROOT/kcc-arm64"
install -m 0755 kcc.sh    "$ROOT/kcc.sh"
install -m 0755 kls       "$ROOT/kls"

# Compiler sources (kcc.sh's --native and host rebuilds need these)
mkdir -p "$ROOT/compiler/macos_arm64"
install -m 0644 compiler/compile.k                              "$ROOT/compiler/compile.k"
install -m 0644 compiler/optimize.k                             "$ROOT/compiler/optimize.k"
install -m 0644 compiler/llvm.k                                 "$ROOT/compiler/llvm.k"
install -m 0644 compiler/run.k                                  "$ROOT/compiler/run.k"
install -m 0644 compiler/macos_arm64/macho_arm64_self.k         "$ROOT/compiler/macos_arm64/macho_arm64_self.k"
install -m 0644 compiler/macos_arm64/macho.k                    "$ROOT/compiler/macos_arm64/macho.k"

# Header files (used by --headers flag, and by kls)
mkdir -p "$ROOT/headers"
cp -R headers/ "$ROOT/headers/"
find "$ROOT/headers" -type f -exec chmod 0644 {} \;

# Bootstrap source + macOS arm64 seed (so users can rebuild from source if needed)
mkdir -p "$ROOT/bootstrap"
install -m 0644 bootstrap/kcc_seed.c                  "$ROOT/bootstrap/kcc_seed.c"
install -m 0644 bootstrap/kcc_seed_macos_aarch64      "$ROOT/bootstrap/kcc_seed_macos_aarch64"

# LSP sources (so users can rebuild kls from source if they edit it)
mkdir -p "$ROOT/lsp"
for f in lsp/*.k lsp/README.md; do
    [[ -f "$f" ]] || continue
    install -m 0644 "$f" "$ROOT/$f"
done

# Examples
if [[ -d examples ]]; then
    mkdir -p "$ROOT/examples"
    for f in examples/*.k; do
        [[ -f "$f" ]] || continue
        install -m 0644 "$f" "$ROOT/$f"
    done
fi

# ── Post-install script ────────────────────────────────────────────────────
# Adds Krypton to PATH two ways (both run as root by Installer.app):
#   1. /etc/paths.d/krypton  → /usr/local/krypton joins PATH for new shells
#      (this is macOS's standard mechanism — see `man path_helper`)
#   2. Symlinks in /usr/local/bin/  → instant availability if that dir is
#      already on the user's PATH (it is by default via /etc/paths)
SCRIPTS_DIR=$(mktemp -d)
cat > "$SCRIPTS_DIR/postinstall" <<'EOF'
#!/bin/bash
# Krypton post-install — runs as root via Installer.app.
set -e

# 1. /etc/paths.d entry — picked up by path_helper(1) on new shell launch.
mkdir -p /etc/paths.d
echo "/usr/local/krypton" > /etc/paths.d/krypton
chmod 0644 /etc/paths.d/krypton

# 2. Belt-and-suspenders: also symlink into /usr/local/bin so the commands
#    are available even if a future macOS release changes PATH defaults, or
#    if the user's shell was opened before the install completed.
mkdir -p /usr/local/bin
ln -sf /usr/local/krypton/kcc    /usr/local/bin/kcc
ln -sf /usr/local/krypton/kcc.sh /usr/local/bin/kcc.sh
ln -sf /usr/local/krypton/kls    /usr/local/bin/kls
exit 0
EOF
chmod 0755 "$SCRIPTS_DIR/postinstall"

# ── Strip xattrs so pkgbuild doesn't bake AppleDouble (._*) files ─────────
# Files in the repo may carry quarantine bits and other extended attributes
# from earlier downloads/cps. xattr -cr clears them recursively.
xattr -cr "$STAGE" 2>/dev/null || true

# ── Build the .pkg ─────────────────────────────────────────────────────────
mkdir -p releases
rm -f "$PKG_FILE"

echo "building $PKG_FILE..."
# COPYFILE_DISABLE=1 stops pkgbuild's internal cpio from encoding AppleDouble
# (._*) sidecars when packaging files that carry xattrs.
COPYFILE_DISABLE=1 pkgbuild \
    --root            "$STAGE" \
    --identifier      "$PKG_ID" \
    --version         "$VERSION" \
    --scripts         "$SCRIPTS_DIR" \
    --install-location / \
    "$PKG_FILE"

SIZE=$(stat -f%z "$PKG_FILE")
echo ""
echo "wrote $PKG_FILE ($SIZE bytes)"
echo ""
echo "install:    sudo installer -pkg $PKG_FILE -target /"
echo "or open in Finder:  open $PKG_FILE"
echo ""
echo "uninstall:  sudo rm -rf /usr/local/krypton /usr/local/bin/{kcc,kcc.sh,kls}"
