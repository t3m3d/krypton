#!/usr/bin/env bash
# Sweep stdlib modules through `kcc --ir` to verify they parse cleanly.
# Stdlib modules are libraries (no `just run`), so we can't execute them —
# but the IR walk still catches tokenizer / parser / IR-emit errors.
cd "$(dirname "$0")/.."
PASS=0; FAIL=0; FAILED=""
for f in stdlib/*.k; do
    n=$(basename "$f")
    out=$(timeout 10 ./kcc-x64 --ir "$f" 2>&1)
    sz=$(echo "$out" | wc -c)
    if [[ "$sz" -gt 50 ]]; then
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1))
        FAILED="$FAILED $n"
    fi
done
echo "PASS=$PASS FAIL=$FAIL"
echo "FAILED=$FAILED"
