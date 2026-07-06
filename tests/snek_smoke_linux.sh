#!/usr/bin/env bash
# snek_smoke_linux.sh -- Linux-native sibling of tests/snek_smoke.sh.
#
# Pipeline: examples/*.kp -> snek -> .k -> kcc_driver_linux_x86_64 --native
# -> ELF -> run + capture output.
#
# Assumes:
#   - this repo is checked out under the WSL native filesystem (~), NOT /mnt/c
#   - scripts/setup-wsl-exherbo.sh has been run once to install kcc
#   - /tmp/snek is built and current
#
# Usage:
#   tests/snek_smoke_linux.sh          # run all examples/*.kp
#   tests/snek_smoke_linux.sh hello    # just hello.kp
#
# NOTE: some examples are known-broken on the Linux native pipeline
# (see docs/backend_history.md#Linux runtime gap notes). This script REPORTS
# results -- a non-zero exit means at least one example didn't run
# cleanly. Differences between Windows and Linux output for the same
# program point at gaps in linux_x86/elf.k.

set -u
cd "$(dirname "$0")/.."

KCC_DRIVER="./bootstrap/kcc_driver_linux_x86_64"
SNEK="${SNEK:-/tmp/snek}"
TMP="/tmp/snek_smoke_linux"
export KRYPTON_ROOT="$PWD"

mkdir -p "$TMP"

# Rebuild snek if missing or stale.
if [ ! -x "$SNEK" ] || [ compiler/snek.k -nt "$SNEK" ]; then
    echo "==> building $SNEK from compiler/snek.k"
    "$KCC_DRIVER" --native compiler/snek.k -o "$SNEK"
fi

filter="${1:-}"
pass=0
fail=0
failed_list=""

for kp in examples/*.kp; do
    name=$(basename "$kp" .kp)
    if [ -n "$filter" ] && [ "$name" != "$filter" ]; then continue; fi
    krypton="$TMP/$name.k"
    exe="$TMP/$name"
    expected="examples/$name.expected"

    if ! "$SNEK" "$kp" -o "$krypton" 2>"$TMP/$name.snek.err"; then
        echo "FAIL $name (snek translate failed)"
        fail=$((fail+1))
        failed_list="$failed_list $name"
        continue
    fi
    if ! "$KCC_DRIVER" --native "$krypton" -o "$exe" >"$TMP/$name.kcc.out" 2>&1; then
        echo "FAIL $name (kcc compile failed)"
        fail=$((fail+1))
        failed_list="$failed_list $name"
        continue
    fi
    "$exe" >"$TMP/$name.out" 2>&1
    rc=$?
    if [ "$rc" -ge 128 ]; then
        echo "FAIL $name (runtime crash signal $((rc-128)))"
        fail=$((fail+1))
        failed_list="$failed_list $name"
        continue
    fi

    if [ -f "$expected" ]; then
        if diff -q "$TMP/$name.out" "$expected" >/dev/null 2>&1; then
            echo "PASS $name"
            pass=$((pass+1))
        else
            echo "DIFF $name"
            diff "$TMP/$name.out" "$expected" | head -8
            fail=$((fail+1))
            failed_list="$failed_list $name"
        fi
    else
        echo "RUN  $name (no .expected; rc=$rc)"
        pass=$((pass+1))
    fi
done

echo "---"
echo "snek smoke (linux): $pass pass, $fail fail"
if [ "$fail" -gt 0 ]; then
    echo "failed:$failed_list"
    exit 1
fi
