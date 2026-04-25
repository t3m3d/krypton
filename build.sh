#!/usr/bin/env bash
# build.sh — Krypton bootstrap build for Linux / macOS / WSL
#
# Layer 1 of Linux support: C-transpile mode only.
#   1) compile bootstrap/kcc_seed.c (a pre-generated C source of compile.k) → ./kcc
#   2) use ./kcc to re-emit compile.k → C → rebuild ./kcc (self-rebuild check)
#   3) smoke test: kcc compiles fibonacci, gcc links, run, check output
#
# After this, ./kcc translates .k files to C. To produce a runnable program:
#   ./kcc source.k > source.c && gcc source.c -o prog -lm -w && ./prog
#
# Native ELF emission (kcc --native on Linux) is NOT supported yet — the
# native PE emitter in kompiler/x64.k targets Windows PE/COFF.

set -euo pipefail

# ── Colours ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; RESET='\033[0m'
ok()   { echo -e "${GREEN}  OK${RESET}  $*"; }
info() { echo -e "${CYAN}  ..${RESET}  $*"; }
fail() { echo -e "${RED}FAIL${RESET}  $*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── Config ──────────────────────────────────────────────────────────────────
SEED_C="bootstrap/kcc_seed.c"
COMPILE_K="kompiler/compile.k"
KCC="./kcc"
CC="${CC:-gcc}"
CFLAGS="-O2 -lm -w"

MODE="${1:-build}"

# ── run FILE.k ──────────────────────────────────────────────────────────────
if [[ "$MODE" == "run" ]]; then
    FILE="${2:-}"
    [[ -n "$FILE" && -f "$FILE" ]] || fail "Usage: ./build.sh run <file.k>"
    [[ -x "$KCC" ]] || fail "kcc not built — run ./build.sh first"
    "$KCC" "$FILE" > /tmp/_kr_out.c
    "$CC" /tmp/_kr_out.c -o /tmp/_kr_run $CFLAGS
    /tmp/_kr_run
    rm -f /tmp/_kr_out.c /tmp/_kr_run
    exit 0
fi

# ── test ────────────────────────────────────────────────────────────────────
if [[ "$MODE" == "test" ]]; then
    [[ -x "$KCC" ]] || fail "kcc not built — run ./build.sh first"
    PASSED=0; FAILED=0
    echo ""
    echo "Running tests..."
    echo "────────────────────────────────────────"
    for TEST in tests/test_*.k; do
        NAME=$(basename "$TEST")
        if "$KCC" "$TEST" > /tmp/_kr_test.c 2>/dev/null \
           && "$CC" /tmp/_kr_test.c -o /tmp/_kr_test_bin $CFLAGS 2>/dev/null \
           && /tmp/_kr_test_bin > /dev/null 2>&1; then
            ok "$NAME"
            PASSED=$((PASSED + 1))
        else
            echo -e "${RED}FAIL${RESET}  $NAME"
            FAILED=$((FAILED + 1))
        fi
    done
    rm -f /tmp/_kr_test.c /tmp/_kr_test_bin
    echo "────────────────────────────────────────"
    echo "  Passed: $PASSED  Failed: $FAILED"
    [[ $FAILED -eq 0 ]] || exit 1
    exit 0
fi

# ── build (default) ─────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════"
echo "  Krypton Linux/WSL Bootstrap Build"
echo "════════════════════════════════════════════════════"
echo ""

# Sanity
[[ -f "$SEED_C" ]]    || fail "missing $SEED_C — generate on Windows: kcc.exe kompiler/compile.k > $SEED_C"
[[ -f "$COMPILE_K" ]] || fail "missing $COMPILE_K"
command -v "$CC" >/dev/null || fail "$CC not found in PATH"

info "compiler: $CC"
info "seed:     $SEED_C ($(wc -l < "$SEED_C") lines)"
echo ""

# [1/3] Build kcc from the seed C
echo "[1/3] Building kcc from bootstrap seed..."
"$CC" "$SEED_C" -o "$KCC" $CFLAGS || fail "gcc compilation of seed failed"
ok "$KCC built ($(stat -c%s "$KCC" 2>/dev/null || stat -f%z "$KCC") bytes)"

# [2/3] Self-rebuild: ./kcc compile.k → fresh .c → gcc → kcc2; replace kcc
echo ""
echo "[2/3] Self-rebuilding kcc from $COMPILE_K..."
"$KCC" "$COMPILE_K" > /tmp/_kcc_self.c || fail "kcc failed to compile compile.k"
"$CC" /tmp/_kcc_self.c -o /tmp/_kcc_self $CFLAGS || fail "gcc failed on self-rebuilt kcc"
mv /tmp/_kcc_self "$KCC"
rm -f /tmp/_kcc_self.c
ok "$KCC self-rebuilt"

# [3/3] Smoke test: fibonacci
echo ""
echo "[3/3] Smoke test: examples/fibonacci.k..."
"$KCC" examples/fibonacci.k > /tmp/_fib.c || fail "kcc failed on fibonacci.k"
"$CC" /tmp/_fib.c -o /tmp/_fib $CFLAGS || fail "gcc failed on fibonacci"
OUTPUT=$(/tmp/_fib)
echo "$OUTPUT" | grep -q "fib(19) = 4181" || fail "fibonacci output wrong: $OUTPUT"
rm -f /tmp/_fib.c /tmp/_fib
ok "fibonacci → 4181"

# Version
VERSION=$("$KCC" --version 2>&1 | head -1)
echo ""
echo "════════════════════════════════════════════════════"
echo "  Build complete: $VERSION"
echo "════════════════════════════════════════════════════"
echo ""
echo "  Usage:"
echo "    ./build.sh run hello.k       compile and run a .k file"
echo "    ./build.sh test              run the test suite"
echo "    ./kcc source.k > source.c    transpile .k → C"
echo "    $CC source.c -o prog -lm     link into a Linux binary"
echo ""
echo "  Note: --native (PE emission) is Windows-only. ELF backend not built yet."
echo ""
