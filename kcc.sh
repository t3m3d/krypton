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
  --ir         emit Krypton IR to stdout
  -o FILE      output path
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
    # Auto-detect macOS CPU arch (Apple Silicon arm64 vs Intel x86_64) so the
    # right backend/frontend is selected. Only arm64 ships today; x86_64 paths
    # are wired for when that backend exists (clear error until then).
    case "$(uname -m 2>/dev/null)" in
        arm64|aarch64) MACOS_ARCH=arm64 ;;
        x86_64|amd64)  MACOS_ARCH=x86_64 ;;
        *)             MACOS_ARCH=arm64 ;;
    esac
    # 2.1.1: point at the platform binary directly, NOT at a libexec/kcc
    # dispatcher (a stale libexec/kcc copy caused infinite recursion).
    KCC_EXE="$SCRIPT_DIR/compiler/macos_${MACOS_ARCH}/kcc-${MACOS_ARCH}"
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
EVAL_CODE=""
RUN_MODE=0
WASM_MODE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ir)      IRFLAG="--ir"; shift ;;
        --native)  NATIVE_MODE=1; shift ;;
        --llvm|--gcc|--c)
                   echo "kcc: $1 was removed (Krypton is C-free; native pipeline only)." >&2
                   exit 1 ;;
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
        # Only arm64 has a Mach-O backend today. x86_64 macOS isn't built yet —
        # fail clearly rather than mis-compile.
        if [[ "$MACOS_ARCH" != "arm64" ]]; then
            echo "kcc --native: macOS $MACOS_ARCH has no native backend yet (only arm64 is built)." >&2
            echo "kcc --native: build/run on Apple Silicon, or use --gcc for the C path." >&2
            exit 1
        fi
        MACHO_DIR="$SCRIPT_DIR/compiler/macos_arm64"
        MACHO_BIN="$MACHO_DIR/macho_host"
        MACHO_SRC="$MACHO_DIR/macho_arm64_self.k"
        MACHO_SEED="$SCRIPT_DIR/bootstrap/macho_host_macos_aarch64"

        # Prefer the prebuilt seed — NO clang at user-invocation time (mirrors
        # the Linux elf_host seed path). Native self-rebuild is the goal but the
        # macho_arm64_self.k self-host has a GC runaway on large input (hangs
        # past ~3k IR lines), so end users get the seed and never touch clang.
        # clang is the last resort, only when the seed is missing/stale (i.e. a
        # backend editor changed macho_arm64_self.k); the seed `! -nt` test (not
        # the strict `-nt`) survives git clone, where mtimes are equal.
        if [[ ! -f "$MACHO_BIN" || "$MACHO_SRC" -nt "$MACHO_BIN" ]]; then
            if [[ -f "$MACHO_SEED" && ! "$MACHO_SRC" -nt "$MACHO_SEED" ]]; then
                cp "$MACHO_SEED" "$MACHO_BIN"
                chmod +x "$MACHO_BIN"
            else
                CC_HOST="${CC:-clang}"
                command -v "$CC_HOST" >/dev/null || {
                    echo "kcc --native: no current macho_host seed for macos_aarch64 and $CC_HOST not found" >&2
                    echo "kcc --native: macho_arm64_self.k changed — regenerate the seed once (see bootstrap/), then kcc is clang-free" >&2
                    exit 1
                }
                echo "kcc: rebuilding macho host (one-time clang bootstrap; goal is to drop this once self-host bug is fixed)..." >&2
                "$KCC_EXE" "$MACHO_SRC" > /tmp/_kcc_macho_build.c && \
                "$CC_HOST" /tmp/_kcc_macho_build.c -o "$MACHO_BIN" $LIBS && rm -f /tmp/_kcc_macho_build.c
                if [[ $? -ne 0 ]]; then echo "kcc --native: failed to build macho host" >&2; exit 1; fi
                # refresh the seed so subsequent builds (and a commit) are clang-free
                cp "$MACHO_BIN" "$MACHO_SEED" && chmod +x "$MACHO_SEED"
            fi
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

        # Rebuild elf_host with NO C compiler:
        #   - seed current      -> cp the prebuilt native seed (user path)
        #   - elf.k edited       -> self-host: the seed elf_host compiles the
        #                           edited elf.k's IR into a fresh elf_host.
        # elf.k self-hosts to a byte-for-byte fixpoint; the gcc bootstrap is gone.
        if [[ ! -f "$ELF_BIN" || "$ELF_SRC" -nt "$ELF_BIN" ]]; then
            if [[ -f "$ELF_SEED" && ! "$ELF_SRC" -nt "$ELF_SEED" ]]; then
                cp "$ELF_SEED" "$ELF_BIN"
                chmod +x "$ELF_BIN"
            else
                ELF_BOOT="$ELF_SEED"; [[ -x "$ELF_BOOT" ]] || ELF_BOOT="$ELF_BIN"
                if [[ ! -x "$ELF_BOOT" ]]; then
                    echo "kcc --native: no elf_host seed to self-host from for ${PLATFORM}_${_ARCH}" >&2
                    exit 1
                fi
                echo "kcc: rebuilding elf host natively (self-host, no C — slow on elf.k)..." >&2
                _elfir="/tmp/_kcc_elf_self_$$.kir"
                "$KCC_EXE" --ir $HEADERS_FLAG "$ELF_SRC" > "$_elfir" || { echo "kcc --native: IR emit for elf.k failed" >&2; rm -f "$_elfir"; exit 1; }
                "$ELF_BOOT" "$_elfir" "$ELF_BIN"
                if [[ $? -ne 0 || ! -s "$ELF_BIN" ]]; then echo "kcc --native: native elf self-host failed" >&2; rm -f "$_elfir"; exit 1; fi
                chmod +x "$ELF_BIN"; rm -f "$_elfir"
            fi
        fi

        # optimize_host is best-effort; if rebuild fails we skip optimization
        # silently rather than blocking the build. No C compiler.
        if [[ ! -f "$OPT_BIN" || "$OPT_SRC" -nt "$OPT_BIN" ]]; then
            if [[ -f "$OPT_SEED" && ! "$OPT_SRC" -nt "$OPT_SEED" ]]; then
                cp "$OPT_SEED" "$OPT_BIN"
                chmod +x "$OPT_BIN"
            elif [[ -x "$ELF_BIN" ]]; then
                echo "kcc: rebuilding optimize host natively (self-host, no C)..." >&2
                _optir="/tmp/_kcc_opt_self_$$.kir"
                if "$KCC_EXE" --ir $HEADERS_FLAG "$OPT_SRC" > "$_optir"; then
                    "$ELF_BIN" "$_optir" "$OPT_BIN" && chmod +x "$OPT_BIN"
                fi
                rm -f "$_optir"
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

# --llvm / --c blocks deleted 2026-06-04 — Krypton is C-free; --llvm and --c
# were removed as flags above. Default path: derive output name, exec --native.
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

# Krypton is C-free; --gcc was removed at flag-parse time. Always re-exec as
# --native (by absolute path, not "$0": a bare `bash kcc.sh` would PATH-lookup
# a different installed copy with the wrong SCRIPT_DIR).
NATIVE_MODE=1
exec "$SCRIPT_DIR/kcc.sh" --native -o "$OUTFILE" "$SRCFILE"
