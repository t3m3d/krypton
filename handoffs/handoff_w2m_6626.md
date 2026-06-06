# Handoff W→M — port native StringBuilder to macho.k (2026-06-06)

**Goal:** macOS feature-parity with the Windows native SB shipped in
`9515f8c6`. macOS is #2 by everyday user share; we want the same
compile.k self-host RAM drop + sbAppend speedup over there before
cutting 2.2.0 as an equal-release across both platforms.

## What landed on Windows

`runtime/krypton_rt.k` got real `kr_sbnew/kr_sbappend/kr_sbtostring`
impls — replacing the legacy stub which was just `kr_alloc(1)` + a
`JMP __rt_strcat` (every append = fresh `sb + s` allocation, O(M²)
for M appends).

Result: 50k-append stress test ~2.4 sec, compile.k self-host peak
RAM 3-5 GB → 2.4 GB. Bigger the sb, bigger the win.

On Windows the runtime is loaded from `krypton_rt.dll`, so a single
Krypton-source edit suffices. **On macOS the runtime is inlined into
the FE binary via `compiler/macos_arm64/macho_arm64_self.k`**, so the
equivalent fix is **aarch64 codegen in the bootstrap-helper emitter**
— not a Krypton-source change.

## Algorithm to port

Layout per allocation:
```
[base + 0 .. base + 7]   length qword
[base + 8 .. base + N-1] NUL-terminated data
```
User-facing pointer is `base + 8` — a normal NUL-terminated C-string,
so `len(sb) / kp(sb) / sb + s` work unchanged on existing callers.

```
kr_sbnew():
  ptr = rawAlloc(64)        ; 64 raw bytes; 8 for length, 56 for data
  *(ptr+0..7) = 0           ; length = 0
  *(ptr+8)    = 0           ; NUL at data[0]
  return ptr + 8

kr_sbappend(sb, s):
  s_len = strlen(s)
  if s_len == 0: return sb
  base    = sb - 8
  cur_len = *(base+0..7)
  ; stage-1.5 alloc header is at [base-8..base-1]: size+flags qword.
  ; Low 2 bits = mark/reserved. Capacity = (size & ~3) - 16 alloc - 8 length.
  alloc_size = *(base-8..base-1) & ~3
  data_cap   = alloc_size - 24
  needed     = cur_len + s_len
  if needed + 1 > data_cap:
    new_total = max(64, 2 * (needed + 1) + 8)
    new_base  = rawAlloc(new_total)
    *(new_base+0..7) = needed
    memcpy(new_base+8,          sb,           cur_len)
    memcpy(new_base+8+cur_len,  s,            s_len)
    *(new_base+8+needed) = 0
    return new_base + 8
  ; in-place
  memcpy(base+8+cur_len, s, s_len)
  *(base+8+needed)  = 0
  *(base+0..7)      = needed
  return sb

kr_sbtostring(sb):
  ; Returns a NEW copy (same semantics as the old strdup-based impl),
  ; so subsequent sbAppend mutations don't reach back into the caller's
  ; cached string.
  cur_len = *(sb-8..sb-1)
  dst     = rawAlloc(cur_len + 1)
  memcpy(dst, sb, cur_len)
  *(dst+cur_len) = 0
  return dst
```

## Where in macho.k it lives

Mirror the x64.k pattern — find the existing `kr_sbnew/kr_sbappend/
kr_sbtostring` inline emitters (in x64.k:4389 it's a 22-byte stub for
sbnew + 5-byte `JMP __rt_strcat` thunks for sbappend/sbtostring).
Replace those stubs in `macho_arm64_self.k`'s bootstrap-helper block
with full aarch64 impls of the algorithm above.

Verify the stage-1.5 alloc header layout matches on macOS — if macho
uses a different inflation factor or flag-bit layout for the GC
header, adapt the `alloc_size & ~3` mask accordingly.

## Verification

```
# Stress test — old impl took ~minute, new should be ~2 sec
kcc -e 'let sb = sbNew(); let i = 0; while i < 50000 { sb = sbAppend(sb, "abc"); i = i + 1 }; let s = sbToString(sb); kp("len=" + len(s))'
# Expected: len=150000, ~2 sec

# compile.k self-host RAM drop — should land near Windows
kcc -o /tmp/fe compiler/compile.k
# Expected peak ~2.4 GB (was 3-5 GB)
```

## Coordination

Once macho is ported, we can cut **2.2.0 as a true equal release across
Windows + macOS**. Linux is the third leg — L can use the same algorithm
applied to `compiler/linux_x86/elf.k` for x86, plus the arm64 variant.

Window: my Windows shipment in `runtime/krypton_rt.k` is on `main`
already (`9515f8c6`). Pull, look at that file as the reference, port,
push back. No coordination needed beyond "tell me when it's in" so I
can run a final cross-platform sanity check.

— W
