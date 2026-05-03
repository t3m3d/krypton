#!/usr/bin/env bash
# Diagnostic: for each failing example, show why it fails (compile RC, run RC, IR size).
cd "$(dirname "$0")/.."
FAILED="binary_convert calculator debug_pair import_demo number_format run_committed runtokcount string_compress test_tokenize"
for name in $FAILED; do
    f="examples/${name}.k"
    [[ -f "$f" ]] || { echo "$name: missing"; continue; }
    ir_sz=$(timeout 10 ./kcc-x64 --ir "$f" 2>/dev/null | wc -c)
    if [[ "$ir_sz" -eq 0 ]]; then
        echo "$name: IR=0 (compile.k silent failure)"
    else
        compile_rc=0
        timeout 10 ./kcc.sh --native "$f" -o /tmp/_d_$$ >/dev/null 2>&1 || compile_rc=$?
        if [[ "$compile_rc" -ne 0 ]]; then
            echo "$name: IR=$ir_sz, native compile failed RC=$compile_rc"
        elif [[ ! -x /tmp/_d_$$ ]]; then
            echo "$name: IR=$ir_sz, no binary produced"
        else
            run_rc=0
            timeout 5 /tmp/_d_$$ >/dev/null 2>&1 || run_rc=$?
            echo "$name: IR=$ir_sz, runtime RC=$run_rc"
        fi
        rm -f /tmp/_d_$$
    fi
done
