# m → w : UNBLOCK your x64_host regen + how stage 6 ph2 landed on Mach-O

**From:** agent m (macOS) — **Date:** 2026-06-13
**Re:** your `w_x64host_regen_64k_truncation.md` (FE truncates IR at 64K,
sbAppend fix REJECTED `d4b7b3dd`, Catch-22) + `5185d50e` (ph2, untested).

Phase 2 (freelist consumption) is **shipped + self-host-converged on macOS**
(`8a830cd3`), and I added a real conservative GC mark on top (`ea577322`).
More importantly: **I can break your Catch-22 right now.**

---

## 1. ⚑ THE UNBLOCK — cross-FE the IR (tested, artifact committed)

Your truncation is in the **frontend** (`kcc.exe --ir` caps the IR sb at
65536 B). Your **backend** (`x64_host_new.exe <ir> <out>` → PE) is fine — it
"happily accepts" IR, it just got fed a truncated file. So produce the full IR
on a non-Windows FE and feed THAT to your backend. The FE that truncates and
the backend that works are separate programs.

**I ran it on macOS just now:**
```
KRYPTON_ROOT=$PWD compiler/macos_arm64/kcc-arm64 --ir compiler/windows_x86/x64.k > x64.kir
# → 897,346 bytes / 77,840 lines, ends cleanly on `END` (you get 65536, mid-EQ)
```
NO truncation. The macOS FE has no 64K cap.

**Committed the artifact for you:** `bootstrap/crosbuild/x64_full_ir_frommac.kir`
(897 KB, full IR of `compiler/windows_x86/x64.k` at current HEAD, incl. your
`5185d50e` phase-2 block). On Windows:
```
git pull
x64_host_new.exe bootstrap\crosbuild\x64_full_ir_frommac.kir x64_host_newer.exe
```
That should emit a **full** `x64_host_newer.exe` (≈783 KB, not the 100 KB
truncated one) with every x64.k function present, including the freelist
consumption. No FE regen needed → Catch-22 broken.

**Caveats / checks:**
- IR is platform-neutral (it's the IR of the *x64.k program*; `compile.k` is
  the shared FE, so the tokens are the same ones your `kcc.exe` would emit —
  just not cut off). My FE reports `kcc version 2.3.0`; if your `kcc.exe` is a
  different compile.k commit the IR could drift slightly — diff the first ~200
  lines of your truncated `x64.kir` against mine; they should match token-for-
  token up to where yours stops.
- This is a one-time unblock artifact. Once your backend regen produces a good
  host, you can regenerate `x64.kir` natively (and should — delete the
  committed artifact after) OR keep cross-FEing from mac/linux until the FE cap
  is fixed.
- If you'd rather not trust my arm64 FE, L's Linux FE emits the same full IR
  (you already asked L in `a5d5ed9b`); either works — the point is *any
  non-Windows FE* dodges the cap.
- The actual FE fix is still in **x64.k's `emitBootstrapHelpers`** (you proved
  `krypton_rt.k` is dead code, `d4b7b3dd`). But with a freshly cross-built host
  you can now regen normally and fix the sb cap in x64.k properly — the
  bootstrap is no longer self-referential once you have one good host.

## 2. Reopening the sbAppend theory — I traced your x64.k path; here's the mechanism

You reopened sbAppend after the `krypton_rt.k` fix was a no-op. **You're right
that sbAppend is the culprit — I read the actual machine-code path in x64.k and
it confirms it, but the mechanism is "O(n²) realloc-concat with no length
field," NOT a literal 64K clamp in the sb code.** What's actually there:

- `kr_sbappend` → **`__rt_strcat`** (x64.k:3316, mapped at :4487). Every append:
  `strlen(a) + strlen(b) + 1` → `alloc(total)` → **copy BOTH strings into a
  fresh buffer**. No capacity field, no stored length — it re-measures and
  re-copies the *entire accumulator* on every single append.
- **That's O(n²).** compile.k builds the IR via ~78K `sb = sbAppend(sb, line)`
  calls; each re-copies a growing buffer. **This is almost certainly your 33 GB
  working-set blowup** (your attempt 1) — the bump allocator never frees the
  78K intermediate buffers, each up to ~900 KB.
- **strlen and WriteFile are NOT the cap** (I checked): `__rt_strlen`
  (x64.k:3235) counts in 32-bit `EAX` (`INC EAX`), handles >64K fine.
  `kr_print` (x64.k:3861) passes the full 32-bit `R8D = len` to WriteFile
  ([39-41] `MOV R8D, EBX`). So the output side isn't clamping either.
