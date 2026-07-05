#!/usr/bin/env bash
# build_pkg.sh — build a macOS .pkg installer for Krypton (arm64).
#
# Output: releases/krypton-<version>-macos-arm64.pkg
#
# Install layout once the .pkg is run:
#   /usr/local/krypton/                payload (driver, compiler, backend, stdlib,
#                                      headers, examples, LSP)
#   /usr/local/bin/{kcc,kls,kweb}      symlinks → /usr/local/krypton/...
#   /Applications/Krypton/kweb_gui.app native kweb deploy GUI
#
# `kcc` is the Krypton-native driver (kcc.ks compiled → kcc_driver_macos_aarch64).
# kcc.sh was removed (0c0dc57b); the C-source seed (kcc_seed.c) was removed too —
# everything is Krypton-built now. Uses Apple's pkgbuild (Xcode CLT, no extra
# deps). Run on a Mac after `./build.sh` has produced the platform binaries.

set -euo pipefail
export COPYFILE_DISABLE=1

cd "$(dirname "$0")/.."

# ── Pre-flight checks ──────────────────────────────────────────────────────
[[ "$(uname -s)" == "Darwin" ]] || { echo "build_pkg.sh: macOS only"; exit 1; }
[[ "$(uname -m)" == "arm64" ]]  || { echo "build_pkg.sh: arm64 only (this script bundles the arm64 binaries)"; exit 1; }
command -v pkgbuild >/dev/null || { echo "build_pkg.sh: pkgbuild not found (install Xcode Command Line Tools)"; exit 1; }

DRIVER="bootstrap/kcc_driver_macos_aarch64"
HOST="bootstrap/macho_host_macos_aarch64"
[[ -x "compiler/macos_arm64/kcc-arm64" ]] || { echo "build_pkg.sh: missing compiler/macos_arm64/kcc-arm64 — run ./build.sh first"; exit 1; }
[[ -x "$DRIVER" ]] || { echo "build_pkg.sh: missing $DRIVER (the kcc.ks driver seed) — run ./build.sh first"; exit 1; }
[[ -x "$HOST" ]]   || { echo "build_pkg.sh: missing $HOST (the macho backend host seed)"; exit 1; }
KLS_BIN=""
[[ -x "compiler/macos_arm64/kls" ]] && KLS_BIN="compiler/macos_arm64/kls"
[[ -z "$KLS_BIN" && -x "kls" ]]     && KLS_BIN="kls"
[[ -x "web/kweb" ]] || { echo "build_pkg.sh: missing web/kweb — build it first"; exit 1; }
[[ -d "dist/kweb_gui.app" ]] || { echo "build_pkg.sh: missing dist/kweb_gui.app — build it first"; exit 1; }

# ── Version ────────────────────────────────────────────────────────────────
VERSION=$(KRYPTON_ROOT="$PWD" "./$DRIVER" --version 2>&1 | sed -E 's/^kcc version //;s/[[:space:]]+.*$//')
[[ -n "$VERSION" ]] || { echo "build_pkg.sh: could not detect kcc version"; exit 1; }

PKG_ID="org.krypton-lang.krypton"
PKG_FILE="releases/krypton-${VERSION}-macos-arm64.pkg"

# ── Stage payload ──────────────────────────────────────────────────────────
STAGE=$(mktemp -d)
SCRIPTS_DIR=$(mktemp -d)
trap 'rm -rf "$STAGE" "$SCRIPTS_DIR"' EXIT

PREFIX="/usr/local/krypton"
ROOT="$STAGE$PREFIX"
mkdir -p "$ROOT"

echo "staging payload for $VERSION ..."

# Driver (the `kcc` command) + frontend seed.
# (BSD/macOS `install` has no GNU `-D`, so mkdir the dir first.)
mkdir -p "$ROOT/bootstrap"
install -m 0755 "$DRIVER"                          "$ROOT/$DRIVER"
install -m 0755 bootstrap/kcc_seed_macos_aarch64   "$ROOT/bootstrap/kcc_seed_macos_aarch64"

# Frontend + backend host + their sources (driver resolves root via
# compiler/macos_arm64/kcc-arm64; ensureHost runs compiler/macos_arm64/macho_host).
mkdir -p "$ROOT/compiler/macos_arm64"
install -m 0755 compiler/macos_arm64/kcc-arm64          "$ROOT/compiler/macos_arm64/kcc-arm64"
install -m 0755 "$HOST"                                 "$ROOT/compiler/macos_arm64/macho_host"
install -m 0644 compiler/macos_arm64/macho_arm64_self.k "$ROOT/compiler/macos_arm64/macho_arm64_self.k"
install -m 0644 compiler/compile.k                      "$ROOT/compiler/compile.k"
[[ -f compiler/optimize.k ]] && install -m 0644 compiler/optimize.k "$ROOT/compiler/optimize.k"
[[ -n "$KLS_BIN" ]] && install -m 0755 "$KLS_BIN"       "$ROOT/compiler/macos_arm64/kls"

