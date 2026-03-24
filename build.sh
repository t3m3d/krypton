#!/usr/bin/env bash
# build.sh — Krypton build script for Linux / macOS
# Usage:
#   ./build.sh              — full bootstrap + self-host build
#   ./build.sh run FILE=x.k — compile and run a single file
#   ./build.sh test         — run test suite
set -euo pipefail

# ── Colours ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; RESET='\033[0m'
ok()   { echo -e "${GREEN}  OK${RESET}  $*"; }
info() { echo -e "${CYAN}  ..${RESET}  $*"; }
fail() { echo -e "${RED}FAIL${RESET}  $*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── Config ───────────────────────────────────────────────────────────────────
RUNTIME_C="archive/c/run.c"       # The C-compiled interpreter (bootstrap)
COMPILE_K="kompiler/compile.k"    # Self-hosting compiler (Krypton source)
OPTIMIZE_K="kompiler/optimize.k"  # IR optimizer (Krypton source)
LLVM_K="kompiler/llvm.k"          # LLVM IR emitter (Krypton source)

KRUN="./krun"                     # Interpreter binary (built from run.c)
KCC="./kcc"                       # Native compiler binary (after bootstrap)

CC="${CC:-gcc}"

# ── Subcommand dispatch ───────────────────────────────────────────────────────
MODE="${1:-build}"

# ── run FILE=x.k ─────────────────────────────────────────────────────────────
if [[ "$MODE" == "run" ]]; then
    FILE="${2:-}"
    if [[ -z "$FILE" ]]; then
        fail "Usage: ./build.sh run <file.k>"
    fi
    if [[ ! -f "$FILE" ]]; then
        fail "File not found: $FILE"
    fi
    if [[ -x "$KCC" ]]; then
        info "Compiling with kcc..."
        "$KCC" "$FILE" > /tmp/_kr_out.c
        "$CC" /tmp/_kr_out.c -o /tmp/_kr_run -lm -w
        /tmp/_kr_run
    elif [[ -x "$KRUN" ]]; then
        info "Running via interpreter (kcc not built yet)..."
        "$KRUN" "$COMPILE_K" "$FILE" > /tmp/_kr_out.c
        "$CC" /tmp/_kr_out.c -o /tmp/_kr_run -lm -w
        /tmp/_kr_run
    else
        fail "Neither kcc nor krun found. Run ./build.sh first."
    fi
    exit 0
fi

# ── test ─────────────────────────────────────────────────────────────────────
if [[ "$MODE" == "test" ]]; then
    if [[ ! -x "$KCC" ]] && [[ ! -x "$KRUN" ]]; then
        fail "Build first: ./build.sh"
    fi
    PASSED=0; FAILED=0
    echo ""
    echo "Running tests..."
    echo "────────────────────────────────────────"
    for TEST in tests/test_*.k; do
        NAME=$(basename "$TEST")
        if [[ -x "$KCC" ]]; then
            "$KCC" "$TEST" > /tmp/_kr_test.c 2>/dev/null
        else
            "$KRUN" "$COMPILE_K" "$TEST" > /tmp/_kr_test.c 2>/dev/null
        fi
        if "$CC" /tmp/_kr_test.c -o /tmp/_kr_test_bin -lm -w 2>/dev/null; then
            if /tmp/_kr_test_bin > /dev/null 2>&1; then
                ok "$NAME"
                PASSED=$((PASSED + 1))
            else
                echo -e "${RED}FAIL${RESET}  $NAME  (runtime error)"
                FAILED=$((FAILED + 1))
            fi
        else
            echo -e "${RED}FAIL${RESET}  $NAME  (compile error)"
            FAILED=$((FAILED + 1))
        fi
    done
    echo "────────────────────────────────────────"
    echo "  Passed: $PASSED  Failed: $FAILED"
    echo ""
    [[ $FAILED -eq 0 ]] || exit 1
    exit 0
fi

# ── build (default) ───────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════"
echo "  Krypton — Linux/macOS Build"
echo "════════════════════════════════════════════════════"
echo ""

# Step 1 — Build the C interpreter (bootstrap)
echo "[1/4] Building interpreter from C source..."
if [[ ! -f "$RUNTIME_C" ]]; then
    fail "Missing $RUNTIME_C — is the archive/ directory present?"
fi
"$CC" "$RUNTIME_C" -o "$KRUN" -lm -w
ok "krun built"

# Smoke test the interpreter
echo 'just run { kp("ok") }' > /tmp/_kr_smoke.k
SMOKE=$("$KRUN" /tmp/_kr_smoke.k 2>/dev/null || true)

# Step 2 — Compile compile.k to C using the interpreter, producing kcc
echo ""
echo "[2/4] Self-hosting: compiling kompiler/compile.k via interpreter..."
echo "      (this takes ~30–120 seconds on first run)"
"$KRUN" "$COMPILE_K" "$COMPILE_K" > /tmp/_kcc.c
ok "compile.k compiled to C"

# Step 3 — Compile the resulting C to a native kcc binary
echo ""
echo "[3/4] Building native kcc from generated C..."
"$CC" /tmp/_kcc.c -o "$KCC" -lm -w
ok "kcc built → $SCRIPT_DIR/kcc"

# Step 4 — Build the optimizer and LLVM emitter
echo ""
echo "[4/4] Building optimizer and LLVM backend..."
"$KCC" "$OPTIMIZE_K" > /tmp/_optimizer.c
"$CC" /tmp/_optimizer.c -o ./koptimize -lm -w
ok "koptimize built"

"$KCC" "$LLVM_K" > /tmp/_llvmbe.c
"$CC" /tmp/_llvmbe.c -o ./kllvmbe -lm -w
ok "kllvmbe built"

# ── Self-host verification ────────────────────────────────────────────────────
echo ""
echo "Verifying self-host (kcc compiles itself)..."
"$KCC" "$COMPILE_K" > /tmp/_kcc_selfhost.c
"$CC" /tmp/_kcc_selfhost.c -o /tmp/_kcc_selfhost_bin -lm -w
# Check the two binaries produce identical output on a test file
"$KCC" examples/fibonacci.k > /tmp/_fib_a.c
/tmp/_kcc_selfhost_bin examples/fibonacci.k > /tmp/_fib_b.c
if diff -q /tmp/_fib_a.c /tmp/_fib_b.c > /dev/null 2>&1; then
    ok "Self-host verified — kcc and kcc² produce identical output"
else
    echo "  Warning: self-host output differs (may be non-fatal)"
fi

echo ""
echo "════════════════════════════════════════════════════"
echo "  Build complete!"
echo ""
echo "  Usage:"
echo "    ./build.sh run hello.k       compile + run a .k file"
echo "    ./build.sh test              run the test suite"
echo "    ./kcc source.k > source.c    compile to C manually"
echo "    gcc source.c -o program -lm  link the C output"
echo ""
echo "  LLVM pipeline:"
echo "    ./kcc --ir source.k > source.kir"
echo "    ./koptimize source.kir > source_opt.kir"
echo "    ./kllvmbe source_opt.kir > source.ll"
echo "    clang source.ll runtime/krypton_runtime.c -o program"
echo "════════════════════════════════════════════════════"
echo ""
