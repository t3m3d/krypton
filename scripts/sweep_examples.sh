#!/usr/bin/env bash
# Sweep examples through native pipeline, in chunks. Usage: sweep_examples.sh [glob]
cd "$(dirname "$0")/.."
GLOB="${1:-examples/*.k}"
PASS=0; FAIL=0; FAILED=""
for f in $GLOB; do
    n=$(basename "$f")
    if timeout 10 ./kcc.sh --native "$f" -o /tmp/_ex 2>/dev/null && timeout 5 /tmp/_ex >/dev/null 2>&1; then
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1))
        FAILED="$FAILED $n"
    fi
    rm -f /tmp/_ex
done
echo "PASS=$PASS FAIL=$FAIL"
echo "FAILED=$FAILED"
