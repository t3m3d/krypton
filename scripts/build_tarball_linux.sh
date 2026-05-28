#!/usr/bin/env bash
# build_tarball_linux.sh — build a self-contained Linux release tarball.
#
# Output: releases/krypton-<version>-linux-<arch>.tar.gz
# Extract + run ./install.sh to put `kcc` on PATH. Prebuilt binaries, no
# clone, no rebuild, no C compiler. Version is read from `kcc --version`.
set -euo pipefail
cd "$(dirname "$0")/.."

ARCH=$(uname -m); [[ "$ARCH" == "amd64" ]] && ARCH=x86_64
DRIVER="bootstrap/kcc_driver_linux_${ARCH}"
[[ -x "$DRIVER" ]] || { echo "build_tarball_linux: missing $DRIVER (run build.sh)"; exit 1; }

VERSION=$(KRYPTON_ROOT="$PWD" "./$DRIVER" --version 2>&1 | sed -E 's/^kcc version //;s/[[:space:]].*$//')
[[ -n "$VERSION" ]] || { echo "build_tarball_linux: could not detect version"; exit 1; }

NAME="krypton-${VERSION}-linux-${ARCH}"
STAGE=$(mktemp -d); ROOT="$STAGE/$NAME"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$ROOT"

echo "staging payload for $NAME ..."
# Driver + FE/backend seeds (the runtime toolchain)
install -D -m0755 "$DRIVER"                          "$ROOT/$DRIVER"
install -D -m0755 "bootstrap/kcc_seed_linux_${ARCH}" "$ROOT/bootstrap/kcc_seed_linux_${ARCH}"
[[ -f bootstrap/elf_host_linux_${ARCH} ]] && install -D -m0755 "bootstrap/elf_host_linux_${ARCH}" "$ROOT/bootstrap/elf_host_linux_${ARCH}"
# x86 backend + FE (driver resolves root via compiler/linux_x86/kcc-x64)
install -D -m0755 compiler/linux_x86/kcc-x64   "$ROOT/compiler/linux_x86/kcc-x64"
install -D -m0755 compiler/linux_x86/elf_host  "$ROOT/compiler/linux_x86/elf_host"
install -D -m0644 compiler/linux_x86/elf.k     "$ROOT/compiler/linux_x86/elf.k"
# aarch64 cross emitter (so `kcc --arm64` works out of the box)
if [[ -d compiler/linux_arm64 ]]; then
  install -D -m0755 compiler/linux_arm64/elf_host "$ROOT/compiler/linux_arm64/elf_host"
  install -D -m0644 compiler/linux_arm64/elf.k    "$ROOT/compiler/linux_arm64/elf.k"
fi
# Compiler sources
install -D -m0644 compiler/compile.k  "$ROOT/compiler/compile.k"
[[ -f compiler/optimize.k ]] && install -D -m0644 compiler/optimize.k "$ROOT/compiler/optimize.k"
# kweb — Krypton Web Framework CLI. Build a native Linux ELF from web/kweb.htk
# with the just-staged toolchain (no C compiler). k:htmk/k:server/k:fs compile
# in; stdlib + headers are bundled below for any runtime import.
if [[ -f web/kweb.htk ]]; then
  echo "building kweb (web/kweb.htk -> native ELF) ..."
  mkdir -p "$ROOT/web"
  KWIR=$(mktemp /tmp/_kweb_XXXXXX.ir)
  if KRYPTON_ROOT="$PWD" compiler/linux_x86/kcc-x64 --ir web/kweb.htk > "$KWIR" 2>/dev/null \
     && [[ -s "$KWIR" ]] \
     && compiler/linux_x86/elf_host "$KWIR" "$ROOT/web/kweb" 2>/dev/null; then
    chmod 0755 "$ROOT/web/kweb"
    install -D -m0644 web/kweb.htk "$ROOT/web/kweb.htk"
    echo "  bundled web/kweb ($(wc -c < "$ROOT/web/kweb") bytes)"
  else
    echo "build_tarball_linux: WARNING — kweb build failed, shipping without kweb" >&2
  fi
  rm -f "$KWIR"
fi
# Runtime support trees the FE/programs need
cp -R stdlib  "$ROOT/stdlib"
cp -R headers "$ROOT/headers"
[[ -d examples ]] && cp -R examples "$ROOT/examples"
[[ -f LICENSE ]] && cp LICENSE "$ROOT/LICENSE"
find "$ROOT" -type f -name '*.k' -exec chmod 0644 {} \;

# Self-contained installer (symlink only — binaries are prebuilt)
cat > "$ROOT/install.sh" <<'INST'
#!/usr/bin/env bash
# Krypton Linux installer — symlinks kcc into PATH. No build, no C.
set -euo pipefail
PREFIX="${1:-/usr/local/krypton}"
BIN="${BINDIR:-/usr/local/bin}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCH=$(uname -m); [[ "$ARCH" == "amd64" ]] && ARCH=x86_64
SUDO=""; [[ -w "$(dirname "$PREFIX")" && -w "$(dirname "$BIN")" ]] || SUDO="sudo"
echo "installing Krypton to $PREFIX ..."
$SUDO rm -rf "$PREFIX"; $SUDO mkdir -p "$PREFIX"; $SUDO cp -R "$HERE"/. "$PREFIX"/
$SUDO mkdir -p "$BIN"
$SUDO ln -sf "$PREFIX/bootstrap/kcc_driver_linux_${ARCH}" "$BIN/kcc"
# kweb (Krypton Web Framework) — native ELF, wrapped so KRYPTON_ROOT resolves
# stdlib/headers (kweb build shells out to kcc).
if [[ -f "$PREFIX/web/kweb" ]]; then
  $SUDO tee "$BIN/kweb" >/dev/null <<KWEB
#!/usr/bin/env bash
export KRYPTON_ROOT="$PREFIX"
exec "$PREFIX/web/kweb" "\$@"
KWEB
  $SUDO chmod 0755 "$BIN/kweb"
fi
echo "done. 'kcc --version':"; KRYPTON_ROOT="$PREFIX" "$BIN/kcc" --version
INST
chmod 0755 "$ROOT/install.sh"

cat > "$ROOT/README.txt" <<RME
Krypton ${VERSION} — Linux ${ARCH}
Install:  ./install.sh            (symlinks kcc into /usr/local/bin)
Use:      kcc hello.k -o hello && ./hello
          kcc --arm64 hello.k -o hello     (cross-compile to aarch64 ELF)
          kcc --version
          kweb init mysite                 (Krypton Web Framework CLI)
No C compiler, no clone needed — prebuilt static binaries.
RME

# Make every prebuilt binary NEWER than the .k sources so the driver never
# triggers its (slow) elf_host self-host rebuild on first run after extract.
find "$ROOT" -type f \( -name elf_host -o -name "kcc-*" -o -name "kcc_*" \) -exec touch {} +
sleep 1; find "$ROOT" -type f \( -name elf_host -o -name "kcc-*" -o -name "kcc_*" \) -exec touch {} +

mkdir -p releases
OUT="releases/${NAME}.tar.gz"
tar -czf "$OUT" -C "$STAGE" "$NAME"
echo "wrote $OUT ($(du -h "$OUT" | cut -f1))"
