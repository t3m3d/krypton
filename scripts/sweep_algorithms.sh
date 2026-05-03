#!/usr/bin/env bash
# Sweep algorithms through native pipeline.
cd "$(dirname "$0")/.."
PASS=0; FAIL=0; FAILED=""
for f in algorithms/*.k; do
    n=$(basename "$f")
    if timeout 10 ./kcc.sh --native "$f" -o /tmp/_alg 2>/dev/null && timeout 5 /tmp/_alg >/dev/null 2>&1; then
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1))
        FAILED="$FAILED $n"
    fi
    rm -f /tmp/_alg
done
echo "PASS=$PASS FAIL=$FAIL"
echo "FAILED=$FAILED"
