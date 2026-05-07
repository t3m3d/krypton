#!/usr/bin/env bash
# Regenerate runtime/ckrypton_gui.dll from stdlib/gui.k.
#
# Naming convention: the leading "c" marks this as a C-implemented
# companion DLL (vs. krypton_rt.dll, which is built from Krypton
# source in krypton_rt.k). Body is extracted verbatim from
# stdlib/gui.k's cfunc { } block and compiled as C.
#
# Run this whenever stdlib/gui.k's cfunc body changes (new widget,
# bug fix in the C side). Output: runtime/ckrypton_gui.dll, which
# the native pipeline IAT-imports as a 6th DLL alongside kernel32 /
# krypton_rt / advapi32 / pdh / user32.
#
# Why a side DLL: the native PE backend's IR generator drops cfunc
# bodies, so functions defined inside cfunc { } can't be called
# directly from a kcc -o native build. Compiling them once into a
# DLL via gcc, exporting them, and IAT-linking gives the native
# pipeline a way to reach them — the same trick krypton_rt.dll
# uses for the runtime helpers.
#
# This is a one-time gcc bootstrap analogous to
# bin/x64_host_new.exe — end-user `kcc -o foo.exe foo.k` builds
# never touch gcc.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
GUI_K="$REPO/stdlib/gui.k"
OUT_DLL="$REPO/runtime/ckrypton_gui.dll"
TMP_C="$REPO/runtime/ckrypton_gui.c"

if [[ ! -f "$GUI_K" ]]; then
    echo "FAIL: $GUI_K not found" >&2
    exit 1
fi

# Locate cfunc body. The cfunc { ... } block straddles the file from
# its opening line to one before the closing }. We grep for the line
# numbers then sed them out.
START=$(grep -n '^cfunc {' "$GUI_K" | head -1 | cut -d: -f1)
if [[ -z "$START" ]]; then
    echo "FAIL: no 'cfunc {' line in $GUI_K" >&2
    exit 1
fi
START=$((START + 1))

# The matching close } is the first } at column 0 *after* the cfunc
# opening — we can't use `tail -1` because Krypton funcs further down
# in the file also start lines with }.
END=$(awk -v s="$START" 'NR>=s && /^}/ {print NR; exit}' "$GUI_K")
END=$((END - 1))

if [[ $START -ge $END ]]; then
    echo "FAIL: bad cfunc range $START..$END" >&2
    exit 1
fi

echo "Extracting cfunc body lines $START..$END from gui.k..."

{
    cat <<'EOF'
// ckrypton_gui.c — auto-generated from stdlib/gui.k cfunc body.
//
// DO NOT EDIT BY HAND. Regenerate with: scripts/build_ckrypton_gui_dll.sh

#define _WIN32_WINNT 0x0601
#define WINVER       0x0601

#include <windows.h>
#include <commctrl.h>
#include <commdlg.h>
#include <shlobj.h>
#include <uxtheme.h>
#include <dwmapi.h>
#include <richedit.h>
#include <wchar.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

// RichEdit code uses kr_gui_resolve before its definition appears.
static HWND kr_gui_resolve(char* s);

BOOL WINAPI DllMain(HINSTANCE hinstDLL, DWORD fdwReason, LPVOID lpvReserved) {
    (void)hinstDLL; (void)fdwReason; (void)lpvReserved;
    return TRUE;
}

EOF
    sed -n "${START},${END}p" "$GUI_K" \
        | sed 's|^    char\* krGui|    __declspec(dllexport) char* krGui|g'
} > "$TMP_C"

echo "Compiling $TMP_C -> $OUT_DLL..."
gcc -shared -O2 -w -o "$OUT_DLL" "$TMP_C" \
    -luser32 -lgdi32 -lcomctl32 -lcomdlg32 -lole32 \
    -luxtheme -ldwmapi -lshell32 -lmsimg32 -lgdiplus -ladvapi32

echo "OK $(basename "$OUT_DLL") $(wc -c < "$OUT_DLL") bytes"
echo "Exports: $(objdump -p "$OUT_DLL" 2>/dev/null | grep -cE '^\s+\[\s*[0-9]+\]\s+krGui')"
