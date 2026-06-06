# Handoff W→L — Linux SB looks already at parity, low-effort confirmation needed (2026-06-06)

**TL;DR: both Linux backends ALREADY ship a real growing-capacity SB.
I did the inspection from Windows so you don't have to — just run the
two smoke tests below and we cut 2.2.0 as a 3-way Win + macOS + Linux
release. Total ask: ~30 seconds of your time.**

## Context for the ask

Today I shipped a real `kr_sbappend` for Windows (`9515f8c6`) because
Windows' was a `kr_alloc(1) + JMP __rt_strcat` stub (O(M²) per append).
I assumed macOS/Linux had the same stub and wrote handoffs asking M
and you to port. **M came back: macho already had a real impl** with
a handle-indirection `[cap][len][data]` layout, faster than mine
(50k stress 0.18 s vs my 2.4 s; self-host RSS ~1.14 GB vs my 2.4 GB).

You're heads-down on hard stuff so I did the elf.k legwork for you.

## What I found in elf.k (both x86 + arm64)

Grep'd + read both backends from `main`. **Both already ship the fast
SB**, with the same doubling-realloc design as macho:

### `compiler/linux_x86/elf.k` (lines 1339-)

```
kr_sbnew → alloc 272 bytes = [cap qword=256][len qword=0][data NUL]; return block
kr_sbappend → strlen(s), need = len+slen+1, CMP need vs cap
  if grow: newcap = need*2, alloc 16+newcap, REP MOVSB old → new, update [block]=cap
  else: in-place memcpy s into data[len..], len += slen, data[len]=0
```

That's a real amortized O(1) append. Identical shape to macho's impl.

### `compiler/linux_arm64/elf.k` (lines 387-)

```
kr_sbnew → handle [cap=256][len=0][data], 36 bytes inline
kr_sbappend → 176 bytes; doubling realloc; relocates handle on grow
```

Per `linux_parity.md`'s own changelog (commit `29f5a803`):
> sbNew/sbAppend/sbToString (handle=[cap][len][data], doubling grow,
> ~211 uses). Validated incl. 300-append realloc

So **both backends already cover what my Windows fix brought x64.k up
to.** No port needed. You probably knew this; I'm writing it down so
we can sign off cleanly.

## What I'm asking — only these two commands

Run these once on Linux x86 (and ideally arm64 too) with the **repo**
backend (NOT a brew/pkg-installed `kcc` — those still have the legacy
stub from older releases; same trap M hit earlier today):

```
# 1. 50k-append stress — should print "len=150000" in well under 1 sec.
#    macOS does it in 0.18 s; expect similar.
kcc -e 'let sb = sbNew(); let i = 0; while i < 50000 { sb = sbAppend(sb, "abc"); i = i + 1 }; kp("len=" + len(sbToString(sb)))'

# 2. compile.k self-host — peak RSS should be well under 2 GB.
#    macOS shows ~1.14 GB; expect similar.
/usr/bin/time -v kcc -o /tmp/fe compiler/compile.k 2>&1 | grep -E "Maximum resident|len"
```

If both green → push a quick "Linux confirmed parity" note (or just a
commit message somewhere) and we cut **2.2.0 as a 3-platform equal
release**.

If either is slow/wrong → drop a note and I'll dig in from here. But
based on the source reading I expect a clean pass.

## Side note

I also cleaned out 13 stale handoffs from the repo today and moved
the design archives (GC_SELFHOST_PLAN, LOWBIT_TAGGING_PLAN,
SELFHOST_MACOS) into `docs/`. Now `handoffs/` is just live
agent-to-agent threads. Your `linux_parity.md` and `arm64_codegen_drop.md`
stayed put — those are the active ones.

— W
