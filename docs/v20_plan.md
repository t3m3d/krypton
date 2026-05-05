# Krypton 2.0 — Plan

Status: **draft, not committed to.** This document sketches the shape of a
2.0 release and defends an order. Items here are candidates only; nothing
here ships until the user signs off.

Primary tension Krypton hits in 1.x: the bump-only arena. Every string
concat allocates fresh; nothing is ever reclaimed. The compiler is a
giant string-concatenation pipeline, so a long compile or a malformed
input file pins arbitrary RAM (one kcc.exe was observed at 50 GB during
1.6.1 development on a malformed import). For programs that *aren't* the
compiler — servers, agents, the LSP we want to ship — the same issue
makes them unrunnable past a few hundred thousand operations.

So the 2.0 theme is **long-running programs become viable.** Everything
in this doc either feeds that theme (GC, concurrency, lambdas) or
benefits from it (LSP, package manager).

---

## Recommended scope for 2.0

| # | Item | Status | Why now |
|---|------|--------|---------|
| 1 | **GC** (mark-sweep) | Largest item | Unblocks every other 2.0 candidate |
| 2 | **C-style low-level memory** | Medium | Krypton as a systems language |
| 3 | **Lambdas in native pipeline** | Medium | Idiomatic stdlib (`map`, `filter`, etc.) |
| 4 | **Concurrency** (`go` + channels) | Medium-large | `go` keyword already reserved |
| 5 | **ARM64 Linux backend** | Medium | Parity with macOS arm64 |
| 6 | **LSP server** | Medium | Editor support |

Deferred to 2.1+:

- Package manager (`kpm`)
- Quantum backend (the original vision, but no concrete demand yet)

---

## 1. GC (the centerpiece)

### Current state

- Bump-only arena via `HeapAlloc` (Windows native) / `mmap` slabs (Linux ELF).
- Every `kr_plus`, every `sbAppend`, every `__rt_strdup` allocates fresh.
- Nothing is ever freed until process exit.
- The DLL ABI returns `char*` pointers everywhere — callers retain references
  with no GC barriers.

### Three-tier fix

This already exists as a plan in [`project_memory_leak_fix.md`](../README.md);
2.0 promotes it to formal status:

**Tier 1 — StringBuilder refactor in x64.k and compile.k.**
Replace `h = h + hexByte(...)` / `h = h + hexDword(...)` chains with
`sbNew` / `sbAppend` / `sbToString`. Already-available builtins, source-only,
no ABI change. Targets the exact hot path that produced the 50 GB blowup.
Estimated: 1-2 sessions.

**Tier 2 — Arena allocator with epoch reset.**
Replace per-string `HeapAlloc` with 64 MB slabs. Add `kr_epoch_begin` /
`kr_epoch_end` so the compiler can mark "everything from this scope is
discardable" and reclaim slabs in bulk. No tracing, no reachability — just
scope-bound bulk free. Catches the long tail Tier 1 misses.
Estimated: 2-3 sessions.

**Tier 3 — Real GC (mark-sweep).**
Track every allocation in a global linked list. Provide `kr_gc_collect`
that walks roots from a shadow stack the compiler maintains. Sweep on
allocation threshold (e.g., 2× live size after last collect).
Estimated: 5-8 sessions.

### Tier-3 design choice: shadow stack vs. conservative scan

- **Shadow stack** (recommended): the compiler emits push/pop of every
  Krypton-typed local at scope entry/exit. GC roots are exactly that
  stack. Precise, simple to reason about, no false retention.
  Cost: ~2 instructions per local at function entry/exit.
- **Conservative scan**: walk the actual machine stack and treat every
  qword that looks like a heap pointer as a root. Zero compiler cost,
  but retains garbage proportional to stack depth and may pin huge
  allocations because of an unrelated qword on the stack.

