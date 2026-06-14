#!/usr/bin/env bash
# build.sh — Krypton bootstrap build for Linux / macOS / WSL
#
# Seed-only, C-free: copy the prebuilt bootstrap/kcc_seed_<os>_<arch> binary as
# ./kcc. Every supported platform ships a Krypton-built seed binary — no C
# compiler is ever invoked. (The old gcc-compiled kcc_seed.c source seed was
# removed 2026-06-03; the seeds are now Krypton-built artifacts.)
#
# After install: smoke-test by compiling and running examples/fibonacci.k.

set -euo pipefail

# ── Colours ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; RESET='\033[0m'
ok()   { echo -e "${GREEN}  OK${RESET}  $*"; }
info() { echo -e "${CYAN}  ..${RESET}  $*"; }
fail() { echo -e "${RED}FAIL${RESET}  $*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# The bootstrap kcc driver locates stdlib/headers via KRYPTON_ROOT; from a plain
# source checkout it's otherwise unset and `--native` fails with "cannot find
# install root (set KRYPTON_ROOT)". Default it to this checkout; honour an override.
export KRYPTON_ROOT="${KRYPTON_ROOT:-$SCRIPT_DIR}"

# ── Config ──────────────────────────────────────────────────────────────────
COMPILE_K="compiler/compile.k"
# KCC is the platform-specific binary (compiler/<arch>/kcc-<arch>, kcc.exe on Windows).
# ./kcc is a symlink to the kcc.ks driver seed (bootstrap/kcc_driver_<os>_<arch>),
# which detects OS/arch and invokes the right platform binary at runtime.
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

# The driver is the compiled kcc.ks (KryptScript) native binary, per platform.
# kcc.sh was removed (commit 0c0dc57b); compiles/tests go through this driver.
KCC_DRIVER="$SCRIPT_DIR/bootstrap/kcc_driver_${OSNAME}_${ARCH}"
[[ "$OSNAME" == "windows" ]] && KCC_DRIVER="${KCC_DRIVER}.exe"

# Platform-specific binary path (kcc itself is a dispatcher).
# Binaries live under compiler/<arch>/ since the 2026-05-11 cleanup;
# matches the dispatcher's case in ./kcc.
case "$OSNAME/$ARCH" in
    macos/aarch64)    KCC="./compiler/macos_arm64/kcc-arm64" ;;
    linux/aarch64)    KCC="./compiler/linux_arm64/kcc-linux-arm64" ;;
    linux/x86_64)     KCC="./compiler/linux_x86/kcc-x64" ;;
    macos/x86_64)     KCC="./compiler/linux_x86/kcc-x64" ;;  # Intel Mac fallback (legacy macho.k path)
    windows/x86_64)   KCC="./kcc.exe" ;;
    *)                KCC="./compiler/${OSNAME}_${ARCH}/kcc-${ARCH}" ;;
esac

MODE="${1:-build}"

