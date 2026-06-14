#!/usr/bin/env bash
# snek_smoke.sh -- end-to-end smoke for the snek frontend.
#
# Builds snek.exe (if stale), then for each examples/*.kp:
#   1. translate via snek.exe -> .k
#   2. compile via kcc.exe -> .exe
#   3. run and capture output
#   4. compare against expected output (if examples/<name>.expected exists)
#
# Usage:
#   tests/snek_smoke.sh          # all .kp files
#   tests/snek_smoke.sh hello    # just hello.kp

set -u
cd "$(dirname "$0")/.."

SNEK=c:/tmp/snek.exe
KCC=./kcc.exe
TMP=c:/tmp/snek_smoke

mkdir -p "$TMP"

# Rebuild snek if missing or stale.
if [ ! -x "$SNEK" ] || [ compiler/snek.k -nt "$SNEK" ]; then
    echo "==> building $SNEK"
    "$KCC" compiler/snek.k -o "$SNEK" 2>&1 | tail -3
fi

filter="${1:-}"
pass=0
fail=0
failed_list=""

for kp in examples/*.kp; do
    name=$(basename "$kp" .kp)
    if [ -n "$filter" ] && [ "$name" != "$filter" ]; then
        continue
    fi
    krypton="$TMP/$name.k"
    exe="$TMP/$name.exe"
    expected="examples/$name.expected"

    # Translate.
    if ! "$SNEK" "$kp" -o "$krypton" 2>"$TMP/$name.snek.err"; then
        echo "FAIL $name (snek translate failed)"
        fail=$((fail+1))
        failed_list="$failed_list $name"
        continue
    fi

    # Compile.
    if ! "$KCC" "$krypton" -o "$exe" >"$TMP/$name.kcc.out" 2>&1; then
        echo "FAIL $name (kcc compile failed)"
        fail=$((fail+1))
        failed_list="$failed_list $name"
        continue
    fi

    # Run.
    if ! "$exe" >"$TMP/$name.out" 2>&1; then
        echo "FAIL $name (runtime exit $?)"
        fail=$((fail+1))
        failed_list="$failed_list $name"
        continue
    fi

    # Compare if expected exists.
    if [ -f "$expected" ]; then
        if diff -q "$TMP/$name.out" "$expected" >/dev/null 2>&1; then
            echo "PASS $name"
            pass=$((pass+1))
        else
            echo "DIFF $name"
            diff "$TMP/$name.out" "$expected" | head -10
            fail=$((fail+1))
            failed_list="$failed_list $name"
        fi
    else
        echo "RUN  $name (no .expected)"
        pass=$((pass+1))
    fi
done

echo "---"
echo "snek smoke: $pass pass, $fail fail"
if [ "$fail" -gt 0 ]; then
    echo "failed:$failed_list"
    exit 1
fi
