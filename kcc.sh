#!/usr/bin/env bash
# kcc — Krypton compiler driver.
#
# Usage: kcc source.k [-o output] [--native | --llvm | --c | --ir | -e | -r]
#
# Default (no flag): native binary. Pipeline = elf.k (Linux), x64.k (Windows),
# macho_arm64_self.k (macOS). NO C compiler at user-invocation time on any
# of those platforms — that's the project goal.
#
# Flags:
#   --native  explicit native pipeline (same as default)
#   --c       emit C source (debug aid)
#   --llvm    emit LLVM IR
#   --ir      emit Krypton IR (.kir) to stdout
#   -e CODE   compile + run + delete an inline snippet (like python -c)
#   -r FILE   compile + run + delete; remaining args pass through to FILE
#
# DEPRECATED — DO NOT REINTRODUCE NEW USES:
#   --gcc     C+gcc/clang fallback. Krypton's goal is no C-language tools in
#             operations. Flag stays only until every native pipeline is
#             verified stable. If native fails, file a bug — don't fall back.

# Resolve through symlinks so /usr/local/bin/kcc.sh → repo/kcc.sh finds repo files.
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
    SDIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$SDIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

# 2.1.1: short-circuit --version / -v / -h / --help BEFORE we route to
# the native pipeline. Without this, --version becomes SRCFILE="--version"
# and the wrapper kicks off the full compile, which hangs on a file that
# doesn't exist.
case "$1" in
    --version|-v)
        echo "kcc version 2.2.0"
        exit 0
        ;;
    -h|--help)
        cat <<EOF
kcc — Krypton compiler driver (2.2.0)

Usage: kcc <source.k|source.ks> [flags]

  Krypton 2.2 introduces .ks (KryptScript) as a sibling extension.
  .k  = library / compiled program (module foo, no shebang)
  .ks = script (just run + #!/usr/bin/env kr, runnable directly)
  Same compiler, same syntax — purely a naming convention.

  --native     (default) emit native binary at ./<basename>
  --c          emit C source to stdout
  --llvm       emit LLVM IR to stdout
  --ir         emit Krypton IR to stdout
  -o FILE      output path (with --native or --c)
  -r FILE      compile, run, delete (like python file.py)
  -e CODE      compile + run an inline snippet (like python -c)
  --version    print version
  --help       this help

Bundled CLIs: kcc, krypton (alias), kweb (web framework).
Site: https://krypton-lang.org
EOF
        exit 0
        ;;
esac

# 2.1.1: expose install root to kcc via env var. compile.k's import
# resolver reads $KRYPTON_ROOT and falls back to /usr/local/krypton on
# POSIX or C:\krypton on Windows. Homebrew + tarball installs land
# stdlib/ + headers/ next to this script, so SCRIPT_DIR IS the root.
if [[ -z "$KRYPTON_ROOT" ]]; then
    export KRYPTON_ROOT="$SCRIPT_DIR"
fi

case "$(uname -s 2>/dev/null)" in
    Linux*)  PLATFORM=linux ;;
    Darwin*) PLATFORM=macos ;;
    *)       PLATFORM=windows ;;
esac

if [[ "$PLATFORM" == "macos" ]]; then
    # 2.1.1: point at the platform binary directly, NOT at a libexec/kcc
    # dispatcher. The 2.0.0 tarball shipped a 1.4KB dispatcher script at
    # libexec/kcc; the 2.1.1 repo accidentally has a 15.5KB stale copy of
    # kcc.sh at the same path, which causes infinite recursion.
    KCC_EXE="$SCRIPT_DIR/compiler/macos_arm64/kcc-arm64"
    KCC_HEADERS="$SCRIPT_DIR/headers"
elif [[ "$PLATFORM" == "linux" ]]; then
    KCC_EXE="$SCRIPT_DIR/compiler/linux_x86/kcc-x64"
    if [[ "$(uname -m 2>/dev/null)" == "aarch64" || "$(uname -m 2>/dev/null)" == "arm64" ]]; then
        KCC_EXE="$SCRIPT_DIR/compiler/linux_arm64/kcc-linux-arm64"
    fi
    KCC_HEADERS="$SCRIPT_DIR/headers"
