#!/usr/bin/env bash
# kcc - Krypton compiler driver
# Usage: kcc source.k [-o output] [-lFOO ...] [--ir] [--native] [--llvm]
#
# Without -o:      writes C to stdout
# With -o:         compiles all the way to a native binary (default = native pipeline)
# With --native:   no gcc — uses x64.k (Windows PE/COFF) or elf.k (Linux ELF)
# With --llvm:     .k → .kir → optimize → llvm.k → .ll  (LLVM IR output, use clang)
# With --gcc:      force the gcc-via-C path
# With --ir:       .k → .kir  (emit IR only)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Platform detection ─────────────────────────────────────────────
# On Linux: ./kcc (ELF), --native uses elf.k → ELF
# On Windows / MSYS: ./kcc.exe, --native uses x64.k → PE/COFF
case "$(uname -s 2>/dev/null)" in
    Linux*)  PLATFORM=linux ;;
    Darwin*) PLATFORM=macos ;;
    *)       PLATFORM=windows ;;
esac

if [[ "$PLATFORM" == "linux" || "$PLATFORM" == "macos" ]]; then
    KCC_EXE="$SCRIPT_DIR/kcc"
    KCC_HEADERS="$SCRIPT_DIR/headers"
else
    KCC_EXE="$SCRIPT_DIR/kcc.exe"
    KCC_HEADERS_UNIX="$SCRIPT_DIR/headers"
    KCC_HEADERS="$(echo "$KCC_HEADERS_UNIX" | sed 's|^/\([a-zA-Z]\)/|\1:/|')"
fi

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