# Standard library — REQUIRED for `import "k:..."` (the FE resolves k: modules
# from <root>/stdlib). Was missing before — imports failed from a .pkg install.
ditto --norsrc stdlib "$ROOT/stdlib"

# Header files (--headers flag + kls) and examples.
ditto --norsrc headers "$ROOT/headers"
[[ -d examples ]] && ditto --norsrc examples "$ROOT/examples"

# LSP sources (so users can rebuild kls if they edit it).
if [[ -d lsp ]]; then
    mkdir -p "$ROOT/lsp"
    for f in lsp/*.k lsp/README.md; do
        [[ -f "$f" ]] && install -m 0644 "$f" "$ROOT/$f"
    done
fi

[[ -f LICENSE ]] && install -m 0644 LICENSE "$ROOT/LICENSE"
find "$ROOT" -type f -name '*.k' -exec chmod 0644 {} \;

# kweb CLI + native GUI.
mkdir -p "$ROOT/web"
install -m 0755 web/kweb "$ROOT/web/kweb"
install -m 0644 web/kweb.htk "$ROOT/web/kweb.htk"
install -m 0644 web/kweb_gui.ks "$ROOT/web/kweb_gui.ks"
[[ -f web/README.md ]] && install -m 0644 web/README.md "$ROOT/web/README.md"
mkdir -p "$STAGE/Applications/Krypton"
ditto --norsrc dist/kweb_gui.app "$STAGE/Applications/Krypton/kweb_gui.app"

# ── Post-install script ────────────────────────────────────────────────────
# Runs as root via Installer.app: symlink kcc/kls onto PATH, ad-hoc sign the
# binaries (AMFI on Apple Silicon refuses unsigned Mach-O), and stamp the
# binaries newer than their .k sources so the driver never tries to clang-
# rebuild macho_host on first run (it would fail on a clang-less machine).
cat > "$SCRIPTS_DIR/postinstall" <<'EOF'
#!/bin/bash
set -e
ROOT=/usr/local/krypton

mkdir -p /usr/local/bin
ln -sf "$ROOT/bootstrap/kcc_driver_macos_aarch64" /usr/local/bin/kcc
[[ -e "$ROOT/compiler/macos_arm64/kls" ]] && ln -sf "$ROOT/compiler/macos_arm64/kls" /usr/local/bin/kls
[[ -e "$ROOT/web/kweb" ]] && ln -sf "$ROOT/web/kweb" /usr/local/bin/kweb

# Ad-hoc sign the executables so they run under AMFI.
for b in "$ROOT/bootstrap/kcc_driver_macos_aarch64" \
         "$ROOT/compiler/macos_arm64/kcc-arm64" \
         "$ROOT/compiler/macos_arm64/macho_host" \
         "$ROOT/compiler/macos_arm64/kls" \
         "$ROOT/web/kweb" \
         "/Applications/Krypton/kweb_gui.app/Contents/MacOS/kweb_gui"; do
    [[ -e "$b" ]] && codesign -s - -f "$b" 2>/dev/null || true
done

# Make binaries newer than the .k sources -> ensureHost() sees macho_host as
# up-to-date and skips the one-time clang rebuild.
touch "$ROOT/bootstrap/kcc_driver_macos_aarch64" \
      "$ROOT/compiler/macos_arm64/kcc-arm64" \
      "$ROOT/compiler/macos_arm64/macho_host" 2>/dev/null || true
exit 0
EOF
chmod 0755 "$SCRIPTS_DIR/postinstall"

# ── Strip xattrs so pkgbuild doesn't bake AppleDouble (._*) files ─────────
xattr -cr "$STAGE" 2>/dev/null || true
find "$STAGE" -name '._*' -delete 2>/dev/null || true

# ── Build the .pkg ─────────────────────────────────────────────────────────
mkdir -p releases
rm -f "$PKG_FILE"

echo "building $PKG_FILE..."
pkgbuild \
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
echo "verify:     kcc --version   # -> kcc version $VERSION"
echo "            kweb"
echo "            open /Applications/Krypton/kweb_gui.app"
echo "uninstall:  sudo rm -rf /usr/local/krypton /Applications/Krypton /usr/local/bin/{kcc,kls,kweb}"
