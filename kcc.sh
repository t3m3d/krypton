#!/usr/bin/env bash
# kcc - Krypton compiler driver
# Usage: kcc source.k [-o output.exe] [-lFOO ...] [--ir] [--native] [--llvm]
#
# Without -o:      writes C to stdout (same as kcc.exe)
# With -o:         compiles all the way to a native .exe via gcc (default)
# With --native:   .k → .kir → optimize → x64.k → .exe  (no gcc, needs krypton_rt.dll)
# With --llvm:     .k → .kir → optimize → llvm.k → .ll  (LLVM IR output, use clang)
# With --ir:       .k → .kir  (emit IR only)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KCC_EXE="$SCRIPT_DIR/kcc.exe"
KCC_HEADERS_UNIX="$SCRIPT_DIR/headers"
KCC_HEADERS="$(echo "$KCC_HEADERS_UNIX" | sed 's|^/\([a-zA-Z]\)/|\1:/|')"

# Find gcc
GCC_EXE="$(command -v gcc 2>/dev/null)"
if [[ -z "$GCC_EXE" ]]; then
    for _try in \
        "/c/TDM-GCC-64/bin/gcc.exe" \
        "/C/TDM-GCC-64/bin/gcc.exe" \
        "C:/TDM-GCC-64/bin/gcc.exe" \
        "/c/mingw64/bin/gcc.exe" \
        "/C/mingw64/bin/gcc.exe" \
        "/c/msys64/mingw64/bin/gcc.exe" \
        "/C/msys64/mingw64/bin/gcc.exe"; do
        if [[ -f "$_try" ]]; then GCC_EXE="$_try"; break; fi
    done
fi
if [[ -z "$GCC_EXE" ]]; then GCC_EXE="gcc"; fi

SRCFILE=""
OUTFILE=""
LIBS="-O2 -lm -w"
IRFLAG=""
NATIVE_MODE=0
LLVM_MODE=0
GCC_MODE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ir)      IRFLAG="--ir"; shift ;;
        --native)  NATIVE_MODE=1; shift ;;
        --llvm)    LLVM_MODE=1; shift ;;
        --gcc)     GCC_MODE=1; shift ;;
        -o)        OUTFILE="$2"; shift 2 ;;
        -l*|-L*|-W*) LIBS="$LIBS $1"; shift ;;
        *)         SRCFILE="$1"; shift ;;
    esac
done

if [[ -z "$SRCFILE" ]]; then
    echo "kcc: no input file" >&2; exit 1
fi

HEADERS_FLAG=""
if [[ -d "$KCC_HEADERS_UNIX" ]]; then
    HEADERS_FLAG="--headers $KCC_HEADERS"
fi

# ── --ir only: emit IR ────────────────────────────────────────────
if [[ -n "$IRFLAG" && -z "$OUTFILE" ]]; then
    "$KCC_EXE" --ir $HEADERS_FLAG "$SRCFILE"
    exit $?
fi

