#!/usr/bin/env bash
# build.sh — Krypton bootstrap build for Linux / macOS / WSL
#
# Two paths:
#   1) Prebuilt seed (no gcc needed): if bootstrap/kcc_seed_<arch>_<os> exists,
#      copy it directly as ./kcc. This is the gcc-free path.
#   2) Source seed (needs gcc): if no prebuilt binary, compile bootstrap/kcc_seed.c
#      with gcc to produce ./kcc, then self-rebuild via compile.k.
#
# After either path: smoke-test by compiling and running examples/fibonacci.k.

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
COMPILE_K="compiler/compile.k"
# KCC is the platform-specific binary (./kcc-arm64, ./kcc-x64, ...).
# ./kcc itself is a thin dispatcher script that picks the right one at runtime.
# Set after platform detection below.
# Default C compiler: $CC env var, then gcc, then clang (macOS default).
if [[ -n "${CC:-}" ]]; then
    : # honour user override
elif command -v gcc >/dev/null 2>&1; then
    CC=gcc
elif command -v clang >/dev/null 2>&1; then
    CC=clang
else
    CC=gcc  # will fail later with a clear message if nothing's installed
fi
CFLAGS="-O2 -lm -w"

# Detect platform → look for matching prebuilt seed binary.
case "$(uname -s 2>/dev/null)" in
    Linux*)               OSNAME=linux ;;
    Darwin*)              OSNAME=macos ;;
    MINGW*|MSYS*|CYGWIN*) OSNAME=windows ;;
    *)                    OSNAME=other ;;
esac
case "$(uname -m 2>/dev/null)" in
    x86_64|amd64) ARCH=x86_64 ;;
    aarch64|arm64) ARCH=aarch64 ;;
    *) ARCH=$(uname -m) ;;
esac
SEED_BIN="bootstrap/kcc_seed_${OSNAME}_${ARCH}"
[[ "$OSNAME" == "windows" ]] && SEED_BIN="${SEED_BIN}.exe"

# Platform-specific binary name (kcc itself is a dispatcher).
# Disambiguate macOS arm64 (kcc-arm64) from Linux arm64 (kcc-linux-arm64),
# matching the dispatcher's case in ./kcc.
case "$OSNAME/$ARCH" in
    macos/aarch64)    KCC="./kcc-arm64" ;;
    linux/aarch64)    KCC="./kcc-linux-arm64" ;;
    linux/x86_64)     KCC="./kcc-x64" ;;
    macos/x86_64)     KCC="./kcc-x64" ;;       # Intel Mac fallback (legacy macho.k path)
    windows/x86_64)   KCC="./kcc-x64.exe" ;;
    *)                KCC="./kcc-${ARCH}" ;;
esac

MODE="${1:-build}"

# ── Native-pipeline availability ────────────────────────────────────────────
# Linux/Windows x86_64 ship native codegen hosts (elf_host / x64_host) so
# `kcc.sh --native` produces a binary directly — no gcc, no clang. macOS uses
# macho_arm64_self.k (Krypton-only) on arm64. We treat the native pipeline as
# available whenever the dispatcher will pick a Krypton-only backend.
native_pipeline_available() {
    case "$OSNAME/$ARCH" in
        linux/x86_64)   return 0 ;;
        windows/x86_64) return 0 ;;
        macos/aarch64)  return 0 ;;
        *)              return 1 ;;
    esac
}

# Compile + run a .k file via the native pipeline. Echoes program output on
# stdout. Returns the program's exit code.
native_compile_and_run() {
    local src="$1"
    local out="/tmp/_kr_native_$$"
    "$SCRIPT_DIR/kcc.sh" --native "$src" -o "$out" >/dev/null 2>&1 || { rm -f "$out"; return 1; }
    "$out"; local rc=$?
    rm -f "$out"
    return $rc
}