Krypton's smart-int convention (values < `0x40000000` are integers,
≥ are pointers) makes conservative scan tempting because the
"is this a pointer?" check is a single compare. But the same convention
means a Krypton integer like `0x40001234` (above 1 GiB) would be
*indistinguishable* from a pointer to a conservative scanner, and we
already document that boundary as a footgun. Shadow stack is the right
call.

### ABI impact

The DLL export signatures don't change — they still return `char*`.
What *does* change: callers can no longer assume the returned pointer
lives forever. Two options:

- **Caller-pinned**: callers must `kr_pin(ptr)` if they want to retain
  a result across a potential GC point. Forgetting to pin is a
  use-after-free. Maximally efficient, maximally unsafe.
- **Allocator handoff** (recommended): every `kr_*` that returns a
  pointer also pushes that pointer onto the current shadow-stack frame
  before returning. Caller pops on scope exit. Compiler emits this
  automatically; user code never sees it. Cost: one extra qword push
  per return.

The allocator-handoff path is what makes Krypton-the-language and
Krypton-the-runtime stay decoupled. User code still feels manual-free.

### Migration order

Backends adopt GC one at a time so we can roll back individually:

1. **Linux ELF** first — most ergonomic to debug (gdb, valgrind), and
   the smaller backend.
2. **Windows native** second — has the ABI through the DLL, so the
   handoff plumbing is more invasive.
3. **macOS arm64** third — Mach-O codesign means every byte of code
   change re-signs; want to do it last when GC is stable.

C path (`--c`) inherits whatever the host C runtime does, which is
`malloc`/`free` via `_K_EMPTY` — so the C path effectively already has
"GC" in the form of process exit. No changes needed; it's a no-op
target.

---

## 2. C-style low-level memory and hardware

Goal: programs that need C-level control over RAM, byte layout, and
hardware can express it directly in Krypton — without dropping into
`cfunc { }` blocks. Currently Krypton has the *primitives* but the
ergonomics are clunky (everything is "smart-int strings", pointers
masquerade as ints, no compile-time layout).

### Already shipped (1.x)

- `bufNew(size)` / `bufStr(buf)` — raw heap buffer, byte-addressable
- `bufGet/SetByte`, `bufGet/SetWord`, `bufGet/SetDword`, `bufGet/SetQword`
  with `*At(off, val)` variants — typed access at arbitrary offsets
