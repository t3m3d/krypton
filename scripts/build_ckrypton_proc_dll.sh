#!/usr/bin/env bash
# Regenerate runtime/ckrypton_proc.dll from stdlib/proc.k.
#
# Naming convention: leading "c" marks this as a C-implemented
# companion DLL (vs. krypton_rt.dll, which is built from Krypton
# source in krypton_rt.k). Body is extracted verbatim from
# stdlib/proc.k's cfunc { } block and compiled as C.
#
# Run this whenever stdlib/proc.k's cfunc body changes (new
# function, bug fix in the C side). Output:
# runtime/ckrypton_proc.dll, which the native pipeline IAT-imports
# as a 7th DLL alongside the existing six.
#
# Same one-time gcc bootstrap pattern as ckrypton_gui — end-user
# `kcc -o foo.exe foo.k` builds never touch gcc.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PROC_K="$REPO/stdlib/proc.k"
OUT_DLL="$REPO/runtime/ckrypton_proc.dll"
TMP_C="$REPO/runtime/ckrypton_proc.c"

if [[ ! -f "$PROC_K" ]]; then
    echo "FAIL: $PROC_K not found" >&2
    exit 1
fi

START=$(grep -n '^cfunc {' "$PROC_K" | head -1 | cut -d: -f1)
if [[ -z "$START" ]]; then
    echo "FAIL: no 'cfunc {' line in $PROC_K" >&2
    exit 1
fi
START=$((START + 1))
END=$(awk -v s="$START" 'NR>=s && /^}/ {print NR; exit}' "$PROC_K")
END=$((END - 1))

if [[ $START -ge $END ]]; then
    echo "FAIL: bad cfunc range $START..$END" >&2
    exit 1
fi

echo "Extracting cfunc body lines $START..$END from proc.k..."

{
    cat <<'EOF'
// ckrypton_proc.c — auto-generated from stdlib/proc.k cfunc body.
//
// DO NOT EDIT BY HAND. Regenerate with: scripts/build_ckrypton_proc_dll.sh

#define _WIN32_WINNT 0x0601
#define WINVER       0x0601

#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

EOF
    sed -n "${START},${END}p" "$PROC_K"
} > "$TMP_C"

echo "Compiling $TMP_C -> $OUT_DLL..."
gcc -shared -O2 -w -o "$OUT_DLL" "$TMP_C" -ladvapi32

echo "OK $(basename "$OUT_DLL") $(wc -c < "$OUT_DLL") bytes"
echo "Exports: $(objdump -p "$OUT_DLL" 2>/dev/null | grep -cE '^\s+\[\s*[0-9]+\]\s+krProc')"
