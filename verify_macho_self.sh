#!/usr/bin/env bash
# verify_macho_self.sh — smoke test for the self-hosted arm64 Mach-O emitter.
#
# Builds compiler/macos_arm64/macho_arm64_self.k → host → /tmp/hello_self.macho directly.
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
./kcc compiler/macos_arm64/macho_arm64_self.k > /tmp/_macho_self.c
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

cat > /tmp/_macho_self_test4.k <<'KEOF'
just run {
    let n = 10
    let a = 0
    let b = 1
    let i = 0
    while i < n {
        let t = a + b
        a = b
        b = t
        i = i + 1
    }
    exit(a)
}
KEOF
./kcc --ir /tmp/_macho_self_test4.k > /tmp/_macho_self_test4.kir
"$HOST" --ir /tmp/_macho_self_test4.kir /tmp/_macho_self_ir4.macho
chmod +x /tmp/_macho_self_ir4.macho
codesign -v /tmp/_macho_self_ir4.macho
EXIT4=0
/tmp/_macho_self_ir4.macho || EXIT4=$?
echo "      fib(10) exit code: $EXIT4 (expected 55)"
[[ "$EXIT4" -eq 55 ]] || { echo "FAIL (IR mode control flow)"; exit 1; }

cat > /tmp/_macho_self_test5.k <<'KEOF'
func fact(n) {
    if n <= 1 { emit 1 }
    emit n * fact(n - 1)
}
func add3(a, b, c) { emit a + b + c }
just run {
    exit(add3(fact(5), 0, 5))         // 120 + 5 = 125
}
KEOF
./kcc --ir /tmp/_macho_self_test5.k > /tmp/_macho_self_test5.kir
"$HOST" --ir /tmp/_macho_self_test5.kir /tmp/_macho_self_ir5.macho
chmod +x /tmp/_macho_self_ir5.macho
codesign -v /tmp/_macho_self_ir5.macho
EXIT5=0
/tmp/_macho_self_ir5.macho || EXIT5=$?
echo "      fact(5) + 5 exit code: $EXIT5 (expected 125)"
[[ "$EXIT5" -eq 125 ]] || { echo "FAIL (IR mode function calls)"; exit 1; }

cat > /tmp/_macho_self_test6.k <<'KEOF'
just run {
    let s = "ABCDE"
    exit(charCode(s[0]) + charCode(s[2]) + charCode(s[4]))
    // 'A' + 'C' + 'E' = 65 + 67 + 69 = 201
}
KEOF
./kcc --ir /tmp/_macho_self_test6.k > /tmp/_macho_self_test6.kir
"$HOST" --ir /tmp/_macho_self_test6.kir /tmp/_macho_self_ir6.macho
chmod +x /tmp/_macho_self_ir6.macho
codesign -v /tmp/_macho_self_ir6.macho
EXIT6=0
/tmp/_macho_self_ir6.macho || EXIT6=$?
echo "      INDEX + charCode (3 allocs) exit code: $EXIT6 (expected 201)"
[[ "$EXIT6" -eq 201 ]] || { echo "FAIL (IR mode INDEX/heap)"; exit 1; }

cat > /tmp/_macho_self_test7.k <<'KEOF'
just run {
    let s = "Hello world 42 done"
    let pos = indexOf(s, "42")
    let snippet = substring(s, pos, pos + 2)
    exit(toInt(snippet))   // should parse "42"
}
KEOF
./kcc --ir /tmp/_macho_self_test7.k > /tmp/_macho_self_test7.kir
"$HOST" --ir /tmp/_macho_self_test7.kir /tmp/_macho_self_ir7.macho
chmod +x /tmp/_macho_self_ir7.macho
codesign -v /tmp/_macho_self_ir7.macho
EXIT7=0
/tmp/_macho_self_ir7.macho || EXIT7=$?
echo "      indexOf + substring + toInt exit code: $EXIT7 (expected 42)"
[[ "$EXIT7" -eq 42 ]] || { echo "FAIL (IR mode string builtins)"; exit 1; }

cat > /tmp/_macho_self_test8.k <<'KEOF'
just run {
    let sb = sbNew()
    sb = sbAppend(sb, "Hello")
    sb = sbAppend(sb, ", ")
    sb = sbAppend(sb, "world")
    sb = sbAppend(sb, "!\n")
    print(sbToString(sb))
    let i = 0
    while i < 3 {
        if i == 1 { i = i + 1; break }
        i = i + 1
    }
    exit(i)   // should be 2 (broke at i=1, then incremented)
}
KEOF
./kcc --ir /tmp/_macho_self_test8.k > /tmp/_macho_self_test8.kir
"$HOST" --ir /tmp/_macho_self_test8.kir /tmp/_macho_self_ir8.macho
chmod +x /tmp/_macho_self_ir8.macho
codesign -v /tmp/_macho_self_ir8.macho
EXIT8=0
ACTUAL8=$(/tmp/_macho_self_ir8.macho) || EXIT8=$?
echo "      sb + print + break output: $ACTUAL8 (exit $EXIT8, expected 'Hello, world!' / exit 2)"
[[ "$ACTUAL8" == "Hello, world!" && "$EXIT8" -eq 2 ]] || { echo "FAIL (IR mode sb/print/break)"; exit 1; }

rm -f /tmp/_macho_self_test*.k /tmp/_macho_self_test*.kir /tmp/_macho_self_ir*.macho

echo ""
echo "════════════════════════════════════════════════════"
echo "  Self-hosted Mach-O smoke test PASSED on $(uname -srm)"
echo "════════════════════════════════════════════════════"
