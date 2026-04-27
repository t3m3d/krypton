#!/usr/bin/env bash
# verify_macho.sh — verify the Mach-O backend on real macOS, both arches.
#
# What this proves: kompiler/macho.k produces binaries that
#   1. macOS recognizes as valid Mach-O 64-bit executables (x86_64 and arm64),
#   2. pass otool's structural inspection (header, load commands),
#   3. run after ad-hoc code signing,
#   4. print the expected hello message and exit cleanly (status 0).
#
# Run on a Mac after `./build.sh`:
#
#   ./verify_macho.sh
#
# By default, runs ONLY the binary that matches the host architecture (since
# x86_64 binaries on Apple Silicon need Rosetta 2). Pass --both to attempt
# both. Pass --arch=arm64|x86_64 to force a specific one.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "skip: this test is for macOS only (saw $(uname -s))"
    exit 0
fi

# Pick which arch(es) to run.
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

# Build the macho host (compiles macho.k → C → clang/gcc → executable)
echo "[setup] Building macho host..."
./kcc kompiler/macho.k > /tmp/_macho.c
${CC:-clang} /tmp/_macho.c -o /tmp/_macho_host -lm -w
rm -f /tmp/_macho.c
echo "        OK  /tmp/_macho_host"
echo ""

run_one_arch() {
    local arch="$1"
    local out="/tmp/hello_${arch}.macho"

    echo "════════════════════════════════════════════════════"
    echo "  arch = $arch"
    echo "════════════════════════════════════════════════════"

    echo "[1/5] Generating $out..."
    /tmp/_macho_host --arch "$arch" "$out"

    echo ""
    echo "[2/5] file utility check..."
    local f
    f=$(file "$out")
    echo "      $f"
    if ! echo "$f" | grep -qE "Mach-O 64-bit.*$arch"; then
        echo "FAIL: not recognized as Mach-O 64-bit $arch"
        return 1
    fi

    echo ""
    echo "[3/5] otool -h (header)..."
    otool -h "$out"

    echo ""
    echo "[4/5] otool -l (load commands)..."
    otool -l "$out"

    echo ""
    echo "[5/5] codesign + run..."
    codesign -s - --force "$out"
    chmod +x "$out"

    # If the requested arch doesn't match host, x86_64 on AS goes through
    # Rosetta 2 (auto-installed on first use). ARM64 on Intel can't run.
    if [[ "$arch" != "$HOST_NAME" && "$HOST_NAME" == "x86_64" ]]; then
        echo "      skip exec: arm64 binary on Intel host cannot run natively"
        return 0
    fi

    local exec_out exec_ec
    exec_out=$("$out" 2>&1)
    exec_ec=$?
    echo "      output: $exec_out"
    echo "      exit:   $exec_ec"
    if [[ "$exec_out" != "Hello from Krypton on macOS!" ]]; then
        echo "FAIL: unexpected output"
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