else
    KCC_EXE="$SCRIPT_DIR/kcc.exe"
    KCC_HEADERS_UNIX="$SCRIPT_DIR/headers"
    KCC_HEADERS="$(echo "$KCC_HEADERS_UNIX" | sed 's|^/\([a-zA-Z]\)/|\1:/|')"
fi

# C compiler lookup: $CC > gcc > clang > common Windows MinGW paths. Only used
# during the one-time bootstrap of native hosts, never on user invocation.
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
GCC_EXPLICIT=0  # --gcc explicitly passed (vs implicit macOS fallback)
C_MODE=0
EVAL_CODE=""
RUN_MODE=0
WASM_MODE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ir)      IRFLAG="--ir"; shift ;;
        --native)  NATIVE_MODE=1; shift ;;
        --llvm)    LLVM_MODE=1; shift ;;
        --gcc)     GCC_MODE=1; GCC_EXPLICIT=1; shift ;;
        --c)       C_MODE=1; shift ;;
        --wasm)    WASM_MODE=1; shift ;;
        -o)        OUTFILE="$2"; shift 2 ;;
        -e)        EVAL_CODE="$2"; shift 2 ;;
        -r)        RUN_MODE=1; shift
                   # -r consumes the next arg as SRCFILE and everything after
                   # as script args (python script.py arg1 arg2 semantics).
                   SRCFILE="$1"; shift
                   SCRIPT_ARGS=("$@")
                   set --
                   ;;
        -l*|-L*|-W*) LIBS="$LIBS $1"; shift ;;
        *)         SRCFILE="$1"; shift ;;
    esac
done

# -e: wrap snippet in `just run { ... }`, recurse via -o, run, clean up.
if [[ -n "$EVAL_CODE" ]]; then
    _KCC_EVAL_TMPK="/tmp/_kcc_eval_$$.k"
    _KCC_EVAL_TMPEXE="/tmp/_kcc_eval_$$"
    if [[ "$PLATFORM" == "windows" ]]; then
        _KCC_EVAL_TMPEXE="${_KCC_EVAL_TMPEXE}.exe"
    fi
    printf 'just run {\n%s\n}\n' "$EVAL_CODE" > "$_KCC_EVAL_TMPK"
    _KCC_LOG="/tmp/_kcc_eval_${$}_log"
    "$SCRIPT_DIR/kcc.sh" -o "$_KCC_EVAL_TMPEXE" "$_KCC_EVAL_TMPK" >"$_KCC_LOG" 2>&1
    _KCC_RC=$?
    if [[ $_KCC_RC -eq 0 ]]; then
        "$_KCC_EVAL_TMPEXE"
        _KCC_RC=$?
    else
        cat "$_KCC_LOG" >&2
    fi
    rm -f "$_KCC_EVAL_TMPK" "$_KCC_EVAL_TMPEXE" "$_KCC_LOG"
    exit $_KCC_RC
fi

if [[ -z "$SRCFILE" ]]; then
    echo "kcc: no input file" >&2; exit 1
fi

# -r: same recursion as -e but with an on-disk SRCFILE and arg passthrough.
# Pair with `#!/usr/bin/env kr` to make .k files chmod +x'd executable.
if [[ $RUN_MODE -eq 1 ]]; then
    _KCC_RUN_TMP="/tmp/_kcc_run_$$"
    if [[ "$PLATFORM" == "windows" ]]; then
        _KCC_RUN_TMP="${_KCC_RUN_TMP}.exe"
    fi
    _KCC_LOG="/tmp/_kcc_run_${$}_log"
    "$SCRIPT_DIR/kcc.sh" -o "$_KCC_RUN_TMP" "$SRCFILE" >"$_KCC_LOG" 2>&1
    _KCC_RC=$?
    if [[ $_KCC_RC -eq 0 ]]; then
        "$_KCC_RUN_TMP" "${SCRIPT_ARGS[@]}"
        _KCC_RC=$?
    else
        cat "$_KCC_LOG" >&2
    fi
    rm -f "$_KCC_RUN_TMP" "$_KCC_LOG"
    exit $_KCC_RC
fi

