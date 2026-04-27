#!/usr/bin/env bash
# kcc - Krypton compiler driver
#
# Usage: kcc source.k [-o output] [--native | --gcc | --llvm | --c | --ir]
#
# DEFAULT (no flag, no -o):  produce a native binary at ./<basename>
# DEFAULT (no flag, with -o): produce a native binary at <output>
# --native:  explicit native pipeline (elf.k on Linux, x64.k on Windows;
#            macOS falls back to C+clang internally until Mach-O lands)
# --gcc:     force C+gcc/clang internally (still produces a native binary)
# --c:       emit C source — to stdout if no -o, to <output> if -o (legacy)
# --llvm:    emit LLVM IR — to stdout if no -o, to <output> if -o
# --ir:      emit Krypton IR (.kir) to stdout

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

# Find a C compiler. Prefer $CC env var, then gcc, then clang (macOS default).
GCC_EXE="${CC:-}"
if [[ -z "$GCC_EXE" ]]; then GCC_EXE="$(command -v gcc 2>/dev/null)"; fi
if [[ -z "$GCC_EXE" ]]; then GCC_EXE="$(command -v clang 2>/dev/null)"; fi
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
C_MODE=0       # --c: emit C source (legacy; default is native binary now)

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ir)      IRFLAG="--ir"; shift ;;
        --native)  NATIVE_MODE=1; shift ;;
        --llvm)    LLVM_MODE=1; shift ;;
        --gcc)     GCC_MODE=1; shift ;;
        --c)       C_MODE=1; shift ;;
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
# Linux:   .k → .kir → elf.k → ELF binary (no gcc, no libc)
# Windows: .k → .kir → optimize → x64.k → .exe (no gcc, needs krypton_rt.dll)
# macOS:   .k → .kir → macho.k → .s → clang → Mach-O (clang+ld required;
#                                                    AMFI on Tahoe forbids
#                                                    self-emitted Mach-O)
if [[ $NATIVE_MODE -eq 1 ]]; then
    if [[ -z "$OUTFILE" ]]; then
        if [[ "$PLATFORM" == "linux" || "$PLATFORM" == "macos" ]]; then
            OUTFILE="${SRCFILE%.k}"
        else
            OUTFILE="${SRCFILE%.k}.exe"
        fi
    fi
    TMPIR="/tmp/_kcc_native_$$.kir"

    if [[ "$PLATFORM" == "macos" ]]; then
        # macOS Mach-O backend via kompiler/macho.k → .s → clang
        MACHO_BIN="$SCRIPT_DIR/kompiler/macho_host"

        case "$(uname -m 2>/dev/null)" in
            x86_64|amd64) _MARCH=x86_64 ;;
            arm64|aarch64) _MARCH=arm64 ;;
            *) _MARCH=$(uname -m) ;;
        esac

        # Build macho host if missing or stale (uses host C compiler — clang
        # ships with Xcode CLT). No prebuilt seed since this is brand-new.
        if [[ ! -f "$MACHO_BIN" || "$SCRIPT_DIR/kompiler/macho.k" -nt "$MACHO_BIN" ]]; then
            CC_HOST="${CC:-clang}"
            command -v "$CC_HOST" >/dev/null || {
                echo "kcc --native: $CC_HOST not found (install Xcode Command Line Tools: xcode-select --install)" >&2
                exit 1
            }
            echo "kcc: building macho host..." >&2
            "$KCC_EXE" "$SCRIPT_DIR/kompiler/macho.k" > /tmp/_kcc_macho_build.c && \
            "$CC_HOST" /tmp/_kcc_macho_build.c -o "$MACHO_BIN" $LIBS && rm -f /tmp/_kcc_macho_build.c
            if [[ $? -ne 0 ]]; then echo "kcc --native: failed to build macho host" >&2; exit 1; fi
        fi

        TMPS="/tmp/_kcc_native_$$.s"
        "$KCC_EXE" --ir $HEADERS_FLAG "$SRCFILE" > "$TMPIR"
        if [[ $? -ne 0 ]]; then echo "kcc --native: IR emission failed" >&2; rm -f "$TMPIR"; exit 1; fi

        "$MACHO_BIN" --arch "$_MARCH" "$TMPIR" "$TMPS"
        if [[ $? -ne 0 ]]; then echo "kcc --native: macho codegen failed" >&2; rm -f "$TMPIR" "$TMPS"; exit 1; fi

        # clang assembles + links + signs in one step.
        clang -arch "$_MARCH" "$TMPS" -o "$OUTFILE"
        CLANG_RET=$?
        rm -f "$TMPIR" "$TMPS"
        if [[ $CLANG_RET -ne 0 ]]; then echo "kcc --native: clang link failed" >&2; exit 1; fi
        chmod +x "$OUTFILE"
        exit 0
    fi

    if [[ "$PLATFORM" == "linux" ]]; then
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

# ── --c (legacy): emit C source ──────────────────────────────────
# Without -o, prints to stdout. With -o, writes to file.
# Same as the old default behaviour of `kcc.sh foo.k`. Kept for users who
# still want C output (porting to other platforms, debugging codegen, etc.).
if [[ $C_MODE -eq 1 ]]; then
    if [[ -z "$OUTFILE" ]]; then
        "$KCC_EXE" $HEADERS_FLAG "$SRCFILE"
        exit $?
    else
        "$KCC_EXE" $HEADERS_FLAG "$SRCFILE" > "$OUTFILE"
        exit $?
    fi
fi

# ── Default: produce a native binary ─────────────────────────────
# No -o: derive output name from source basename (e.g. hello.k → hello on
#        Linux/macOS, hello.exe on Windows).
# Linux/Windows: native pipeline (elf.k / x64.k → ELF/PE, no gcc).
# macOS:         falls back to C+clang internally (Mach-O backend in progress).
# --gcc:         force C+gcc on any platform.
if [[ -z "$OUTFILE" ]]; then
    if [[ "$PLATFORM" == "linux" || "$PLATFORM" == "macos" ]]; then
        OUTFILE="${SRCFILE%.k}"
    else
        OUTFILE="${SRCFILE%.k}.exe"
    fi
fi

if [[ "$GCC_MODE" -ne 1 ]]; then
    NATIVE_MODE=1
    exec "$0" --native -o "$OUTFILE" "$SRCFILE"
fi

# C+gcc path — opt-in via --gcc on any platform.
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
