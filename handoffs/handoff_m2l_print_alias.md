# Handoff M → L: `print` as the newline print (kp = fallback) — macOS intel + de-risk

**Date:** 2026-06-12
**From:** Agent M (macOS)
**To:** Agent L — you're implementing `print` on the Linux end
**Repo:** krypton, `compiler/compile.k` (SHARED frontend → your one edit lands on macOS + Windows too)

## The ask (as Brian framed it)
`print(x)` becomes THE print function (with trailing newline, like `kp`). Keep `kp` working unchanged so existing programs don't break.

## Current state (verified on macOS, kcc 2.4.0)
- `print` ALREADY exists — it's the **no-newline** writer (`BUILTIN_PRINT`, 52 instrs).
- `kp` is the **newline** writer (`BUILTIN_KP`, 69 instrs).
- Frontend maps the names at `compile.k:~1690` (`bname == "kp" → BUILTIN_KP`) and `~1760` (`bname == "print" → BUILTIN_PRINT`).

## Cleanest implementation (no codegen/backend change → no drift risk)
Remap `print` to the existing, proven newline op in the frontend:
`compile.k:~1760` — `bname == "print"` emit **`BUILTIN_KP`** instead of `BUILTIN_PRINT`. One line. `kp` stays as-is. No `macho_arm64_self.k` / `elf.k` / `x64.k` edit needed; you're just pointing the name at a working op.

(Alternative if you prefer keeping the op name: make `BUILTIN_PRINT`'s emitter append the newline — but that's a per-backend codegen edit ×3 with instruction-count updates. The remap is strictly easier and reuses tested code. Recommend the remap.)

## The gotcha I chased down — and why it's NOT a blocker
The compiler emits its OWN IR via no-newline `print`: `compile.k:3218 print(irLibText)`, `3222`/`3373 print(sbToString(sb))`, `3369 print(irText)`. With `print`→newline, the emitted `.kir` gains ONE trailing `\n`.

**Verified on macOS this is harmless:**
- Each IR path does a SINGLE `print(wholeBlob)` then `emit 0` — so it's one trailing `\n`, not newlines splitting tokens.
- `macho_host --ir` tolerates a trailing newline in the `.kir` (tested: appended `\n`, still builds + runs `hi 5`).
- Self-host fixpoint compares gen1.kir vs gen2.kir — BOTH produced by the new `print`, so both carry the trailing `\n` → still byte-identical. Fixpoint stays green.

So you do **NOT** need to migrate those compiler sites to a raw writer. (If you want byte-exact `.kir` for some external tooling, switch the 4 sites to `fdWrite(1, s, len(s))` — but it's optional/cosmetic, don't let it block the change.)

## Division of labor from here
1. **You (L):** make the `compile.k` remap, rebuild the Linux FE + seeds, verify (`print("x")` newlines, `kp` unchanged, self-host fixpoint byte-identical, `build.sh test` still green). Push `compile.k`.
2. **M (me):** on your push, rebuild the macOS toolchain (`kcc-arm64`, `macho_host` unchanged), refresh `bootstrap/{kcc_seed,macho_host,kcc_driver}_macos_aarch64`, verify print/kp + fixpoint, commit the macOS seeds.
3. **W:** same for Windows (`x64.k` path; PE seeds).

Please **don't** expect me to also edit `compile.k` — one editor for the shared frontend avoids a conflict. Ping when pushed and I'll do the macOS leg. — M
