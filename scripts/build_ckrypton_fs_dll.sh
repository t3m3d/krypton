#!/usr/bin/env bash
# Regenerate runtime/ckrypton_fs.dll from stdlib/fs.k.
#
# Same pattern as ckrypton_gui / ckrypton_proc — extract the cfunc
# body, compile via gcc, ship as an IAT-importable side DLL.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SRC_K="$REPO/stdlib/fs.k"
OUT_DLL="$REPO/runtime/ckrypton_fs.dll"
TMP_C="$REPO/runtime/ckrypton_fs.c"

if [[ ! -f "$SRC_K" ]]; then
    echo "FAIL: $SRC_K not found" >&2
    exit 1
fi

START=$(grep -n '^cfunc {' "$SRC_K" | head -1 | cut -d: -f1)
[[ -z "$START" ]] && { echo "FAIL: no 'cfunc {' in $SRC_K" >&2; exit 1; }
START=$((START + 1))
END=$(awk -v s="$START" 'NR>=s && /^}/ {print NR; exit}' "$SRC_K")
END=$((END - 1))

[[ $START -ge $END ]] && { echo "FAIL: bad cfunc range $START..$END" >&2; exit 1; }

echo "Extracting cfunc body lines $START..$END from fs.k..."

{
    cat <<'EOF'
// ckrypton_fs.c — auto-generated from stdlib/fs.k cfunc body.
//
// DO NOT EDIT BY HAND. Regenerate with: scripts/build_ckrypton_fs_dll.sh

#define _WIN32_WINNT 0x0601
#define WINVER       0x0601

#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

EOF
    sed -n "${START},${END}p" "$SRC_K"
} > "$TMP_C"

echo "Compiling $TMP_C -> $OUT_DLL..."
gcc -shared -O2 -w -o "$OUT_DLL" "$TMP_C"

echo "OK $(basename "$OUT_DLL") $(wc -c < "$OUT_DLL") bytes"
echo "Exports: $(objdump -p "$OUT_DLL" 2>/dev/null | grep -cE '^\s+\[\s*[0-9]+\]\s+krFs')"
