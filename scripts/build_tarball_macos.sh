#!/usr/bin/env bash
# build_tarball_macos.sh — build a self-contained macOS (arm64) release tarball.
#
# Output: releases/krypton-<version>-macos-arm64.tar.gz
# Extract + run ./install.sh to put `kcc` on PATH. Prebuilt binaries, no clone,
# no rebuild, no clang. Version is read from the driver. This same tarball is the
# artifact the Homebrew formula points at — one file for `brew install` AND
# direct download. Mirrors scripts/build_tarball_linux.sh (agent L).
set -euo pipefail
cd "$(dirname "$0")/.."

[[ "$(uname -s)" == "Darwin" ]] || { echo "build_tarball_macos: macOS only"; exit 1; }
ARCH=arm64
DRIVER="bootstrap/kcc_driver_macos_aarch64"
HOST="bootstrap/macho_host_macos_aarch64"
[[ -x "$DRIVER" ]] || { echo "build_tarball_macos: missing $DRIVER (run ./build.sh)"; exit 1; }
[[ -x "$HOST" ]]   || { echo "build_tarball_macos: missing $HOST"; exit 1; }
[[ -x "compiler/macos_arm64/kcc-arm64" ]] || { echo "build_tarball_macos: missing compiler/macos_arm64/kcc-arm64"; exit 1; }

VERSION=$(KRYPTON_ROOT="$PWD" "./$DRIVER" --version 2>&1 | sed -E 's/^kcc version //;s/[[:space:]].*$//')
[[ -n "$VERSION" ]] || { echo "build_tarball_macos: could not detect version"; exit 1; }

NAME="krypton-${VERSION}-macos-${ARCH}"
STAGE=$(mktemp -d); ROOT="$STAGE/$NAME"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$ROOT"

echo "staging payload for $NAME ..."
# (BSD/macOS `install` has no GNU `-D`, so mkdir dirs first.)
mkdir -p "$ROOT/bootstrap" "$ROOT/compiler/macos_arm64"
# Driver (the `kcc` command) + frontend seed
install -m 0755 "$DRIVER"                          "$ROOT/$DRIVER"
install -m 0755 bootstrap/kcc_seed_macos_aarch64   "$ROOT/bootstrap/kcc_seed_macos_aarch64"
# Frontend + backend host + their sources (driver resolves root via kcc-arm64;
# ensureHost runs compiler/macos_arm64/macho_host)
install -m 0755 compiler/macos_arm64/kcc-arm64          "$ROOT/compiler/macos_arm64/kcc-arm64"
install -m 0755 "$HOST"                                 "$ROOT/compiler/macos_arm64/macho_host"
install -m 0644 compiler/macos_arm64/macho_arm64_self.k "$ROOT/compiler/macos_arm64/macho_arm64_self.k"
install -m 0644 compiler/compile.k                      "$ROOT/compiler/compile.k"
[[ -f compiler/optimize.k ]] && install -m 0644 compiler/optimize.k "$ROOT/compiler/optimize.k"
[[ -x compiler/macos_arm64/kls ]] && install -m 0755 compiler/macos_arm64/kls "$ROOT/compiler/macos_arm64/kls"
# Runtime trees the FE/programs need
cp -R stdlib  "$ROOT/stdlib"      # REQUIRED for `import "k:..."`
cp -R headers "$ROOT/headers"
[[ -d examples ]] && cp -R examples "$ROOT/examples"
[[ -f LICENSE ]] && cp LICENSE "$ROOT/LICENSE"
find "$ROOT" -type f -name '*.k' -exec chmod 0644 {} \;

# Self-contained installer. Symlink-only (binaries prebuilt) + two macOS steps:
# clear Gatekeeper quarantine and ad-hoc sign so the arm64 Mach-O run under AMFI.
cat > "$ROOT/install.sh" <<'INST'
#!/usr/bin/env bash
# Krypton macOS installer — copies the bundle, signs it, puts kcc on PATH.
set -euo pipefail
PREFIX="${1:-/usr/local/krypton}"
BIN="${BINDIR:-/usr/local/bin}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUDO=""; [[ -w "$(dirname "$PREFIX")" && -w "$(dirname "$BIN")" ]] || SUDO="sudo"
echo "installing Krypton to $PREFIX ..."
$SUDO rm -rf "$PREFIX"; $SUDO mkdir -p "$PREFIX"; $SUDO cp -R "$HERE"/. "$PREFIX"/
# Clear download quarantine + ad-hoc sign so AMFI lets the binaries run.
$SUDO xattr -dr com.apple.quarantine "$PREFIX" 2>/dev/null || true
for b in bootstrap/kcc_driver_macos_aarch64 compiler/macos_arm64/kcc-arm64 \
         compiler/macos_arm64/macho_host compiler/macos_arm64/kls; do
    [[ -e "$PREFIX/$b" ]] && $SUDO codesign -s - -f "$PREFIX/$b" 2>/dev/null || true
done
# Stamp binaries newer than the .k sources so ensureHost() skips the clang rebuild.
$SUDO touch "$PREFIX/bootstrap/kcc_driver_macos_aarch64" \
            "$PREFIX/compiler/macos_arm64/kcc-arm64" \
            "$PREFIX/compiler/macos_arm64/macho_host" 2>/dev/null || true
$SUDO mkdir -p "$BIN"
$SUDO ln -sf "$PREFIX/bootstrap/kcc_driver_macos_aarch64" "$BIN/kcc"
[[ -e "$PREFIX/compiler/macos_arm64/kls" ]] && $SUDO ln -sf "$PREFIX/compiler/macos_arm64/kls" "$BIN/kls"
echo "done. 'kcc --version':"; "$BIN/kcc" --version
INST
chmod 0755 "$ROOT/install.sh"

cat > "$ROOT/README.txt" <<RME
Krypton ${VERSION} — macOS ${ARCH}
Install:  ./install.sh            (symlinks kcc into /usr/local/bin, ad-hoc signs)
Use:      kcc hello.k -o hello && ./hello
          kcc -r hello.ks
          kcc --version
No clang, no clone needed — prebuilt binaries, self-signed on install.
RME

# Make binaries NEWER than the .k sources so the driver never triggers the
# (clang) macho_host self-host rebuild on first run after extract.
find "$ROOT" -type f \( -name macho_host -o -name "kcc-*" -o -name "kcc_*" \) -exec touch {} +
sleep 1; find "$ROOT" -type f \( -name macho_host -o -name "kcc-*" -o -name "kcc_*" \) -exec touch {} +

mkdir -p releases
OUT="releases/${NAME}.tar.gz"
tar -czf "$OUT" -C "$STAGE" "$NAME"
echo "wrote $OUT ($(du -h "$OUT" | cut -f1))"
shasum -a 256 "$OUT"
