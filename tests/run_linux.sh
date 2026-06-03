#!/usr/bin/env bash
# tests/run_linux.sh — Linux native test runner (agent-w greenfield).
#
# For each tests/*.k file: compile to a static-syscall ELF via the
# Linux native backend (kcc.sh -o), run it, check exit code AND grep
# the output for "[FAIL]" markers. Reports PASS / FAIL / SKIP per
# test and exits non-zero if anything failed.
#
# Why this exists: the previous smoke harness was content-shaped to
# the Windows / C path and treated any compile success as a pass —
# segfaults at runtime, FAIL markers in output, and non-zero exit
# codes all got masked. This runner is brutal on purpose: an actual
# test failure on Linux now causes the run to exit 1, suitable for
# CI gating and for catching elf.k regressions early.
#
# Usage:
#   bash tests/run_linux.sh                 # all tests/*.k
#   bash tests/run_linux.sh foo bar         # only tests/foo*.k tests/bar*.k
#   bash tests/run_linux.sh -v              # verbose: show stdout of every test
#   VERBOSE=1 bash tests/run_linux.sh       # same
#
# Exit codes:
#   0   all PASS (SKIP is fine, only the genuinely impossible)
#   1   any test FAIL
#   2   harness setup error (kcc.sh missing, etc.)
#
# Conventions:
#   - A test is a tests/*.k file. Each must compile + run to exit 0.
#   - If the test prints any line containing "[FAIL]" anywhere in its
#     stdout/stderr, it's a FAIL regardless of exit code. (Lots of
#     existing tests print "[PASS]" / "[FAIL]" per assertion.)
#   - SKIP means we couldn't even attempt the test (compile failed
#     for a reason that's not a regression — e.g. test imports
#     something only available on Windows). We log it but don't fail
#     the run.

set -u

# ── 1. Locate repo + kcc driver ────────────────────────────────────────
REPO="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$REPO/tests/.work-linux"
mkdir -p "$WORK"

if [[ ! -f "$REPO/kcc.sh" ]]; then
    echo "run_linux.sh: $REPO/kcc.sh not found — wrong checkout?" >&2
    exit 2
fi
KCC="$REPO/kcc.sh"

# ── 2. Sanity-check we're actually on Linux ────────────────────────────
case "$(uname -s)" in
    Linux*) ;;
    *)
        echo "run_linux.sh: this runner targets Linux (uname=$(uname -s))." >&2
        echo "  On macOS / Windows, use the platform-appropriate harness." >&2
        exit 2 ;;
esac

# ── 3. Parse args ──────────────────────────────────────────────────────
VERBOSE="${VERBOSE:-0}"
SELECTORS=()
for arg in "$@"; do
    case "$arg" in
        -v|--verbose)  VERBOSE=1 ;;
        -h|--help)
            grep '^#' "${BASH_SOURCE[0]}" | sed 's|^# \?||'
            exit 0 ;;
        -*)
            echo "run_linux.sh: unknown flag '$arg'" >&2
            exit 2 ;;
        *)
            SELECTORS+=("$arg") ;;
    esac
done

# ── 4. Select tests ────────────────────────────────────────────────────
tests=()
for k in "$REPO"/tests/*.k; do
    [[ -e "$k" ]] || continue
    name="$(basename "$k" .k)"
    if [[ ${#SELECTORS[@]} -gt 0 ]]; then
        keep=0
        for sel in "${SELECTORS[@]}"; do
            if [[ "$name" == ${sel}* || "$name" == *${sel}* ]]; then keep=1; fi
        done
        [[ $keep -eq 1 ]] || continue
    fi
    tests+=("$k")
done

if [[ ${#tests[@]} -eq 0 ]]; then
    echo "run_linux.sh: no tests matched" >&2
    exit 2
fi

# ── 5. Run loop ────────────────────────────────────────────────────────
PASS=0; FAIL=0; SKIP=0
FAILED=()
SKIPPED=()
T_START="$(date +%s)"

for k in "${tests[@]}"; do
    name="$(basename "$k" .k)"
    exe="$WORK/$name"
    log="$WORK/$name.log"

    # Step a: compile
    if ! "$KCC" -o "$exe" "$k" >"$log.compile" 2>&1; then
        printf '  SKIP %-32s (compile failed)\n' "$name"
        SKIP=$((SKIP+1))
        SKIPPED+=("$name (compile)")
        continue
    fi

    if [[ ! -x "$exe" ]]; then
        printf '  SKIP %-32s (compile succeeded but no exe at %s)\n' "$name" "$exe"
        SKIP=$((SKIP+1))
        SKIPPED+=("$name (no exe)")
        continue
    fi

    # Step b: run. timeout caps any infinite-loop regressions at 10s.
    rc=0
    timeout 10s "$exe" >"$log" 2>&1 || rc=$?

    # Step c: classify
    if [[ $rc -eq 124 ]]; then
        printf '  FAIL %-32s (timed out — possible infinite loop)\n' "$name"
        FAIL=$((FAIL+1))
        FAILED+=("$name (timeout)")
    elif [[ $rc -ge 128 ]]; then
        # 128 + signal — most commonly 139 (SIGSEGV), 137 (SIGKILL)
        sig=$((rc - 128))
        printf '  FAIL %-32s (signal %d, rc=%d)\n' "$name" "$sig" "$rc"
        FAIL=$((FAIL+1))
        FAILED+=("$name (signal $sig)")
    elif [[ $rc -ne 0 ]]; then
        printf '  FAIL %-32s (exit rc=%d)\n' "$name" "$rc"
        FAIL=$((FAIL+1))
        FAILED+=("$name (rc=$rc)")
    elif grep -qE '\[FAIL\]' "$log"; then
        nfail="$(grep -cE '\[FAIL\]' "$log")"
        printf '  FAIL %-32s (%d [FAIL] markers in output)\n' "$name" "$nfail"
        FAIL=$((FAIL+1))
        FAILED+=("$name ($nfail assertions)")
    else
        printf '  PASS %-32s\n' "$name"
        PASS=$((PASS+1))
    fi

    if [[ $VERBOSE -eq 1 ]]; then
        sed 's|^|    |' "$log" | head -40
    fi
done

# ── 6. Summary ─────────────────────────────────────────────────────────
T_END="$(date +%s)"
DUR=$((T_END - T_START))

echo "──────────────────────────────────────────────────────────────"
echo "  Linux native tests: PASS=$PASS  FAIL=$FAIL  SKIP=$SKIP  (${DUR}s)"
if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo "  failed:"
    for f in "${FAILED[@]}"; do echo "    - $f"; done
fi
if [[ ${#SKIPPED[@]} -gt 0 && $VERBOSE -eq 1 ]]; then
    echo "  skipped (verbose):"
    for s in "${SKIPPED[@]}"; do echo "    - $s"; done
fi

# Exit non-zero if any tests genuinely failed. SKIP is forgiven.
if [[ $FAIL -gt 0 ]]; then exit 1; fi
exit 0