# ── --native pipeline: .k → .kir → optimize → x64 → .exe ─────────
if [[ $NATIVE_MODE -eq 1 ]]; then
    if [[ -z "$OUTFILE" ]]; then
        OUTFILE="${SRCFILE%.k}.exe"
    fi
    TMPIR="/tmp/_kcc_native_$$.kir"
    TMPOPT="/tmp/_kcc_native_opt_$$.kir"

    # Pre-build optimize.k and x64.k into cached binaries (kompiler/*.exe)
    OPT_BIN="$SCRIPT_DIR/kompiler/optimize_host.exe"
    X64_BIN="$SCRIPT_DIR/kompiler/x64_host.exe"
    if [[ ! -f "$OPT_BIN" || "$SCRIPT_DIR/kompiler/optimize.k" -nt "$OPT_BIN" ]]; then
        echo "kcc: building optimize host..." >&2
        "$KCC_EXE" "$SCRIPT_DIR/kompiler/optimize.k" > /tmp/_kcc_opt_build.c && \
        "$GCC_EXE" /tmp/_kcc_opt_build.c -o "$OPT_BIN" $LIBS && rm -f /tmp/_kcc_opt_build.c
        if [[ $? -ne 0 ]]; then echo "kcc --native: failed to build optimizer" >&2; exit 1; fi
    fi
    if [[ ! -f "$X64_BIN" || "$SCRIPT_DIR/kompiler/x64.k" -nt "$X64_BIN" ]]; then
        echo "kcc: building x64 host..." >&2
        "$KCC_EXE" "$SCRIPT_DIR/kompiler/x64.k" > /tmp/_kcc_x64_build.c && \
        "$GCC_EXE" /tmp/_kcc_x64_build.c -o "$X64_BIN" $LIBS && rm -f /tmp/_kcc_x64_build.c
        if [[ $? -ne 0 ]]; then echo "kcc --native: failed to build x64 codegen" >&2; exit 1; fi
    fi
    # Rebuild krypton_rt_legacy.dll from native_rt.c when the source changes
    RT_LEGACY_SRC="$SCRIPT_DIR/runtime/native_rt.c"
    RT_LEGACY_DLL="$SCRIPT_DIR/runtime/krypton_rt_legacy.dll"
    if [[ ! -f "$RT_LEGACY_DLL" || "$RT_LEGACY_SRC" -nt "$RT_LEGACY_DLL" ]]; then
        echo "kcc: building krypton_rt_legacy.dll from native_rt.c..." >&2
        "$GCC_EXE" -shared -O2 -w "$RT_LEGACY_SRC" -o "$RT_LEGACY_DLL" -lkernel32 -Wl,--export-all-symbols
        if [[ $? -ne 0 ]]; then echo "kcc --native: failed to build krypton_rt_legacy.dll" >&2; exit 1; fi
    fi

    # Step 1: emit IR
    "$KCC_EXE" --ir $HEADERS_FLAG "$SRCFILE" > "$TMPIR"
    if [[ $? -ne 0 ]]; then echo "kcc --native: IR emission failed" >&2; rm -f "$TMPIR"; exit 1; fi

    # Step 2: optimize IR
    "$OPT_BIN" "$TMPIR" > "$TMPOPT"
    if [[ $? -ne 0 ]]; then echo "kcc --native: optimizer failed" >&2; rm -f "$TMPIR" "$TMPOPT"; exit 1; fi

    # Step 3: x64 code generation → .exe
    "$X64_BIN" "$TMPOPT" "$OUTFILE"
    X64_RET=$?
    rm -f "$TMPIR" "$TMPOPT"
    if [[ $X64_RET -ne 0 ]]; then echo "kcc --native: x64 codegen failed" >&2; exit 1; fi

    # Copy runtime DLLs next to output
    RT_DLL="$SCRIPT_DIR/runtime/krypton_rt.dll"
    RT_LEGACY="$SCRIPT_DIR/runtime/krypton_rt_legacy.dll"
    OUT_DIR="$(dirname "$OUTFILE")"
    if [[ -f "$RT_DLL" && "$OUT_DIR" != "$(dirname "$RT_DLL")" ]]; then
        cp "$RT_DLL" "$OUT_DIR/krypton_rt.dll" 2>/dev/null || true
        cp "$RT_LEGACY" "$OUT_DIR/krypton_rt_legacy.dll" 2>/dev/null || true
        echo "kcc: copied runtime DLLs to $OUT_DIR" >&2
    fi
    exit 0
fi

# ── --llvm pipeline: .k → .kir → optimize → llvm IR (.ll) ────────
if [[ $LLVM_MODE -eq 1 ]]; then
    TMPIR="/tmp/_kcc_llvm_$$.kir"
    TMPOPT="/tmp/_kcc_llvm_opt_$$.kir"

    "$KCC_EXE" --ir $HEADERS_FLAG "$SRCFILE" > "$TMPIR"
    if [[ $? -ne 0 ]]; then echo "kcc --llvm: IR emission failed" >&2; rm -f "$TMPIR"; exit 1; fi

    "$KCC_EXE" "$SCRIPT_DIR/kompiler/optimize.k" "$TMPIR" > "$TMPOPT"
    if [[ $? -ne 0 ]]; then echo "kcc --llvm: optimizer failed" >&2; rm -f "$TMPIR" "$TMPOPT"; exit 1; fi

    # Emit LLVM IR
    if [[ -n "$OUTFILE" ]]; then
        "$KCC_EXE" "$SCRIPT_DIR/kompiler/llvm.k" "$TMPOPT" > "$OUTFILE"
    else
        "$KCC_EXE" "$SCRIPT_DIR/kompiler/llvm.k" "$TMPOPT"
    fi
    RET=$?
    rm -f "$TMPIR" "$TMPOPT"
    exit $RET
fi

# ── Default: emit C (no -o) or native exe (with -o) ──────────────
if [[ -z "$OUTFILE" ]]; then
    "$KCC_EXE" $HEADERS_FLAG "$SRCFILE"
    exit $?
fi

# With -o: use native pipeline by default; --gcc flag falls back to gcc
if [[ "$GCC_MODE" -ne 1 ]]; then
    NATIVE_MODE=1
    exec "$0" --native -o "$OUTFILE" "$SRCFILE"
fi

TMPFILE="${OUTFILE}__kcc_tmp.c"
"$KCC_EXE" $HEADERS_FLAG "$SRCFILE" > "$TMPFILE"
if [[ $? -ne 0 ]]; then
    rm -f "$TMPFILE"
    echo "kcc: Krypton compilation failed" >&2
    exit 1
fi

"$GCC_EXE" "$TMPFILE" -o "$OUTFILE" $LIBS
GCC_RET=$?
rm -f "$TMPFILE"
if [[ $GCC_RET -ne 0 ]]; then echo "kcc: C compilation failed" >&2; exit 1; fi
exit 0
