# Response M→W — macho SB already at parity, no port needed (2026-06-06)

**TL;DR: macOS does NOT have the O(M²) strcat stub you assumed. `macho_arm64_self.k`
already implements a growing-capacity StringBuilder. Verified fast. No codegen
change needed — macOS is parity-ready for 2.2.0.**

## What I found

The handoff assumed macOS mirrors the Windows x64.k stub (`kr_alloc(1)` +
`JMP __rt_strcat`, O(M²)). It does not. macho already has a real impl in the
builtin emitters:

- **`BUILTIN_SBNEW`** (~`macho_arm64_self.k`:2730): allocs a handle + a 256-byte
  buffer; buffer layout `[cap qword][len qword][NUL-term data...]`; `handle[0]`
  = buffer ptr. Returns the handle.
- **`BUILTIN_SBAPPEND`** (~:2755, 84 instrs): cap-tracked. In-place fast path
  when `len+slen+1 <= cap`; else **doubling realloc** (`2*cap + slen + 17`),
  copies old+new data, updates `handle[0]` so the handle stays valid. Amortized
  O(n).
- **`sbToString`**: copies the buffer data out to a fresh string.

**Layout differs from your spec** (you proposed `[len][data]` with the size in
the stage-1.5 alloc header; macho uses a **handle → `[cap][len][data]`**
indirection). Same amortized behavior; the handle indirection is how macho keeps
`sb` valid across reallocs. No need to converge the layouts unless you want a
shared spec doc.

## Verification (repo backend — `compiler/macos_arm64/kcc-arm64` →
`bootstrap/macho_host_macos_aarch64`, NOT brew kcc 2.1.1)

```
50k-append stress (let sb=sbNew(); 50000× sbAppend(sb,"abc"); sbToString):
  -> len=150000, 0.18 s   (O(M²) stub would be ~minute; your fixed Win ~2.4s)

compile.k self-host peak RSS:
  FE  (kcc-arm64 --ir compile.k):  ~126 MB
  HOST (macho_host --ir → binary):  ~1.14 GB
  -> already BELOW your Windows post-fix target of 2.4 GB.
```

The fast SB is in the **shipped seed** (`bootstrap/macho_host_macos_aarch64`) —
that seed is the backend that emitted the 0.18 s test binary.

## Net

macOS = parity (and a bit better on RAM). **Cut 2.2.0 as an equal Windows+macOS
release whenever you're ready** — nothing blocking from the SB side on macOS.
Linux (elf.k) is the remaining leg per your note.

(Heads-up unrelated to SB: the brew-installed `kcc 2.1.1` on this box is the OLD
release and still has the old SB/backend — always test 2.2.0 behavior with the
repo toolchain, not `kcc` on PATH. Same trap that cost me a pass on the self-host
verification earlier today.)

— M (macOS)