- `rawAlloc(n)` / `rawFree(ptr)` / `rawRealloc(ptr, n)` — raw heap, no
  arena/GC tracking (escapes Krypton's lifetime story)
- `ptrAdd(ptr, n)`, `ptrToInt(ptr)`, `ptrDeref(ptr)`, `ptrIndex(ptr, n)`
  — pointer arithmetic
- `rawReadByte/Word/Qword(ptr, off)`, `rawWriteWord/Qword(...)` —
  direct memory access at arbitrary virtual addresses
- `structNew(typename)` — typed struct allocation matching Win32 ABI
  for known struct types (`SYSTEM_INFO`, `PROCESSENTRY32`, etc.)
- `callPtr1..4(fn, args)` — call a function pointer (e.g. from
  `GetProcAddress` or a Win32 callback)

So the building blocks exist. What 2.0 adds is a coherent *language-level*
story so user programs don't feel like they're calling intrinsics.

### What 2.0 adds

**Pointer types in the language.** Today every value is a string
pointer in disguise. 2.0 adds typed pointers:

```krypton
let p: *u8 = rawAlloc(1024)   // typed raw pointer
let x: *Vec3 = ptrCast(p)     // reinterpret as struct pointer
x.y = 4.5                     // direct field write, no buf*
```

The compiler tracks type at use sites and emits the right load/store
width — no manual `bufSetDword(buf, off, val)` for plain field access.
String types stay as today (smart-int convention) for compatibility;
the typed-pointer layer is opt-in via a type annotation.

**Stack allocation.** A `let local Vec3 v` declaration allocates on the
function's stack frame, no heap traffic, no GC root. Goes away on
function exit. Useful for short-lived structs in tight loops.

```krypton
func dot(a: *Vec3, b: *Vec3) -> int {
    let local Vec3 t                          // stack
    t.x = a.x * b.x
    t.y = a.y * b.y
    t.z = a.z * b.z
    emit t.x + t.y + t.z
}
```

**Inline byte/bit slices** for protocol parsing:

```krypton
let header: *u8 = recvBuf
let magic: u32 = read_be32(header)            // big-endian dword
let len:   u16 = read_le16(header + 4)        // little-endian word
```

`read_be32` / `read_le16` etc. ship as builtins that compile to direct
load + bswap on x86_64.

**Inline assembly** (limited, escape hatch):

```krypton
asm {
    rdtsc                                     // read time-stamp counter
    shl rdx, 32
    or  rax, rdx                              // RAX now holds 64-bit TSC
}
```

Restricted form — no full assembler, just a curated set of useful
instructions (`rdtsc`, `cpuid`, `pause`, atomics). Anything more
complex stays in `cfunc { }` or a syscall.

**Memory-mapped I/O** — `mmapFile(path)` returns a `*u8` whose lifetime
the runtime tracks. Reads happen on page-fault, no `readFile` copy
into the heap. Critical for the LSP (it should not load entire files
into the GC heap just to tokenize them).

**Direct syscalls / ports.** Linux ELF backend already does this;
expose it to user code as `syscall(num, a0, a1, ...)`. On Windows,
expose `inb` / `outb` for kernel-mode-style hardware access (gated
behind admin and a user-explicit `import unsafe.hardware`).

### Interaction with GC

Typed pointers and stack-allocated values are **outside** the GC heap.
The compiler enforces this: a typed pointer must come from `rawAlloc`,
`mmapFile`, a `local` declaration, or a foreign call — never from a
GC-tracked allocation. Going the other way (passing a typed pointer
where a GC string is expected) requires an explicit `gcCopy(ptr, n)`
that materialises a GC string from raw bytes.

This split is what makes the language feel like C *in the parts where
you want C* and like a managed language *in the parts where you don't*.
You opt into the pain by using the typed-pointer features.

### Estimated effort

3-5 sessions, mostly in the parser (type annotations, `local`
keyword, `asm` blocks) and the codegen (direct load/store at typed
offsets, stack-frame layout for local structs). Inline assembly and
mmap are platform-specific; ship them backend-by-backend like GC.

---

## 3. Lambdas in native pipeline

### Current state

C path supports lambdas via lifted helpers (`_krlamN` static functions
in the emitted C). Native pipeline does not — `func` expressions in
non-statement position are silently miscompiled or rejected.

### Plan

The C path's lifting strategy is portable: at IR generation time, scan
for `func`-expressions, compile each as a top-level function `_krlam<n>`,
and replace the expression with a function-pointer-to-`_krlam<n>`.
Free-variable capture via static cells (one per free var per lambda) —
matches what the C path already does. Closures-with-environments are a
2.1 problem.

Estimated: 1-2 sessions. Mostly ports the existing C-path logic into
`compile.k`'s IR-emission branch.

---

## 4. Concurrency primitives

### Current state

`go` keyword is reserved (reserved in tokenizer, no syntax). No threads,
no scheduler.

### Plan

Two layers:

- **Layer A: `go` blocks.** Single-threaded green threads via
  `setjmp`/`longjmp` (Linux/macOS) or fibers (Windows). Cooperative
  yields at allocation points. No real parallelism but enables
  generators, coroutines, async I/O patterns.
- **Layer B: channels.** `chan := make_chan()`, `chan <- val`,
  `val := <-chan`. Buffered + unbuffered. Built on top of the green
  thread scheduler.

Both layers depend on GC being in place — green threads each need a
shadow stack and the GC has to walk all of them on collection.

Estimated: 3-4 sessions on top of GC.

---

## 5. ARM64 Linux backend

### Current state

- Linux x86_64: `compiler/linux_x86/elf.k`
- macOS arm64: `compiler/macos_arm64/macho_arm64_self.k`
- Linux ARM64: falls back to C path

### Plan

`compiler/linux_arm64/elf_arm64.k` modeled on the x86_64 version's
ELF emission, with macOS arm64's instruction encoding. The two
existing backends already cover both halves of what's needed; this is
mostly assembly.

Estimated: 3-4 sessions.

---

## 6. LSP server

Standalone Krypton program speaking JSON-RPC over stdio. Reuses
`compile.k`'s `tokenize` and `scanFunctions` (after `tokenize` is
exposed as a runtime function — see roadmap.md's 1.6 item, may already
be done by 2.0).

