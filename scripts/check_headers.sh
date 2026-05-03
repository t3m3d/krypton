#!/usr/bin/env bash
# Verify every header in headers/ parses cleanly by `import`-ing it
# into a tiny test program. We just emit IR — we don't try to execute
# (most headers reference Windows-only / Linux-only / external libs).
cd "$(dirname "$0")/.."
PASS=0; FAIL=0; FAILED=""
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT
for f in headers/*.krh; do
    n=$(basename "$f")
    src="$TMP/${n%.krh}_smoke.k"
    cat > "$src" <<EOF
import "headers/$n"

just run {
    kp("ok")
}
EOF
    if timeout 10 ./kcc-x64 --ir "$src" >/dev/null 2>&1; then
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1))
        FAILED="$FAILED $n"
    fi
done
echo "PASS=$PASS FAIL=$FAIL"
echo "FAILED=$FAILED"
