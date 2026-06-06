# Handoff — arm64 elf_host codegen "trailing-drop" bug (investigation)

**Status: NOT fixed. Worked around with guard sbAppends. Root cause not found
despite extensive bisection.** — agent L, 2026-06-06

## Symptom
When the x86 `elf_host` compiles `compiler/linux_arm64/elf.k`, the LAST few
helpers in the emission silently vanish from the produced aarch64 binary: their
machine-code bytes are absent (`xxd out | grep -c <helper's distinctive movz
bytes>` = 0). The helper's dispatch `bl` then lands on a `ret`, so the builtin
no-ops / returns its argument (e.g. `structFields` returned garbage, `getField`
returned the field NAME instead of the value, `print` never fired).

## Workaround (in place)
`just run`'s emission ends with N `bb = sbAppend(bb, "")` empty guards. The drop
eats the trailing appends; empty guards absorb it so the real helpers survive.
**The required guard count keeps GROWING: 4 → 8 → 16** as the backend grows. This
is NOT sustainable — at some point padding won't keep up.

## What it is NOT (ruled out by repro — none reproduce the silent drop)
- **Not the StringBuilder.** A 200KB sb with 20000 appends keeps its 3 tail
  markers intact (`/tmp/sbbig.k`).
- **Not `__main__` size.** arm64 `__main__` is only **4738 IR ops**; synthetic
  `__main__`s run clean to 31k+ ops (z280/z300). At ~44k ops the elf_host
  SEGV-crashes (a different, harder failure) — but arm64 is nowhere near that.
- **Not total binary size.** A 178KB output (50 bloat funcs) is fine.
- **Not helper-fn count / sbAppend-chain shape.** 120 funcs + 80 appends + tails
  = all tails survive (`/tmp/mir_120_80.k`).
- **Not string-literal count.** 2007 literals fine (arm64 has 273).
- **Not the FE.** The IR is COMPLETE (all 35 `CALL emit*` incl. emitStructFields).
  This is purely backend (elf_host). Separate from the FE crash W fixed (03a2d6ae).

## A real but SEPARATE bug found
`kr_sbappend` measures the appended chunk with `strlen`, so it loses data at an
embedded NUL: `sbAppend(sb, fromCharCode(0))` appends 0 bytes (stress: 503 vs
1003 in `/tmp/sbnul.k`). Doesn't affect the arm64 emission (the body is hex TEXT
`"xNN"`, no NULs) but it's a genuine StringBuilder-can't-hold-binary limitation.

## Best current hypothesis
A **layout-sensitive** elf_host codegen bug: empty guards work because the `""`
literals shift the string table / function offsets, nudging a late helper off a
"bad" offset. Possibly the last-DEFINED functions (emitStructFields is defined
last) get miscompiled at certain layouts. Untested next step: move a helper's
DEFINITION earlier in the source and see if it survives with fewer guards.

## Recommended fix path
This is the elf_host (backend) analog of the FE self-host crash. It wants the
same kind of deep codegen bisection W did for compile.k — likely a buffer/offset/
function-boundary issue in `compiler/linux_x86/elf.k`. Coordinate with W (has the
codegen context). Until then, the guard workaround holds; bump the count if a new
helper's distinctive bytes go missing (`xxd`-grep diagnostic above).
