#!/usr/bin/env bash
# tests/smoke_2_1_features.sh — exercise the 2.1 Python-replacement features.
#
# Runs each new capability end-to-end and reports PASS / FAIL with a
# short summary line. Designed to be run from the krypton repo root on
# Windows under Git Bash (or any bash with the standard Win32 PATH).
#
#   bash tests/smoke_2_1_features.sh
#
# Exit code: 0 if all tests pass, 1 otherwise.

set -u

REPO="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# kcc.sh was removed (0c0dc57b); the driver is the compiled kcc.ks binary seed.
# Prefer the committed repo seed (tests THIS tree), else fall back to `kcc` on PATH.
case "$(uname -s 2>/dev/null)" in
    Darwin*) KCC="$REPO/bootstrap/kcc_driver_macos_aarch64" ;;
    *)       KCC="$REPO/bootstrap/kcc_driver_linux_x86_64" ;;
esac
if [[ ! -x "$KCC" ]]; then
    if command -v kcc >/dev/null 2>&1; then KCC="$(command -v kcc)"
    else echo "smoke: no kcc driver seed and no kcc on PATH" >&2; exit 1; fi
fi
PASS=0
FAIL=0
FAILED=()

step() {
    printf '  %s ... ' "$1"
}

ok() {
    PASS=$((PASS + 1))
    echo "OK"
}

bad() {
    FAIL=$((FAIL + 1))
    FAILED+=("$1")
    echo "FAIL"
    if [[ -n "${2:-}" ]]; then
        echo "      $2"
    fi
}

# 1. kcc -e one-liner
echo "[1/6] kcc -e one-liner"
step "kp + arithmetic"
out="$("$KCC" -e 'kp("sum=" + (1+2+3))' 2>&1)"
if [[ "$out" == "sum=6" ]]; then ok; else bad "kcc -e" "got: $out"; fi

step "multi-statement"
out="$("$KCC" -e 'let n = 0; let i = 1; while i <= 5 { n = n + i; i = i + 1 }; kp(n + "")' 2>&1)"
if [[ "$out" == "15" ]]; then ok; else bad "kcc -e multi" "got: $out"; fi

# 2. kcc -r run + arg passthrough
echo "[2/6] kcc -r run mode"
tmpk="/tmp/krsmoke_$$.k"
cat > "$tmpk" <<'KEOF'
#!/usr/bin/env kr
just run {
    kp("argc=" + argCount())
    if argCount() > 0 { kp("a0=" + arg("0")) }
}
KEOF
step "shebang ignored + no args"
out="$("$KCC" -r "$tmpk" 2>&1)"
if [[ "$out" == "argc=0" ]]; then ok; else bad "kcc -r no-args" "got: $out"; fi

step "args passed through"
out="$("$KCC" -r "$tmpk" hello 2>&1)"
expected="argc=1
a0=hello"
if [[ "$out" == "$expected" ]]; then ok; else bad "kcc -r args" "got: $out"; fi
rm -f "$tmpk"

# 3. fs ops round-trip
echo "[3/6] fs ops (mkdir/copy/rename/delete/rmdir/env paths)"
step "round-trip"
out="$("$KCC" -r "$REPO/tests/test_fs_extended.k" 2>&1)"
if [[ "$out" == "ok" ]]; then ok; else bad "fs round-trip" "got: $out"; fi

# 4. shellRun real exit code
echo "[4/6] shellRun exit code"
step "exit 0 / 7 / 42 round-trip"
out="$("$KCC" -r "$REPO/tests/test_shellrun_exit.k" 2>&1)"
expected="ok: 0
err: 7
err2: 42"
if [[ "$out" == "$expected" ]]; then ok; else bad "shellRun exit code" "got: $out"; fi

# 5. http (skip if no network)
echo "[5/6] http (curl-backed)"
if ! command -v curl >/dev/null 2>&1; then
    echo "  curl not on PATH — skipping http tests"
else
    step "GET status code"
    out="$("$KCC" -e 'import "k:http"; kp(httpStatus("https://httpbin.org/get"))' 2>&1)"
    if [[ "$out" == "200" ]]; then ok; else bad "httpStatus" "got: $out"; fi

    step "POST JSON"
    out="$("$KCC" -e 'import "k:http"; let r = httpPost("https://httpbin.org/post", "{\"x\":1}", "application/json"); kp(contains(r, "Content-Length") + "")' 2>&1)"
    if [[ "$out" == "1" ]]; then ok; else bad "httpPost" "got: $out"; fi
fi

# 6. settings — JSON load/save + tool resolution
echo "[6/6] settings (JSON config + findTool)"
step "round-trip"
out="$("$KCC" -r "$REPO/tests/test_settings.k" 2>&1)"
if [[ "$out" == "ok" ]]; then ok; else bad "settings" "got: $out"; fi

# Summary
echo ""
echo "──────────────────────────────────────────"
echo " smoke results: PASS=$PASS  FAIL=$FAIL"
echo "──────────────────────────────────────────"
if [[ $FAIL -gt 0 ]]; then
    echo " failed:"
    for f in "${FAILED[@]}"; do echo "   - $f"; done
    exit 1
fi
echo " all good — 2.1 features ready to use"
exit 0
