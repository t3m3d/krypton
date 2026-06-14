# w → wine: kcc.exe smoke under wine-on-arm

**From:** agent w (Windows-native)
**To:** agent wine (arm + wine + x86 translation)
**Date:** 2026-06-13
**Status:** waiting on wine install to finish; pick this up when ready

---

## What this is

You're the 4th agent on Krypton (after w / m / l). Your platform is **arm hardware running wine
with x86 translation** (FEX-Emu, box64, or wine's own emulation). The goal long-term is to validate
that Krypton's PE binaries run under wine — and eventually that we have an arm-windows backend
(m is the likely owner of that, since they already have Mach-O arm64).

For now: **just smoke-test that the existing Windows toolchain runs**. No code changes from you yet.

## Setup checklist (after wine install completes)

```bash
# 1. Confirm wine + x86 translation works at all
wine --version
wine cmd.exe /c "echo hello from wine"

# 2. Pull the repo (read-only is fine)
git clone https://github.com/t3m3d/krypton.git  # or whatever Brian's URL is
cd krypton

# 3. Drop the runtime DLL where the PE loader will find it
# kcc.exe needs krypton_rt.dll next to it OR on PATH
ls -la kcc.exe runtime/krypton_rt.dll
```

## Three smoke gates

### Gate 1 — kcc.exe runs at all

```bash
wine ./kcc.exe --version 2>&1
# expect: version string, rc=0
```

If this fails with IAT/missing-DLL errors, wine is missing one of:
- `ws2_32.dll` (sockets — used by stdlib/net)
- `comctl32.dll` / `user32.dll` (GUI — used even by CLI builds at init)
- `kernel32.dll` (everything)

Most wine installs have these. If not, install `winetricks` and pull the relevant
component. Don't patch the binary — that's our problem on the FE side.

### Gate 2 — interpret a Krypton script

```bash
cat > /tmp/hello.k <<'EOF'
just run {
    print("hello from " + "wine")
    let n = 0
    while n < 5 {
        print("count=" + n)
        n = n + 1
    }
}
EOF
wine ./kcc.exe -r /tmp/hello.k
# expect: "hello from wine" + 5 count lines, rc=0
```

This proves the interpreter path (run.k) works end-to-end through wine's x86
translation layer. If output is garbled or truncated, capture the exact bytes
(`wine ./kcc.exe -r /tmp/hello.k | xxd | head -20`) — that's a charset issue, not
your bug to fix.

### Gate 3 — native PE compile + run a self-contained binary

```bash
wine ./kcc.exe /tmp/hello.k -o /tmp/hello.exe
ls -la /tmp/hello.exe
wine /tmp/hello.exe
# expect: same output as Gate 2, rc=0
```

This is the big one. It exercises the full pipeline: kcc reads source, generates
x64 machine code, writes PE, links against krypton_rt.dll, then wine loads the
resulting PE. If any step fails, **which step** is the useful signal.

## What to report back

Write `handoffs/handoff_wine2w_smoke_results.md` with:

- `wine --version` output
- For each gate: pass / fail + exact output (or first ~30 lines of error)
- Total wall-clock for `kcc /tmp/hello.k -o /tmp/hello.exe` (sanity check that
  translation overhead isn't catastrophic — if it's >30s for a 10-line script,
  that's a wine-perf issue not Krypton's)

## What NOT to do (yet)

- **Don't touch any source file.** Cross-platform changes need w/m/l coordination
  first. Your job this round is observation, not patching.
- **Don't run `kcc compiler/x64.k`** — that's the self-host build, eats 25-35 GB
  of RAM, will OOM-kill wine and probably your host. We rebuild that only on
  beefy boxes.
- **Don't commit anything** unless Brian explicitly asks. Default is "report,
  don't touch."

## If wine flat-out can't run PE

That's still useful — tells us we need a different translation layer (box64-style
direct), or that arm-windows-native is the only viable path. Either way, document
the exact failure mode and we can route from there.

## Why this matters

If the existing PE pipeline works under wine, that's a free arm-windows preview
for users (slow but functional). And it gives us a test platform to debug the
eventual native arm-windows backend against — comparing native arm64 output to
"x64 under translation" output catches whole classes of codegen bugs.

— w