# --headers flag was removed in 1.8.4; install root fixed at C:\krypton.
# Keep $HEADERS_FLAG empty so the existing call sites stay no-ops.
HEADERS_FLAG=""

# --ir alone: emit IR to stdout.
if [[ -n "$IRFLAG" && -z "$OUTFILE" ]]; then
    "$KCC_EXE" --ir $HEADERS_FLAG "$SRCFILE"
    exit $?
fi

# --native pipeline by platform:
#   Linux:   .k → kir → elf.k → ELF (no gcc, no libc)
#   Windows: .k → kir → optimize → x64.k → PE (no gcc; needs krypton_rt.dll)
#   macOS:   .k → kir → macho_arm64_self.k → Mach-O (no clang/as/ld/codesign;
#            self-emits load commands + ad-hoc SHA-256 signature)
if [[ $NATIVE_MODE -eq 1 ]]; then
    if [[ -z "$OUTFILE" ]]; then
        # 2.2: strip .ks before .k so KryptScript source `foo.ks` becomes
        # `foo`/`foo.exe`, not `foo.ks.exe`. Order matters — bash %.k won't
        # match a .ks tail, so the .ks branch must come first.
        case "$SRCFILE" in
            *.ks) _kcc_base="${SRCFILE%.ks}" ;;
            *.k)  _kcc_base="${SRCFILE%.k}" ;;
            *)    _kcc_base="$SRCFILE" ;;
        esac
        if [[ "$PLATFORM" == "linux" || "$PLATFORM" == "macos" ]]; then
            OUTFILE="$_kcc_base"
        else
            OUTFILE="$_kcc_base.exe"
        fi
    fi
    TMPIR="/tmp/_kcc_native_$$.kir"

    if [[ "$PLATFORM" == "macos" ]]; then
        MACHO_DIR="$SCRIPT_DIR/compiler/macos_arm64"
        MACHO_BIN="$MACHO_DIR/macho_host"
        MACHO_SRC="$MACHO_DIR/macho_arm64_self.k"

        # One-time gcc/clang bootstrap of macho host. Goal: replace this with
        # a self-rebuild once macho_arm64_self.k is fully self-host.
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
        LINUX_DIR="$SCRIPT_DIR/compiler/linux_x86"
        ELF_BIN="$LINUX_DIR/elf_host"
        OPT_BIN="$LINUX_DIR/optimize_host"
        ELF_SRC="$LINUX_DIR/elf.k"
        OPT_SRC="$SCRIPT_DIR/compiler/optimize.k"

        case "$(uname -m 2>/dev/null)" in
            x86_64|amd64) _ARCH=x86_64 ;;
            aarch64|arm64) _ARCH=aarch64 ;;
            *) _ARCH=$(uname -m) ;;
        esac
        ELF_SEED="$SCRIPT_DIR/bootstrap/elf_host_${PLATFORM}_${_ARCH}"
        OPT_SEED="$SCRIPT_DIR/bootstrap/optimize_host_${PLATFORM}_${_ARCH}"

        # Rebuild elf_host. Native rebuild is the goal but blocked by the
        # elf.k self-host bug at >66 funcs (bootstrap/REBUILD_SEED.md). Until
        # that lands, fall back to a one-shot gcc bootstrap for elf.k editors;
        # end users with a prebuilt seed never hit this path.
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

        # optimize_host is best-effort; if rebuild fails we skip optimization
        # silently rather than blocking the build.
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

        "$KCC_EXE" --ir $HEADERS_FLAG "$SRCFILE" > "$TMPIR"
        if [[ $? -ne 0 ]]; then echo "kcc --native: IR emission failed" >&2; rm -f "$TMPIR"; exit 1; fi

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

    # Windows: PE/COFF backend.
    TMPOPT="/tmp/_kcc_native_opt_$$.kir"
    WIN_DIR="$SCRIPT_DIR/compiler/windows_x86"
    OPT_BIN="$WIN_DIR/optimize_host.exe"
    X64_BIN="$WIN_DIR/x64_host.exe"
    X64_SRC="$WIN_DIR/x64.k"
    OPT_SRC="$SCRIPT_DIR/compiler/optimize.k"
    OPT_SEED="$SCRIPT_DIR/bootstrap/optimize_host_windows_x86_64.exe"
    X64_SEED="$SCRIPT_DIR/bootstrap/x64_host_windows_x86_64.exe"

    # One-time gcc bootstrap (same situation as Linux above). Goal: route
    # this through the native pipeline once x64.k self-host parity is verified.
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

