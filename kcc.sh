#!/usr/bin/env bash
# kcc - Krypton compiler driver
#
# Usage: kcc source.k [-o output] [--native | --llvm | --c | --ir]
#
# DEFAULT (no flag, no -o):  produce a native binary at ./<basename>
# DEFAULT (no flag, with -o): produce a native binary at <output>
#   The native pipeline is elf.k → ELF on Linux, x64.k → PE/COFF on Windows,
#   macho_arm64_self.k → Mach-O on macOS arm64. NO C compiler involved at
#   user-invocation time on any of those platforms.
#
# --native:  explicit native pipeline (same as default)
# --c:       emit C source — to stdout if no -o, to <output> if -o (debug aid)
# --llvm:    emit LLVM IR — to stdout if no -o, to <output> if -o
# --ir:      emit Krypton IR (.kir) to stdout
#
# DEPRECATED:
# --gcc:     C+gcc/clang fallback. Krypton's stated goal is no C-language
#            tools in operations. This flag will be removed once every
#            platform's native pipeline is verified stable. Don't use it
#            for new work; if native fails, file a bug.

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
        # macOS arm64: compiler/macos_arm64/macho_arm64_self.k writes a
        # signed Mach-O directly (load commands, __TEXT/__DATA/__LINKEDIT,
        # chained fixups, ad-hoc SHA-256 code signature — all in Krypton).
        # NO clang, no `as`, no `ld`, no external codesign.
        MACHO_DIR="$SCRIPT_DIR/compiler/macos_arm64"
        MACHO_BIN="$MACHO_DIR/macho_host"
        MACHO_SRC="$MACHO_DIR/macho_arm64_self.k"

        # Build macho host if missing or stale (one-time bootstrap; uses kcc
        # itself + the host C compiler that built kcc). Subsequent runs reuse
        # the binary directly.
        if [[ ! -f "$MACHO_BIN" || "$MACHO_SRC" -nt "$MACHO_BIN" ]]; then
            CC_HOST="${CC:-clang}"
            command -v "$CC_HOST" >/dev/null || {
                echo "kcc --native: $CC_HOST not found (need a C compiler once to build the macho host)" >&2
                exit 1
            }
            echo "kcc: building macho host..." >&2
            "$KCC_EXE" "$MACHO_SRC" > /tmp/_kcc_macho_build.c && \
            "$CC_HOST" /tmp/_kcc_macho_build.c -o "$MACHO_BIN" $LIBS && rm -f /tmp/_kcc_macho_build.c
            if [[ $? -ne 0 ]]; then echo "kcc --native: failed to build macho host" >&2; exit 1; fi
        fi

        "$KCC_EXE" --ir $HEADERS_FLAG "$SRCFILE" > "$TMPIR"
        if [[ $? -ne 0 ]]; then echo "kcc --native: IR emission failed" >&2; rm -f "$TMPIR"; exit 1; fi

        "$MACHO_BIN" --ir "$TMPIR" "$OUTFILE"
        MACHO_RET=$?
        rm -f "$TMPIR"
        if [[ $MACHO_RET -ne 0 ]]; then echo "kcc --native: macho codegen failed" >&2; exit 1; fi
        chmod +x "$OUTFILE"
        exit 0
    fi

    if [[ "$PLATFORM" == "linux" ]]; then
        # Linux: .k → kir → optimize.k → kir' → elf.k → ELF
        LINUX_DIR="$SCRIPT_DIR/compiler/linux_x86"
        ELF_BIN="$LINUX_DIR/elf_host"
        OPT_BIN="$LINUX_DIR/optimize_host"
        ELF_SRC="$LINUX_DIR/elf.k"
        OPT_SRC="$SCRIPT_DIR/compiler/optimize.k"   # shared source

        # Detect arch for prebuilt seed lookup
        case "$(uname -m 2>/dev/null)" in
            x86_64|amd64) _ARCH=x86_64 ;;
            aarch64|arm64) _ARCH=aarch64 ;;
            *) _ARCH=$(uname -m) ;;
        esac
        ELF_SEED="$SCRIPT_DIR/bootstrap/elf_host_${PLATFORM}_${_ARCH}"
        OPT_SEED="$SCRIPT_DIR/bootstrap/optimize_host_${PLATFORM}_${_ARCH}"

        # Build / restore elf_host
        # Native rebuild path (preferred): use existing elf_host (or seed) to
        # compile the new elf.k via the .k → .kir → ELF pipeline. Currently
        # blocked by elf.k-self-host bug at >66 funcs (see REBUILD_SEED.md);
        # until that's fixed, the gcc rebuild stays as a one-time bootstrap
        # for users who edit elf.k. End users with prebuilt seeds never hit it.
        if [[ ! -f "$ELF_BIN" || "$ELF_SRC" -nt "$ELF_BIN" ]]; then
            if [[ -f "$ELF_SEED" && "$ELF_SEED" -nt "$ELF_SRC" ]]; then
                cp "$ELF_SEED" "$ELF_BIN"
                chmod +x "$ELF_BIN"
            else
                if [[ -z "$GCC_EXE" || ! -x "$(command -v "$GCC_EXE" 2>/dev/null)$GCC_EXE" ]] && ! command -v "$GCC_EXE" >/dev/null 2>&1; then
                    echo "kcc --native: no prebuilt elf_host seed for ${PLATFORM}_${_ARCH} and no gcc found" >&2
                    echo "kcc --native: stale elf.k requires rebuild — run on a Linux box with gcc once, see bootstrap/REBUILD_SEED.md" >&2
                    exit 1
                fi
                echo "kcc: rebuilding elf host (one-time gcc bootstrap; goal is to drop this once self-host bug is fixed)..." >&2
                "$KCC_EXE" "$ELF_SRC" > /tmp/_kcc_elf_build.c && \
                "$GCC_EXE" /tmp/_kcc_elf_build.c -o "$ELF_BIN" $LIBS && rm -f /tmp/_kcc_elf_build.c
                if [[ $? -ne 0 ]]; then echo "kcc --native: failed to build elf codegen" >&2; exit 1; fi
            fi
        fi

        # Build / restore optimize_host (best-effort — if it fails to build we
        # fall through to skip-optimize mode rather than blocking the build).
        # Same one-time-gcc situation as elf_host above.
        if [[ ! -f "$OPT_BIN" || "$OPT_SRC" -nt "$OPT_BIN" ]]; then
            if [[ -f "$OPT_SEED" && "$OPT_SEED" -nt "$OPT_SRC" ]]; then
                cp "$OPT_SEED" "$OPT_BIN"
                chmod +x "$OPT_BIN"
            elif command -v "$GCC_EXE" >/dev/null 2>&1; then
                echo "kcc: rebuilding optimize host (one-time gcc bootstrap)..." >&2
                "$KCC_EXE" "$OPT_SRC" > /tmp/_kcc_opt_build.c && \
                "$GCC_EXE" /tmp/_kcc_opt_build.c -o "$OPT_BIN" $LIBS && rm -f /tmp/_kcc_opt_build.c
            fi
        fi

        # Generate IR
        "$KCC_EXE" --ir $HEADERS_FLAG "$SRCFILE" > "$TMPIR"
        if [[ $? -ne 0 ]]; then echo "kcc --native: IR emission failed" >&2; rm -f "$TMPIR"; exit 1; fi

        # Optimize (skip silently if host not available)
        if [[ -x "$OPT_BIN" ]]; then
            TMPOPT="/tmp/_kcc_native_opt_$$.kir"
            "$OPT_BIN" "$TMPIR" > "$TMPOPT" 2>/dev/null
            if [[ -s "$TMPOPT" ]]; then
                mv "$TMPOPT" "$TMPIR"
            else
                rm -f "$TMPOPT"
            fi
        fi

        "$ELF_BIN" "$TMPIR" "$OUTFILE"
        ELF_RET=$?
        rm -f "$TMPIR"
        if [[ $ELF_RET -ne 0 ]]; then echo "kcc --native: elf codegen failed" >&2; exit 1; fi
        chmod +x "$OUTFILE"
        exit 0
    fi

    # Windows: PE/COFF backend
    TMPOPT="/tmp/_kcc_native_opt_$$.kir"
    WIN_DIR="$SCRIPT_DIR/compiler/windows_x86"
    OPT_BIN="$WIN_DIR/optimize_host.exe"
    X64_BIN="$WIN_DIR/x64_host.exe"
    X64_SRC="$WIN_DIR/x64.k"
    OPT_SRC="$SCRIPT_DIR/compiler/optimize.k"   # shared source
    OPT_SEED="$SCRIPT_DIR/bootstrap/optimize_host_windows_x86_64.exe"
    X64_SEED="$SCRIPT_DIR/bootstrap/x64_host_windows_x86_64.exe"

    # One-time gcc bootstrap (Windows side). Same situation as Linux: end
    # users with prebuilt seeds don't hit this; only triggered if you edit
    # x64.k or optimize.k. Goal is to drop these by routing rebuild through
    # the native pipeline once x64.k self-host parity is verified.
    if [[ ! -f "$OPT_BIN" || "$OPT_SRC" -nt "$OPT_BIN" ]]; then
        if [[ -f "$OPT_SEED" && "$OPT_SEED" -nt "$OPT_SRC" ]]; then
            cp "$OPT_SEED" "$OPT_BIN"
        else
            echo "kcc: rebuilding optimize host (one-time gcc bootstrap)..." >&2
            "$KCC_EXE" "$OPT_SRC" > /tmp/_kcc_opt_build.c && \
            "$GCC_EXE" /tmp/_kcc_opt_build.c -o "$OPT_BIN" $LIBS && rm -f /tmp/_kcc_opt_build.c
            if [[ $? -ne 0 ]]; then echo "kcc --native: failed to build optimizer" >&2; exit 1; fi
        fi
    fi
    if [[ ! -f "$X64_BIN" || "$X64_SRC" -nt "$X64_BIN" ]]; then
        if [[ -f "$X64_SEED" && "$X64_SEED" -nt "$X64_SRC" ]]; then
            cp "$X64_SEED" "$X64_BIN"
        else
            echo "kcc: rebuilding x64 host (one-time gcc bootstrap)..." >&2
            "$KCC_EXE" "$X64_SRC" > /tmp/_kcc_x64_build.c && \
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

    "$KCC_EXE" "$SCRIPT_DIR/compiler/optimize.k" "$TMPIR" > "$TMPOPT"
    if [[ $? -ne 0 ]]; then echo "kcc --llvm: optimizer failed" >&2; rm -f "$TMPIR" "$TMPOPT"; exit 1; fi

    # Emit LLVM IR
    if [[ -n "$OUTFILE" ]]; then
        "$KCC_EXE" "$SCRIPT_DIR/compiler/llvm.k" "$TMPOPT" > "$OUTFILE"
    else
        "$KCC_EXE" "$SCRIPT_DIR/compiler/llvm.k" "$TMPOPT"
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

# ──────────────────────────────────────────────────────────────────────────
# DEPRECATED: --gcc path. Krypton's stated goal is no C-language tools in
# operations. Native is the default. This branch only runs when the user
# explicitly opts in with --gcc and is kept temporarily for emergency
# fallback while we close out the remaining native-pipeline gaps:
#   - Linux:   elf.k self-host bug at >66 funcs (bug #3 in REBUILD_SEED.md)
#   - Windows: x64.k self-host parity not yet verified
#   - macOS:   macho_arm64_self.k handles all builtins arm64 supports
# Once each platform's native rebuild path replaces gcc in kcc.sh's lazy
# host-rebuild block, --gcc gets removed entirely.
# ──────────────────────────────────────────────────────────────────────────
echo "kcc: warning: --gcc is deprecated; native is the default and goal." >&2
echo "kcc: see bootstrap/REBUILD_SEED.md for the path to gcc-free." >&2
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
