#!/usr/bin/env bash
# verify_macho_self.sh — smoke test for the self-hosted arm64 Mach-O emitter.
#
# Builds kompiler/macho_arm64_self.k → host → /tmp/hello_self.macho directly.
# Krypton emits every byte including the ad-hoc SHA-256 code signature — no
# clang, ld, or codesign in the user-program build path.
#
# `codesign -v` is invoked only to *verify* (independent oracle that Apple's
# tool accepts our signature) — not to sign.
#
# Pass criterion: codesign -v passes, output is exactly "Hi\n", exit code 0.

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

echo "[2/4] Emitting Mach-O directly via writeBytes (incl. ad-hoc SHA-256 sig)..."
"$HOST" "$OUT"
file "$OUT"

echo "[3/5] codesign -v (independent oracle — verification only, no signing)..."
chmod +x "$OUT"
codesign -v "$OUT"
codesign -dv "$OUT" 2>&1 | grep -E "Identifier|CodeDirectory|Signature"

echo "[4/5] Run hardcoded-Hi binary..."
ACTUAL=$("$OUT")
EXIT=$?
echo "      output: $ACTUAL"
echo "      exit:   $EXIT"
[[ "$ACTUAL" == "Hi" && "$EXIT" -eq 0 ]] || { echo "FAIL (default mode)"; exit 1; }

echo "[5/5] IR-driven path: compile real .k programs (kp + locals)..."
cat > /tmp/_macho_self_test.k <<'KEOF'
just run {
    kp("Hello")
    kp("World")
    kp("Krypton on M1")
}
KEOF
./kcc --ir /tmp/_macho_self_test.k > /tmp/_macho_self_test.kir
"$HOST" --ir /tmp/_macho_self_test.kir /tmp/_macho_self_ir.macho
chmod +x /tmp/_macho_self_ir.macho
codesign -v /tmp/_macho_self_ir.macho
ACTUAL_IR=$(/tmp/_macho_self_ir.macho)
EXIT_IR=$?
EXPECTED_IR=$'Hello\nWorld\nKrypton on M1'
echo "      output:"
echo "$ACTUAL_IR" | sed 's/^/        /'
echo "      exit: $EXIT_IR"
[[ "$ACTUAL_IR" == "$EXPECTED_IR" && "$EXIT_IR" -eq 0 ]] || { echo "FAIL (IR mode kp-sequence)"; exit 1; }

cat > /tmp/_macho_self_test2.k <<'KEOF'
just run {
    let a = "first"
    let b = "second"
    kp(a)
    kp(b)
    a = "third"
    kp(a)
}
KEOF
./kcc --ir /tmp/_macho_self_test2.k > /tmp/_macho_self_test2.kir
"$HOST" --ir /tmp/_macho_self_test2.kir /tmp/_macho_self_ir2.macho
chmod +x /tmp/_macho_self_ir2.macho
codesign -v /tmp/_macho_self_ir2.macho
ACTUAL2=$(/tmp/_macho_self_ir2.macho)
EXIT2=$?
EXPECTED2=$'first\nsecond\nthird'
echo "      output (locals):"
echo "$ACTUAL2" | sed 's/^/        /'
[[ "$ACTUAL2" == "$EXPECTED2" && "$EXIT2" -eq 0 ]] || { echo "FAIL (IR mode locals)"; exit 1; }

cat > /tmp/_macho_self_test3.k <<'KEOF'
just run {
    let x = 100
    let y = 7
    exit((x - 8) / y * 3 + x % y)
}
KEOF
./kcc --ir /tmp/_macho_self_test3.k > /tmp/_macho_self_test3.kir
"$HOST" --ir /tmp/_macho_self_test3.kir /tmp/_macho_self_ir3.macho
chmod +x /tmp/_macho_self_ir3.macho
codesign -v /tmp/_macho_self_ir3.macho
EXIT3=0
/tmp/_macho_self_ir3.macho || EXIT3=$?
# (100 - 8) / 7 * 3 + 100 % 7  = 13 * 3 + 2 = 41
echo "      arithmetic exit code: $EXIT3 (expected 41)"
[[ "$EXIT3" -eq 41 ]] || { echo "FAIL (IR mode arithmetic)"; exit 1; }

rm -f /tmp/_macho_self_test*.k /tmp/_macho_self_test*.kir /tmp/_macho_self_ir*.macho

echo ""
echo "════════════════════════════════════════════════════"
echo "  Self-hosted Mach-O smoke test PASSED on $(uname -srm)"
echo "════════════════════════════════════════════════════"
