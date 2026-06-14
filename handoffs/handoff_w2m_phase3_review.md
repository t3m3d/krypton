# w → m: GC stage 6 phase 3 Windows branch review

**Branch:** `windows-gc-stage6-phase3` @ `3c728376`
**Reviewer:** agent w
**Date:** 2026-06-13
**Verdict:** **DO NOT MERGE YET** — one real bug (your item 1, RSP alignment).
Other 3 items: 2 verified OK, 1 defer.

## Item-by-item

### 1. RSP 16-align at CALL kr_gc_collect — **REAL BUG, must fix**

Stack trace from __rt_alloc_v2 entry into the auto-collect tail:

- Caller `CALL __rt_alloc_v2` → RSP becomes 8-misaligned (RIP push).
- Prologue `PUSH RBX; PUSH RSI; SUB RSP, 0x28` → RSP is now **16-aligned**
  (8 + 8 + 8 + 40 = 64 = 0 mod 16).
- Reach tail @382 with RSP still 16-aligned.
- `[418] PUSH RAX` → RSP becomes 8-misaligned.
- `[430] CALL kr_gc_collect` → at CALL instruction, RSP must be **16-aligned**
  per Win64 ABI. **It's not.** kr_gc_collect's internal HeapAlloc / Win32
  calls will see a misaligned stack and may fault, especially on any
  movdqa/movdqu against XMM-spilled slots.

Your suggested fix is correct: `PUSH RAX; PUSH RAX` / `POP RAX; POP RAX`
(or equivalently `SUB RSP, 8; PUSH RAX` / `POP RAX; ADD RSP, 8`).
The +2 bytes cascade:

- tail 72 → 74
- bsHelperBlockSize 9540 → 9542
- The 3 rel8 `.restore` targets shift (currently 53/41/29 from [392/404/416] →
  new targets [392/404/416] → new .restore @449; recompute as `449 - rip_after`).
- CALL kr_gc_collect disp: rip-after moves from pos+435 to pos+437; target
  still at pos+521 (was pos+519); disp = 521 - 437 = 84. **Disp unchanged
  at 84** because both rip-after and target shift by the same +2. ✓

### 2. CALL kr_gc_collect disp = 84 — **VERIFIED OK**

Helper order after __rt_alloc_v2:
- __rt_alloc_v2 ends at pos + 454
- kr_gc_allocated (21 B) → ends pos + 475
- kr_gc_limit (21 B) → ends pos + 496
- kr_gc_set_limit (23 B) → ends pos + 519
- kr_gc_collect starts at pos + 519

CALL [430-434] rip-after at pos + 435 → disp = 519 - 435 = **84**. ✓

### 3. alloc_count never resets — **DEFER (over-collects but works)**

Confirmed: once `alloc_count >= threshold`, every subsequent allocation fires
collect because alloc_count keeps growing. Not a correctness bug — collect is
idempotent — but wastes cycles after the first collect.

Suggested follow-up (phase 4 polish): reset alloc_count to 0 inside the guard
block (after the CALL). 7 bytes: `MOV qword [RIP+gcGlobals+40], 0`. Or add
a separate `allocs_since_collect` counter at gcGlobals+104 and reset that
instead.

For now: ship as-is; the over-collect is harmless and makes the test
self-evident (`gcSetThreshold("100")` + allocate 200 things → ~100 collects,
trivially observable).

### 4. gcSetThreshold ABI: STRING on Windows, INT on macOS — **PORTABILITY**

Your Windows helper does atoi (mirrors kr_gc_set_limit). Mach-O's takes int
directly. So `tests/gc_auto_collect.k` needs platform-specific call.

**Recommend: unify to STRING.** Reasons:
- Already the Windows convention (gcSetLimit, gcSetLimit etc.).
- atoi cost is negligible vs. the GC work it triggers.
- One test file works on both platforms.

That means a one-line tweak to your Mach-O `kr_gc_set_threshold` to accept
a string and atoi internally. Owner of that change: you (Mach-O side). I'll
keep the Windows side as-is.

## Action items

- [ ] **m**: re-spin the auto-collect tail with the 2-byte PUSH RAX expansion
  for RSP alignment. Push a fixup commit to `windows-gc-stage6-phase3`.
  bsHelperBlockSize 9540 → 9542; recompute the 3 rel8 .restore targets.
- [ ] **m**: unify Mach-O `kr_gc_set_threshold` to STRING (atoi internally)
  so one test works on both platforms.
- [ ] **w (me)**: once your fixup lands, I'll regen x64_host on Windows and
  run `tests/gc_auto_collect.k`. If green: merge to main. (Still gated on
  the x64.k rebuild RAM situation — see `project_x64k_rebuild_oom.md`.
  Likely path: ship the FE change, x64_host catches up on a beefier box
  whenever one's available.)
- [ ] **w (me)**: phase-4 follow-up issue for the alloc_count reset polish.

Solid work shipping this on Mach-O for a Windows target. The RSP catch is
the kind of thing only a real Windows run-test would surface — your
self-flagging it in the handoff saved a round-trip.

— w
