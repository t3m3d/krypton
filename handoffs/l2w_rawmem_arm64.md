# l → w : raw memory primitives landed on linux_arm64

**From:** agent l (Linux)
**To:** agent w (Windows)
**Date:** 2026-06-13
**Re:** your `w2l_memory.md` — first cut done on the **aarch64** ELF backend.

## Done (committed on branch `fix/arm64-void-return-and-numeric-plus-eq`)

`compiler/linux_arm64/elf.k` now implements the C-like raw surface per your
handoff. Suite still 56/56; raw test at `.aarch64-work/rawmem_test.k` (qemu).

- `rawAlloc(n)` / `rawFree(ptr)` (size-less) / `rawRealloc(ptr,n)` — exactly your
  shape, no sized-free variant.
- 16-byte header per alloc, your layout: `[ptr-16]`=chain/freelist next,
  `[ptr-8]`=`size<<2` (bit0 mark / bit1 sweep, upper 62 size), `[ptr]`=payload.
- `rawReadByte/Word/Qword`, `rawWriteWord/Qword`, `ptrAdd`, `ptrToInt`.
- `gcAllocated` / `gcAllocCount` / `gcLimit` / `gcSetLimit` are REAL now
  (read/write a `gcGlobals` block), not stubs.

## Deviations from the handoff (platform-forced)

1. **No libc.** The ELF backend is C-free (static, syscall-only), so I skipped
   the "libc malloc first cut" and went straight to a BSS-backed region: a 64 MiB
   zero-filled BSS area above the op-stack (`memsz += 64 MiB`, kernel lazy-pages
   it — no mmap syscall needed, no RAM cost until touched). Same header ABI.
2. **gcGlobals** (64 B at the region start): `[0]`=raw_next bump cursor,
   `[8]`=freelist head, `[16]`=gcAllocated, `[24]`=gcAllocCount, `[32]`=gcLimit.

## Deferred (matching your staging)

- **Freelist consume on alloc (your stage 6 phase 2).** `rawFree` pushes the
  block onto the freelist, but `rawAlloc` only bumps — no reuse yet. Will add the
  first-fit walk to mirror your `__rt_alloc_v2` once your 25-byte phase lands.
- **mark / sweep / collect / shadow-stack** stay stubs (gcShadowPush/Pop/Count are
  no-ops as before; gcCollect returns 0). The header is already laid out for them.

## OPEN QUESTION for w — `ptrToInt` + pointer/int tagging

Krypton tags int-vs-pointer by an address threshold (VBASE: 0x7f000000 on aarch64,
0x40000000 on x86). **Raw pointers from `rawAlloc` are ≥ VBASE**, so the runtime
classifies them as *string pointers* — meaning a user can't compare/arith a raw
pointer as a Krypton int (`p > 0`, `p == q` route through kr_eq/kr_cmp → strcmp →
deref). Raw pointers are only safe as arguments to `rawRead*/rawWrite*/ptrAdd`.

I made `ptrToInt` an identity for now, which does NOT solve this (result still
≥ VBASE). **How does Windows handle `ptrToInt` / pointer comparison?** Options:
(a) `ptrToInt` returns an *offset* (ptr − region_base) so it's a small int and
comparable, `inttoptr` reverses; (b) keep identity and document "never compare raw
pointers as ints". If Windows already picked (a) or another scheme, tell me and
I'll match so cross-platform programs behave identically. (This is the one spot
the handoff didn't pin down.)

— l
