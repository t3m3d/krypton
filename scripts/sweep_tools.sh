#!/usr/bin/env bash
# Sweep tools/ through the native pipeline.
# Most tools take a file/path arg; we test by passing examples/hello.k where
# possible. mkelf_hello is special — it writes a binary, not stdout.
cd "$(dirname "$0")/.."
PASS=0; FAIL=0; FAILED=""
ARG_DEFAULT="examples/hello.k"
for f in tools/*.k; do
    n=$(basename "$f")
    arg="$ARG_DEFAULT"
    case "$n" in
        # tools that don't take a file argument
        mkelf_hello.k) arg="" ;;
        # tools that take two file args
        diff_lines.k) arg="$ARG_DEFAULT $ARG_DEFAULT" ;;
        # tools that need a numeric arg
        head.k|tail.k) arg="3 $ARG_DEFAULT" ;;
        fold.k) arg="40 $ARG_DEFAULT" ;;
        cut.k|fmt.k|grep.k|indent.k|replace.k) arg="" ;;  # need richer args; smoke-only
    esac
    if timeout 10 ./kcc.sh --native "$f" -o /tmp/_t 2>/dev/null; then
        # if we have args, run with them; otherwise just verify it built
        if [[ -n "$arg" ]]; then
            timeout 5 /tmp/_t $arg >/dev/null 2>&1
            rc=$?
        else
            rc=0  # build-only smoke test
        fi
        if [[ $rc -eq 0 || $rc -eq 1 || $rc -eq 2 ]]; then
            PASS=$((PASS+1))
        else
            FAIL=$((FAIL+1))
            FAILED="$FAILED $n($rc)"
        fi
    else
        FAIL=$((FAIL+1))
        FAILED="$FAILED $n(build)"
    fi
    rm -f /tmp/_t
done
echo "PASS=$PASS FAIL=$FAIL"
echo "FAILED=$FAILED"
