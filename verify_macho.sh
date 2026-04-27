#!/usr/bin/env bash
# verify_macho.sh — verify the Mach-O backend on real macOS, both arches.
#
# kompiler/macho.k emits assembly source (.s); clang assembles+links+signs.
# This script proves: macho.k → .s → clang → working Mach-O on macOS.
#
# Run on a Mac after `./build.sh`:
#
#   ./verify_macho.sh                  # native arch only
#   ./verify_macho.sh --both           # x86_64 + arm64
#   ./verify_macho.sh --arch=arm64     # force one

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "skip: this test is for macOS only (saw $(uname -s))"
    exit 0
fi

HOST_ARCH=$(uname -m)
case "$HOST_ARCH" in
    arm64|aarch64) HOST_NAME=arm64 ;;
    x86_64|amd64)  HOST_NAME=x86_64 ;;
    *) echo "FAIL: unrecognized host arch '$HOST_ARCH'"; exit 1 ;;
esac

ARCHES_TO_RUN=("$HOST_NAME")
case "${1:-}" in
    --both)         ARCHES_TO_RUN=(x86_64 arm64) ;;
    --arch=arm64)   ARCHES_TO_RUN=(arm64) ;;
    --arch=x86_64)  ARCHES_TO_RUN=(x86_64) ;;
esac

if [[ ! -x ./kcc ]]; then
    echo "FAIL: ./kcc not built — run ./build.sh first"
    exit 1
fi

CC="${CC:-clang}"
command -v "$CC" >/dev/null || {
    echo "FAIL: $CC not found — install Xcode Command Line Tools"
    echo "  xcode-select --install"
    exit 1
}

# Build the macho host (compiles macho.k → C → clang → executable)
echo "[setup] Building macho host..."
./kcc kompiler/macho.k > /tmp/_macho.c
"$CC" /tmp/_macho.c -o /tmp/_macho_host -lm -w
rm -f /tmp/_macho.c
echo "        OK  /tmp/_macho_host"
echo ""

run_one_arch() {
    local arch="$1"
    local asm="/tmp/hello_${arch}.s"
    local out="/tmp/hello_${arch}"

    echo "════════════════════════════════════════════════════"
    echo "  arch = $arch"
    echo "════════════════════════════════════════════════════"

    echo "[1/4] Generating $asm..."
    /tmp/_macho_host --arch "$arch" "$asm"

    echo ""
    echo "[2/4] clang -arch $arch $asm -o $out ..."
    "$CC" -arch "$arch" "$asm" -o "$out" 2>&1
    file "$out"

    echo ""
    echo "[3/4] otool -h ..."
    otool -h "$out" || true

    # Native-arch binaries run directly. Cross-arch ones need Rosetta (x86_64 on AS).
    if [[ "$arch" != "$HOST_NAME" && "$HOST_NAME" == "x86_64" ]]; then
        echo "      skip exec: arm64 binary on Intel host cannot run natively"
        return 0
    fi

    echo ""
    echo "[4/4] Run..."
    local exec_out exec_ec
    exec_out=$("$out" 2>&1)
    exec_ec=$?
    echo "      output: $exec_out"
    echo "      exit:   $exec_ec"
    if [[ "$exec_out" != "Hello from Krypton on macOS!" ]]; then
        echo "FAIL: unexpected output (expected: Hello from Krypton on macOS!)"
        return 1
    fi
    if [[ $exec_ec -ne 0 ]]; then
        echo "FAIL: nonzero exit"
        return 1
    fi
    return 0
}

FAILED=0
for arch in "${ARCHES_TO_RUN[@]}"; do
    if ! run_one_arch "$arch"; then
        FAILED=$((FAILED + 1))
    fi
    echo ""
done

if [[ $FAILED -eq 0 ]]; then
    echo "════════════════════════════════════════════════════"
    echo "  Mach-O smoke test PASSED on $(uname -srm)"
    echo "════════════════════════════════════════════════════"
    exit 0
else
    echo "════════════════════════════════════════════════════"
    echo "  Mach-O smoke test FAILED ($FAILED arch(es))"
    echo "════════════════════════════════════════════════════"
    exit 1
fi
