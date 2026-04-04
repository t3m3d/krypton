#!/usr/bin/env bash
# kcc - Krypton compiler driver
# Usage: kcc source.k [-o output.exe] [-lFOO ...] [--ir]
#
# Without -o: writes C to stdout (same as kcc.exe)
# With -o:    compiles all the way to a native .exe via gcc

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KCC_EXE="$SCRIPT_DIR/kcc.exe"
KCC_HEADERS_UNIX="$SCRIPT_DIR/headers"
# Convert /c/foo -> C:/foo for Windows exes; fall back to unix path if not a /X/... form
KCC_HEADERS="$(echo "$KCC_HEADERS_UNIX" | sed 's|^/\([a-zA-Z]\)/|\1:/|')"

# Find gcc — check PATH first, then common Windows install locations
GCC_EXE="$(command -v gcc 2>/dev/null)"
if [[ -z "$GCC_EXE" ]]; then
    for _try in \
        "/c/TDM-GCC-64/bin/gcc.exe" \
        "/C/TDM-GCC-64/bin/gcc.exe" \
        "C:/TDM-GCC-64/bin/gcc.exe" \
        "/c/TDM-GCC-64/bin/gcc" \
        "/C/TDM-GCC-64/bin/gcc" \
        "/c/mingw64/bin/gcc.exe" \
        "/C/mingw64/bin/gcc.exe" \
        "C:/mingw64/bin/gcc.exe" \
        "/c/mingw64/bin/gcc" \
        "/c/msys64/mingw64/bin/gcc.exe" \
        "/C/msys64/mingw64/bin/gcc.exe" \
        "C:/msys64/mingw64/bin/gcc.exe" \
        "/c/msys64/mingw64/bin/gcc"; do
        if [[ -f "$_try" ]]; then GCC_EXE="$_try"; break; fi
    done
fi
# Last resort: try bare name and let the shell resolve it
if [[ -z "$GCC_EXE" ]]; then
    GCC_EXE="gcc"
fi

SRCFILE=""
OUTFILE=""
LIBS="-lm -w"
IRFLAG=""
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ir)
            IRFLAG="--ir"
            shift ;;
        -o)
            OUTFILE="$2"
            shift 2 ;;
        -l*|-L*|-W*)
            LIBS="$LIBS $1"
            shift ;;
        *)
            SRCFILE="$1"
            shift ;;
    esac
done

if [[ -z "$SRCFILE" ]]; then
    echo "kcc: no input file" >&2
    exit 1
fi

HEADERS_FLAG=""
if [[ -d "$KCC_HEADERS_UNIX" ]]; then
    HEADERS_FLAG="--headers $KCC_HEADERS"
fi

if [[ -z "$OUTFILE" ]]; then
    # No -o: pipe C to stdout as usual
    "$KCC_EXE" $IRFLAG $HEADERS_FLAG "$SRCFILE"
    exit $?
fi

# -o mode: compile to native exe via temp file
TMPFILE="${OUTFILE}__kcc_tmp.c"

"$KCC_EXE" $IRFLAG $HEADERS_FLAG "$SRCFILE" > "$TMPFILE"
KCC_RET=$?
if [[ $KCC_RET -ne 0 ]]; then
    rm -f "$TMPFILE"
    echo "kcc: Krypton compilation failed" >&2
    exit 1
fi

"$GCC_EXE" "$TMPFILE" -o "$OUTFILE" $LIBS
GCC_RET=$?
rm -f "$TMPFILE"

if [[ $GCC_RET -ne 0 ]]; then
    echo "kcc: C compilation failed" >&2
    exit 1
fi

exit 0