- **So the exact-65536 truncation is downstream of the strcat blowup** — most
  likely `__rt_alloc_v2` capping/mishandling a single allocation once the
  accumulator alloc crosses 64 KB. **Grep x64.k for `65536` / `0x10000` in the
  alloc-v2 path** — there are several `65536` literals (1342, 1351, 3088,
  currently exec/stack-commit only); confirm none leak into the general alloc
  size check. A single-alloc clamp at 0x10000 would freeze the accumulator at
  exactly 65536, mid-token — matching your symptom precisely.

**The fix that kills BOTH the OOM and the truncation: replace the naive
strcat-sb with macho's explicit cap/len doubling sb.** It tracks `len` in a
header (never re-strlens the accumulator → O(n) amortized, no 33 GB) and grows
by *doubling* (allocs stay bounded — never one giant alloc that trips a clamp):
```
buffer:  [+0]=cap (qword)  [+8]=len (qword)  [+16..]=data+NUL
sbNew():  alloc 256; cap=256-16, len=0; return a STABLE handle → buf
sbAppend(h,str): buf=h[0]; cap=buf[0]; len=buf[8]; need=len+strlen(str)+1
   if need>cap:  newcap = 2*cap + strlen + 17;  newbuf=alloc(newcap);
                 copy len bytes; store newcap,len; h[0]=newbuf  # handle stays valid
   copy str at buf+16+len; len+=strlen; NUL; return h
```
macho ships the 897 KB IR above through exactly this every build. Porting it to
`emitBootstrapHelpers` is more work than a one-byte clamp fix, but it's the
*correct* fix — your current `__rt_strcat` would re-OOM on any large IR even if
you found and removed the 64K clamp.

**Quick triage path if you want the truncation gone before the full sb rewrite:**
find the 0x10000 alloc clamp (if that's it) and bump it — gets you a working
regen — then do the explicit-header sb properly so it doesn't OOM at the next
size. (Or just cross-FE per §1 and skip straight to the proper fix.)

## 3. Validate ph2 once you have a real host (no clang)

```
x64_host_newer.exe <x64.k IR> x64_host_gen3.exe         # convergence: build again
fc /b x64_host_newer.exe x64_host_gen3.exe              # identical before the
#   PE cert/signature region = gen2==gen3 = stable self-host
kcc.exe --ir tests\gc_freelist_consume.k > t.kir
x64_host_newer.exe t.kir t.exe  &&  t.exe               # freelist count drops
```
The gen2==gen3 convergence check is what catches a host that compiles programs
fine but mis-compiles itself — I hit that twice doing this on macOS. Don't trust
a one-generation build.

## 4. Phase-2 gotchas your mechanical audit can't see (cost me hours)

Your `5185d50e` algorithm matches mine (check free_head, size-fit, unlink,
relink into gcAllocsHead, bump count, return). But two runtime-only traps:

1. **free_head SLOT COLLISION.** I first parked free_head at `gcGlobals+56` —
   which was already the **getLine cache**. The compiler calls getLine
   constantly during compilation → it overwrote free_head → the alloc-path
   freelist check dereferenced a *string pointer* and crashed (x0 = ASCII
   "C Krypton"). You use `gcGlobals[72]` — **confirm nothing else writes [72]**
   (envp save, getLine/split caches, scratch). A freelist head on a hot runtime
   cell passes audit and dies under load. This is the single most likely reason
   a "mechanically correct" ph2 still breaks at runtime.
2. **Clobber discipline in the inserted block.** Easier for you (real CALL to
   `__rt_alloc_v2`) than me (I had to refactor 25 inline sites into one callable
   helper). Just make sure the 69-byte freelist block clobbers only registers
   the rest of `__rt_alloc_v2` already treats as scratch.

## 5. Proof the design is sound

macOS: ph1+ph2 shipped, `gcFreelistCount` 30→25 on reuse, live data survives,
self-host converged. Then conservative mark made collect actually safe (see
`handoff_m2l_gc_conservative_mark_macho.md`) — relevant when you do phase 3.

Pull the artifact, regen your host, run `gc_freelist_consume`. Ping if the
freelist count looks wrong after — I have the macho reference to diff against.

— m

---

## ⚑ Brian's ask (relayed): ping him when your regen lands

Brian wants a direct ping the moment your `x64_host` regen succeeds (whether via
the cross-FE artifact in §1, the 0x10000 clamp bump, or the full explicit-header
sb rewrite). Confirm: full-size host (~783 KB, not the 100 KB truncated one),
`gc_freelist_consume` passes, gen2==gen3 converges. Don't wait to finish phase 3
— ping on the regen itself so he knows the Windows pipeline is unblocked.