# ── run FILE.k ──────────────────────────────────────────────────────────────
if [[ "$MODE" == "run" ]]; then
    FILE="${2:-}"
    [[ -n "$FILE" && -f "$FILE" ]] || fail "Usage: ./build.sh run <file.k>"
    [[ -x "$KCC" ]] || fail "kcc not built — run ./build.sh first"
    if native_pipeline_available; then
        native_compile_and_run "$FILE"
        exit $?
    fi
    # Fallback: C path (needs gcc/clang)
    command -v "$CC" >/dev/null || fail "no native pipeline for $OSNAME/$ARCH and $CC not in PATH"
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
    if native_pipeline_available; then
        echo "Running tests (native pipeline, no $CC)..."
    else
        echo "Running tests (C path via $CC)..."
    fi
    echo "────────────────────────────────────────"
    for TEST in tests/test_*.k; do
        NAME=$(basename "$TEST")
        if native_pipeline_available; then
            OUT="/tmp/_kr_test_bin_$$"
            if "$SCRIPT_DIR/kcc.sh" --native "$TEST" -o "$OUT" >/dev/null 2>&1 \
               && "$OUT" > /dev/null 2>&1; then
                ok "$NAME"
                PASSED=$((PASSED + 1))
            else
                echo -e "${RED}FAIL${RESET}  $NAME"
                FAILED=$((FAILED + 1))
            fi
            rm -f "$OUT"
        else
            if "$KCC" "$TEST" > /tmp/_kr_test.c 2>/dev/null \
               && "$CC" /tmp/_kr_test.c -o /tmp/_kr_test_bin $CFLAGS 2>/dev/null \
               && /tmp/_kr_test_bin > /dev/null 2>&1; then
                ok "$NAME"
                PASSED=$((PASSED + 1))
            else
                echo -e "${RED}FAIL${RESET}  $NAME"
                FAILED=$((FAILED + 1))
            fi
            rm -f /tmp/_kr_test.c /tmp/_kr_test_bin
        fi
    done
    echo "────────────────────────────────────────"
    echo "  Passed: $PASSED  Failed: $FAILED"
    [[ $FAILED -eq 0 ]] || exit 1
    exit 0
fi

# ── build (default) ─────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════"
echo "  Krypton Bootstrap Build  (Linux / macOS / WSL)"
echo "════════════════════════════════════════════════════"
echo ""

[[ -f "$COMPILE_K" ]] || fail "missing $COMPILE_K"

# ── Path A: prebuilt seed binary (no gcc required) ──────────────────────────
if [[ -f "$SEED_BIN" ]]; then
    info "platform: ${OSNAME}/${ARCH}"
    info "prebuilt: $SEED_BIN ($(stat -c%s "$SEED_BIN" 2>/dev/null || stat -f%z "$SEED_BIN") bytes)"
    echo ""
    echo "[1/2] Installing prebuilt kcc..."
    cp "$SEED_BIN" "$KCC"
    chmod +x "$KCC"
    ok "$KCC ready (no gcc needed)"

    echo ""
    echo "[2/2] Smoke test: examples/fibonacci.k..."
    if native_pipeline_available; then
        OUTPUT=$(native_compile_and_run examples/fibonacci.k 2>&1) || fail "native build of fibonacci failed: $OUTPUT"
        echo "$OUTPUT" | grep -q "fib(19) = 4181" || fail "fibonacci output wrong: $OUTPUT"
        ok "fibonacci → 4181 (via native pipeline, no $CC)"
    elif command -v "$CC" >/dev/null; then
        "$KCC" examples/fibonacci.k > /tmp/_fib.c || fail "kcc failed on fibonacci.k"
        "$CC" /tmp/_fib.c -o /tmp/_fib $CFLAGS || fail "gcc failed on fibonacci"
        OUTPUT=$(/tmp/_fib)
        echo "$OUTPUT" | grep -q "fib(19) = 4181" || fail "fibonacci output wrong: $OUTPUT"
        rm -f /tmp/_fib.c /tmp/_fib
        ok "fibonacci → 4181 (via gcc-built user program)"
    else
        info "no native pipeline for $OSNAME/$ARCH and gcc not present — skipping smoke test"
    fi
    VERSION=$("$KCC" --version 2>&1 | head -1)
    echo ""
    echo "════════════════════════════════════════════════════"
    echo "  Build complete: $VERSION (gcc-free bootstrap)"
    echo "════════════════════════════════════════════════════"
    echo ""
    echo "  Usage:"
    if native_pipeline_available; then
        echo "    ./build.sh run hello.k        compile + run a .k file (native, no $CC)"
        echo "    ./build.sh test               run the test suite (native, no $CC)"
    else
        echo "    ./build.sh run hello.k        compile + run a .k file (needs $CC)"
        echo "    ./build.sh test               run the test suite (needs $CC)"
    fi
    if [[ "$OSNAME" == "linux" ]]; then
        echo "    ./kcc.sh --native hello.k -o hello   gcc-free native ELF"
    elif [[ "$OSNAME" == "macos" ]]; then
        echo "    ./kcc.sh --native hello.k -o hello   gcc-free native Mach-O (arm64)"
    elif [[ "$OSNAME" == "windows" ]]; then
        echo "    ./kcc.sh --native hello.k -o hello   gcc-free native PE/COFF"
    fi
    echo ""
    exit 0