# --llvm: .k → kir → optimize → LLVM IR
if [[ $LLVM_MODE -eq 1 ]]; then
    TMPIR="/tmp/_kcc_llvm_$$.kir"
    TMPOPT="/tmp/_kcc_llvm_opt_$$.kir"

    "$KCC_EXE" --ir $HEADERS_FLAG "$SRCFILE" > "$TMPIR"
    if [[ $? -ne 0 ]]; then echo "kcc --llvm: IR emission failed" >&2; rm -f "$TMPIR"; exit 1; fi

    "$KCC_EXE" "$SCRIPT_DIR/compiler/optimize.k" "$TMPIR" > "$TMPOPT"
    if [[ $? -ne 0 ]]; then echo "kcc --llvm: optimizer failed" >&2; rm -f "$TMPIR" "$TMPOPT"; exit 1; fi

    if [[ -n "$OUTFILE" ]]; then
        "$KCC_EXE" "$SCRIPT_DIR/compiler/llvm.k" "$TMPOPT" > "$OUTFILE"
    else
        "$KCC_EXE" "$SCRIPT_DIR/compiler/llvm.k" "$TMPOPT"
    fi
    RET=$?
    rm -f "$TMPIR" "$TMPOPT"
    exit $RET
fi

# --c (legacy): emit C source. Kept for porting/debugging only; native is the
# goal everywhere. Don't add new code paths that rely on this.
if [[ $C_MODE -eq 1 ]]; then
    if [[ -z "$OUTFILE" ]]; then
        "$KCC_EXE" $HEADERS_FLAG "$SRCFILE"
        exit $?
    else
        "$KCC_EXE" $HEADERS_FLAG "$SRCFILE" > "$OUTFILE"
        exit $?
    fi
fi

# Default path: derive output name, then re-exec as --native. Falls through
# to the gcc block below only when --gcc was passed explicitly.
if [[ -z "$OUTFILE" ]]; then
    # 2.2: strip .ks before .k (same rationale as the --native block above).
    case "$SRCFILE" in
        *.ks) _kcc_base="${SRCFILE%.ks}" ;;
        *.k)  _kcc_base="${SRCFILE%.k}" ;;
        *)    _kcc_base="$SRCFILE" ;;
    esac
    if [[ "$PLATFORM" == "linux" || "$PLATFORM" == "macos" ]]; then
        OUTFILE="$_kcc_base"
    else
        OUTFILE="$_kcc_base.exe"
    fi
fi

if [[ "$GCC_MODE" -ne 1 ]]; then
    NATIVE_MODE=1
    # Re-exec by absolute path, NOT "$0": when invoked as a bare `bash kcc.sh`,
    # `$0` is "kcc.sh" and exec would do a PATH lookup, re-dispatching to a
    # DIFFERENT installed copy (e.g. /usr/local/krypton/kcc.sh) with the wrong
    # SCRIPT_DIR/KRYPTON_ROOT — so imports resolve against the wrong stdlib.
    exec "$SCRIPT_DIR/kcc.sh" --native -o "$OUTFILE" "$SRCFILE"
fi

# ─── C+gcc/clang path — DEPRECATED ─────────────────────────────────────────
# Reached only when --gcc was passed explicitly. The goal is to remove this
# block entirely once all platforms' native pipelines are verified stable:
#   - Linux:   elf.k self-host bug at >66 funcs (bootstrap/REBUILD_SEED.md)
#   - Windows: x64.k self-host parity unverified
#   - macOS:   macho_arm64_self.k covers only the core surface
# Do NOT introduce new callers of this path. If native fails, fix native.
if [[ "$GCC_EXPLICIT" -eq 1 ]]; then
    echo "kcc: warning: --gcc is deprecated; native is the default and goal." >&2
    echo "kcc: see bootstrap/REBUILD_SEED.md for the path to gcc-free." >&2
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
