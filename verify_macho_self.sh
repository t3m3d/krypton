#!/usr/bin/env bash
# verify_macho_self.sh — smoke test for the self-hosted arm64 Mach-O emitter.
#
# Builds kompiler/macho_arm64_self.k → host → /tmp/hello_self.macho directly
# (no clang, no ld touching the output). Ad-hoc signs (external codesign,
# pending in-Krypton SHA-256 in slice 2) and runs.
#
# Pass criterion: output is exactly "Hi\n" and exit code 0.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "skip: macOS only (saw $(uname -s))"
    exit 0
fi
if [[ "$(uname -m)" != "arm64" && "$(uname -m)" != "aarch64" ]]; then
    echo "skip: Apple Silicon only (saw $(uname -m))"
    exit 0
fi
[[ -x ./kcc ]] || { echo "FAIL: ./kcc not built — run ./build.sh first"; exit 1; }

CC="${CC:-clang}"
OUT=/tmp/hello_self.macho
HOST=/tmp/_macho_self_host

echo "[1/4] Building macho_arm64_self host..."
./kcc kompiler/macho_arm64_self.k > /tmp/_macho_self.c
"$CC" /tmp/_macho_self.c -o "$HOST" -lm -w
rm -f /tmp/_macho_self.c

echo "[2/4] Emitting Mach-O directly via writeBytes (no clang/ld in this step)..."
"$HOST" "$OUT"
file "$OUT"

echo "[3/4] codesign -s - --force (slice 2 will replace this with in-Krypton SHA-256)..."
chmod +x "$OUT"
codesign -s - --force "$OUT"
codesign -v "$OUT"

echo "[4/4] Run..."
ACTUAL=$("$OUT")
EXIT=$?
echo "      output: $ACTUAL"
echo "      exit:   $EXIT"
[[ "$ACTUAL" == "Hi" && "$EXIT" -eq 0 ]] || { echo "FAIL"; exit 1; }

echo ""
echo "════════════════════════════════════════════════════"
echo "  Self-hosted Mach-O smoke test PASSED on $(uname -srm)"
echo "════════════════════════════════════════════════════"