# ── Native-pipeline availability ────────────────────────────────────────────
# Linux/Windows x86_64 ship native codegen hosts (elf_host / x64_host) so
# `kcc --native` produces a binary directly — no gcc, no clang. macOS uses
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
    "$KCC_DRIVER" --native "$src" -o "$out" >/dev/null 2>&1 || { rm -f "$out"; return 1; }
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
    SKIPPED=0
    for TEST in tests/test_*.k; do
        NAME=$(basename "$TEST")
        # Platform-specific skips
        case "$NAME:$OSNAME" in
            test_dll_exports.k:linux|test_dll_exports.k:macos \
            |test_fs_extended.k:linux|test_fs_extended.k:macos \
            |test_settings.k:linux|test_settings.k:macos)
                # stdlib fs.k/settings.k are pure Win32 IAT (CreateDirectoryA,
                # GetTempPathA, GetEnvironmentVariableA, ...); the native ELF
                # pipeline emits calls to symbols absent off Windows → SIGSEGV.
                echo -e "${CYAN}SKIP${RESET}  $NAME (Windows-only)"
                SKIPPED=$((SKIPPED + 1))
                continue
                ;;
            test_objc_smoke.k:linux|test_objc_smoke.k:windows)
                # objc FFI binds /usr/lib/libobjc.A.dylib via macho dyld chained
                # fixups — macOS-only; no libobjc on ELF/PE targets.
                echo -e "${CYAN}SKIP${RESET}  $NAME (macOS-only)"
                SKIPPED=$((SKIPPED + 1))
                continue
                ;;
        esac
        if native_pipeline_available; then
            OUT="/tmp/_kr_test_bin_$$"
            OUT_LOG="/tmp/_kr_test_log_$$"
            # A test passes if its output contains no "[FAIL]" markers and
            # neither the compile nor the run produced a runtime crash. We
            # don't require exit-0 because many Krypton tests end with a
            # last-expression-value semantics (e.g., `emit "ok"`) that
            # propagates through `just run`'s return into the process exit
            # code. Tests that print [PASS]/[FAIL] markers per assertion
            # would otherwise silently green when the process exit happens
            # to be 0 by luck — the grep filter is what catches bad results.
            if ! "$KCC_DRIVER" --native "$TEST" -o "$OUT" >/dev/null 2>&1; then
                echo -e "${RED}FAIL${RESET}  $NAME (compile)"
                FAILED=$((FAILED + 1))
            else
                # The `if` wrapper keeps `set -e` from aborting on a non-zero
                # exit (which is common — many Krypton tests return their last
                # expression value, not 0). Only signals (>= 128) count as failures.
                # We ignore the exit code: Krypton's `just run` blocks exit
                # with the last expression's value, which is often a pointer
                # ("ok" string), an int (some computed value), or 0 — all
                # of which look "non-zero" to the shell. Tests with [PASS]/
                # [FAIL] assertion lines are the source of truth.
                "$OUT" > "$OUT_LOG" 2>&1 && RC=0 || RC=$?
                if grep -q '\[FAIL\]' "$OUT_LOG"; then
                    echo -e "${RED}FAIL${RESET}  $NAME (assertion)"
                    FAILED=$((FAILED + 1))
                # Crash signals (SIGILL/TRAP/ABRT/EMT/FPE/KILL/BUS/SEGV = rc
                # 132-139) are real failures — a crashed binary produces no
                # [FAIL] marker, so without this it would score as a false pass.
                # The range is narrow enough not to collide with Krypton's
                # last-expression exit-code semantics (tests don't emit 132-139).
                elif [ "$RC" -ge 132 ] && [ "$RC" -le 139 ]; then
                    echo -e "${RED}FAIL${RESET}  $NAME (crash: signal $((RC - 128)))"
                    FAILED=$((FAILED + 1))
                else
                    ok "$NAME"
                    PASSED=$((PASSED + 1))
                fi
            fi
            rm -f "$OUT" "$OUT_LOG"
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
    if [[ $SKIPPED -gt 0 ]]; then
        echo "  Passed: $PASSED  Failed: $FAILED  Skipped: $SKIPPED"
    else
        echo "  Passed: $PASSED  Failed: $FAILED"
    fi
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
        echo "    ./kcc --native hello.k -o hello      gcc-free native ELF (x86_64)"
        echo "    ./kcc --arm64  hello.k -o hello      cross-compile to aarch64 ELF"
    elif [[ "$OSNAME" == "macos" ]]; then
        echo "    ./kcc --native hello.k -o hello      gcc-free native Mach-O (arm64)"
    elif [[ "$OSNAME" == "windows" ]]; then
        echo "    ./kcc --native hello.k -o hello      gcc-free native PE/COFF"
    fi
    echo ""
    exit 0
fi

# ── No prebuilt seed for this platform ──────────────────────────────────────
# There is no C source seed anymore — seeds are Krypton-built binaries. A
# platform without a committed seed binary must be bootstrapped from an existing
# one (cross-build) rather than from C.
fail "no prebuilt seed for ${OSNAME}/${ARCH} (expected $SEED_BIN). Seeds are Krypton-built binaries — bootstrap this platform from an existing seed; there is no C source seed."