fi

# ── Path B: source seed (gcc required) ──────────────────────────────────────
[[ -f "$SEED_C" ]] || fail "missing both $SEED_BIN and $SEED_C — cannot bootstrap"
command -v "$CC" >/dev/null || fail "$CC not found in PATH (no prebuilt seed for ${OSNAME}/${ARCH} either)"

info "platform:  ${OSNAME}/${ARCH}  (no prebuilt seed for this platform)"
info "compiler:  $CC"
info "seed:      $SEED_C ($(wc -l < "$SEED_C") lines)"
echo ""

echo "[1/3] Building kcc from bootstrap seed..."
"$CC" "$SEED_C" -o "$KCC" $CFLAGS || fail "gcc compilation of seed failed"
ok "$KCC built ($(stat -c%s "$KCC" 2>/dev/null || stat -f%z "$KCC") bytes)"

echo ""
echo "[2/3] Self-rebuilding kcc from $COMPILE_K..."
"$KCC" "$COMPILE_K" > /tmp/_kcc_self.c || fail "kcc failed to compile compile.k"
"$CC" /tmp/_kcc_self.c -o /tmp/_kcc_self $CFLAGS || fail "gcc failed on self-rebuilt kcc"
mv /tmp/_kcc_self "$KCC"
rm -f /tmp/_kcc_self.c
ok "$KCC self-rebuilt"

echo ""
echo "[3/3] Smoke test: examples/fibonacci.k..."
"$KCC" examples/fibonacci.k > /tmp/_fib.c || fail "kcc failed on fibonacci.k"
"$CC" /tmp/_fib.c -o /tmp/_fib $CFLAGS || fail "gcc failed on fibonacci"
OUTPUT=$(/tmp/_fib)
echo "$OUTPUT" | grep -q "fib(19) = 4181" || fail "fibonacci output wrong: $OUTPUT"
rm -f /tmp/_fib.c /tmp/_fib
ok "fibonacci → 4181"

VERSION=$("$KCC" --version 2>&1 | head -1)
echo ""
echo "════════════════════════════════════════════════════"
echo "  Build complete: $VERSION"
echo "════════════════════════════════════════════════════"
echo ""
echo "  Usage:"
if native_pipeline_available; then
    echo "    ./build.sh run hello.k        compile + run a .k file (native, no $CC)"
    echo "    ./build.sh test               run the test suite (native, no $CC)"
else
    echo "    ./build.sh run hello.k        compile + run a .k file (needs $CC)"
    echo "    ./build.sh test               run the test suite (needs $CC)"
fi
if [[ "$OSNAME" == "linux" ]]; then
    echo "    ./kcc.sh --native hello.k -o hello   gcc-free native ELF"
elif [[ "$OSNAME" == "macos" ]]; then
    echo "    ./kcc.sh --native hello.k -o hello   gcc-free native Mach-O (arm64)"
elif [[ "$OSNAME" == "windows" ]]; then
    echo "    ./kcc.sh --native hello.k -o hello   gcc-free native PE/COFF"
fi
echo ""