# ── --native pipeline ───────────────────────────────────────────────
# Linux/macOS: .k → .kir → elf.k → ELF binary (no gcc, no libc)
# Windows:     .k → .kir → optimize → x64.k → .exe (no gcc, needs krypton_rt.dll)
if [[ $NATIVE_MODE -eq 1 ]]; then
    if [[ -z "$OUTFILE" ]]; then
        if [[ "$PLATFORM" == "linux" || "$PLATFORM" == "macos" ]]; then
            OUTFILE="${SRCFILE%.k}"
        else
            OUTFILE="${SRCFILE%.k}.exe"
        fi
    fi
    TMPIR="/tmp/_kcc_native_$$.kir"

    if [[ "$PLATFORM" == "linux" || "$PLATFORM" == "macos" ]]; then
        # Linux ELF backend via kompiler/elf.k
        ELF_BIN="$SCRIPT_DIR/kompiler/elf_host"

        # Detect arch for prebuilt seed lookup
        case "$(uname -m 2>/dev/null)" in
            x86_64|amd64) _ARCH=x86_64 ;;
            aarch64|arm64) _ARCH=aarch64 ;;
            *) _ARCH=$(uname -m) ;;
        esac
        ELF_SEED="$SCRIPT_DIR/bootstrap/elf_host_${PLATFORM}_${_ARCH}"

        if [[ ! -f "$ELF_BIN" || "$SCRIPT_DIR/kompiler/elf.k" -nt "$ELF_BIN" ]]; then
            # Prefer prebuilt seed (no gcc needed). Fall back to gcc-build if no seed.
            if [[ -f "$ELF_SEED" && "$ELF_SEED" -nt "$SCRIPT_DIR/kompiler/elf.k" ]]; then
                cp "$ELF_SEED" "$ELF_BIN"
                chmod +x "$ELF_BIN"
            else
                if [[ -z "$GCC_EXE" || ! -x "$(command -v "$GCC_EXE" 2>/dev/null)$GCC_EXE" ]] && ! command -v "$GCC_EXE" >/dev/null 2>&1; then
                    echo "kcc --native: no prebuilt elf_host seed for ${PLATFORM}_${_ARCH} and no gcc found" >&2
                    exit 1
                fi
                echo "kcc: building elf host..." >&2
                "$KCC_EXE" "$SCRIPT_DIR/kompiler/elf.k" > /tmp/_kcc_elf_build.c && \
                "$GCC_EXE" /tmp/_kcc_elf_build.c -o "$ELF_BIN" $LIBS && rm -f /tmp/_kcc_elf_build.c
                if [[ $? -ne 0 ]]; then echo "kcc --native: failed to build elf codegen" >&2; exit 1; fi
            fi
        fi

        "$KCC_EXE" --ir $HEADERS_FLAG "$SRCFILE" > "$TMPIR"
        if [[ $? -ne 0 ]]; then echo "kcc --native: IR emission failed" >&2; rm -f "$TMPIR"; exit 1; fi

        "$ELF_BIN" "$TMPIR" "$OUTFILE"
        ELF_RET=$?
        rm -f "$TMPIR"
        if [[ $ELF_RET -ne 0 ]]; then echo "kcc --native: elf codegen failed" >&2; exit 1; fi
        chmod +x "$OUTFILE"
        exit 0
    fi

    # Windows: PE/COFF backend
    TMPOPT="/tmp/_kcc_native_opt_$$.kir"
    OPT_BIN="$SCRIPT_DIR/kompiler/optimize_host.exe"
    X64_BIN="$SCRIPT_DIR/kompiler/x64_host.exe"
    OPT_SEED="$SCRIPT_DIR/bootstrap/optimize_host_windows_x86_64.exe"
    X64_SEED="$SCRIPT_DIR/bootstrap/x64_host_windows_x86_64.exe"

    if [[ ! -f "$OPT_BIN" || "$SCRIPT_DIR/kompiler/optimize.k" -nt "$OPT_BIN" ]]; then
        # Prefer prebuilt seed (no gcc needed). Fall back to gcc-build.
        if [[ -f "$OPT_SEED" && "$OPT_SEED" -nt "$SCRIPT_DIR/kompiler/optimize.k" ]]; then
            cp "$OPT_SEED" "$OPT_BIN"
        else
            echo "kcc: building optimize host..." >&2
            "$KCC_EXE" "$SCRIPT_DIR/kompiler/optimize.k" > /tmp/_kcc_opt_build.c && \
            "$GCC_EXE" /tmp/_kcc_opt_build.c -o "$OPT_BIN" $LIBS && rm -f /tmp/_kcc_opt_build.c
            if [[ $? -ne 0 ]]; then echo "kcc --native: failed to build optimizer" >&2; exit 1; fi
        fi
    fi
    if [[ ! -f "$X64_BIN" || "$SCRIPT_DIR/kompiler/x64.k" -nt "$X64_BIN" ]]; then
        if [[ -f "$X64_SEED" && "$X64_SEED" -nt "$SCRIPT_DIR/kompiler/x64.k" ]]; then
            cp "$X64_SEED" "$X64_BIN"
        else
            echo "kcc: building x64 host..." >&2
            "$KCC_EXE" "$SCRIPT_DIR/kompiler/x64.k" > /tmp/_kcc_x64_build.c && \
            "$GCC_EXE" /tmp/_kcc_x64_build.c -o "$X64_BIN" $LIBS && rm -f /tmp/_kcc_x64_build.c
            if [[ $? -ne 0 ]]; then echo "kcc --native: failed to build x64 codegen" >&2; exit 1; fi
        fi
    fi

    "$KCC_EXE" --ir $HEADERS_FLAG "$SRCFILE" > "$TMPIR"
    if [[ $? -ne 0 ]]; then echo "kcc --native: IR emission failed" >&2; rm -f "$TMPIR"; exit 1; fi

    "$OPT_BIN" "$TMPIR" > "$TMPOPT"
    if [[ $? -ne 0 ]]; then echo "kcc --native: optimizer failed" >&2; rm -f "$TMPIR" "$TMPOPT"; exit 1; fi

    "$X64_BIN" "$TMPOPT" "$OUTFILE"
    X64_RET=$?
    rm -f "$TMPIR" "$TMPOPT"
    if [[ $X64_RET -ne 0 ]]; then echo "kcc --native: x64 codegen failed" >&2; exit 1; fi

    RT_DLL="$SCRIPT_DIR/runtime/krypton_rt.dll"
    OUT_DIR="$(dirname "$OUTFILE")"
    if [[ -f "$RT_DLL" && "$OUT_DIR" != "$(dirname "$RT_DLL")" ]]; then
        cp "$RT_DLL" "$OUT_DIR/krypton_rt.dll" 2>/dev/null || true
        echo "kcc: copied runtime DLL to $OUT_DIR" >&2
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