Hard dependency on **GC** (long-running process), and benefits from
**concurrency** (handle requests without blocking on slow analyses).

Estimated: 4-6 sessions.

---

## Sequencing

```
GC Tier 1 (StringBuilder)     — first commit toward 2.0  [STARTED]
       ↓
GC Tier 2 (Arena epochs)      — 2.0-alpha-1
       ↓
GC Tier 3 (Mark-sweep, ELF)   — 2.0-alpha-2
       ↓
GC Tier 3 (Windows + macOS)   — 2.0-alpha-3
       ↓                ↘                  ↘
Typed-ptr / local /     Lambdas         ARM64 Linux       — 2.0-beta-1
asm / mmap              in native       backend             (parallel)
       ↓                ↙                  ↙
Concurrency primitives                           — 2.0-beta-2
       ↓
LSP server                                       — 2.0-rc-1
       ↓
2.0.0 ships
```

The C-style memory layer can run in parallel with lambdas and ARM64
once GC is stable on at least one platform — the pieces touch
different parts of the codegen.

The two GC alpha-3 work items (Windows, macOS) can happen in either
order; the parallel work item only depends on GC alpha-3 being done on
*at least one* platform.

---

## Versioning policy

- **2.0.0** is a hard ABI break. The DLL export signatures stay
  source-compatible (still `char*`-returning), but callers built
  against 1.x cannot link against the 2.0 runtime — the shadow-stack
  handoff means the entry/exit conventions differ.
- **1.7+** stays open as a compatibility branch. Bug fixes to 1.6
  semantics ship there. No new features; users who want new features
  upgrade to 2.0.
- **Migration tool**: a `kcc --port-1to2 source.k` flag that flags
  patterns that need attention (manual lifetime tracking via
  `bufNew`, raw pointer arithmetic). Most user code needs nothing.

---

## What to do first

**Tier 1 of the GC plan: StringBuilder refactor in `compiler/windows_x86/x64.k`
and `compiler/compile.k`.** Source-only, no ABI change, no DLL rebuild,
no breakage risk if reviewed carefully. Directly fixes the class of
bug that produced the 50 GB blowup. Prerequisite for everything else
in 2.0.

### Tier 1 progress (2026-05-04)

- [x] `hexStrIR` — per-character hot path (8 concat sites)
- [x] `emitStringTable` — per-string outer loop
- [x] `buildExportTable` — EAT, NPT, OT, nameStrs, dir
- [x] `buildImportTable` — main descriptor + assembly chain (~14 concat sites)
- [x] `buildBootstrapImportTable` — descriptor + assembly chain
- [ ] Smaller chains in the bootstrap section (per-instruction `sb2 = sbAppend(...)` is already correct in `emitBootstrapHelpers`; only string-build chains in setup remain)

Smoke test after each round: fibonacci compiles to byte-identical PE
output and runs cleanly. No DLL rebuild needed (refactor is in
codegen, not runtime).

**Tier 1 essentially complete on x64.k.** Remaining work: scan
`compiler/compile.k` for the same patterns (`grep` reported 0 hits
for `var = var + hex...` but the same problem can show up as
`s = s + str` style chains in the C-emit path). That's a separate
audit pass.
