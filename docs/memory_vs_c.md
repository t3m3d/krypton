# Krypton Memory Management vs. C

Krypton 1.8.0 ships a memory model that's deliberately better than C's
`malloc` / `free` for the workloads Krypton is actually used for —
compilers, system tools, fetch programs, anything that allocates a lot
of small strings and runs in scopes.

This page contrasts the two head-to-head and shows the patterns Krypton
makes available.

---

## Side-by-side

| Concern | C | Krypton 1.8.0 (Windows native) |
|---|---|---|
| **Allocation API** | `malloc(n)` per call, system heap | Bump-allocate from a 64 MB slab via `__rt_alloc`. New slab linked into chain on overflow. |
| **Per-allocation cost** | malloc internal bookkeeping (~16-32 bytes overhead, locking) | 8-byte alignment round, bump pointer, write `ADD [RIP+slab_off], n`. ~3 instructions in the fast path. |
| **Free** | `free(ptr)` per allocation, easy to miss, easy to double-free | `gcReset()` or `gcRestore(token)` reclaim a whole region in O(slab-count). No per-allocation free needed. |
| **Tracking total bytes allocated** | Not provided; must integrate `mtrace`, jemalloc, or similar | `gcAllocated()` — single instruction |
| **Soft cap on allocation** | None natively. SIGSEGV on OOM is best you get. | `gcSetLimit(N)` — `__rt_alloc` aborts cleanly with `ExitProcess(99)` if total crosses N |
| **Visibility into current usage** | `mallinfo` (Linux) or platform-specific. Often slow. | `gcSlabCount()` + `gcSlabBytes()` — both O(1) reads |
| **Scope-bound bulk free** | Roll your own region/pool allocator (e.g. APR pools, talloc) | `gcCheckpoint()` returns token; `gcRestore(token)` rewinds. Built into the runtime. |
| **Auto-reclaim per function** | C has no equivalent. C++ has RAII via destructors but not for malloc'd memory. | Functions named `pure_*` get `gcCheckpoint`/`gcRestore` wrapping auto-emitted by the compiler |
| **Memory model exposed to user code** | Raw pointers everywhere | String-handle ABI; raw pointers only via explicit `rawAlloc` family |

---

## The 50 GB scenario — concrete example

During Krypton 1.6.1 development, a malformed source file caused
`kcc.exe` to enter an O(N²) string-concatenation loop and consume
50 GB of RAM before the user noticed and killed it.

In C, the equivalent (`char *out = strdup(""); for (...) out =
strcat_grow(out, chunk);`) has identical worst case. The OS eventually
OOM-kills the process, but only after the entire physical RAM is
swapped to disk.

In Krypton 1.8.0, the same scenario is bounded by:

```krypton
just run {
    gcSetLimit(1 << 30)   // 1 GB cap
    runCompiler()         // even if buggy, aborts at rc=99 instead of pinning all RAM
}
```

`__rt_alloc` adds the requested size to `alloc_total` and compares
against `alloc_limit`; if exceeded, calls `ExitProcess(99)` cleanly.
The user sees a controlled abort instead of an unresponsive system.

---

## The `--watch` / event-loop scenario

Programs that re-render on a tick (live dashboards, watchers, REPLs)
classically leak in C unless the author manually frees per-iteration
allocations. In Krypton 1.8.0:

```krypton
while running == 1 {
    let ck = gcCheckpoint()
    renderFrame()
    Sleep(toHandle("16"))    // 60 fps
    gcRestore(ck)
}
```

`gcRestore(ck)` walks the slab chain, frees every slab allocated since
the checkpoint via `HeapFree`, and rewinds `slab_curr` / `slab_off`.
Memory stays bounded at peak per-frame usage forever, regardless of
how long the loop runs.

`kryofetch --watch` (the Krypton system-info tool) uses exactly this
pattern. Measured: 109,691 bytes per render, growing 110 KB / render
without `gcRestore`, **flat working set with it**.

C equivalent requires hand-maintained pool allocator with manual
reset between frames — same shape, but the bookkeeping is on you.

---

## The procedural-helper scenario

For functions that are pure side-effect (print stuff, manipulate state,
no useful return), Krypton 1.8.0 auto-emits the
checkpoint/restore wrap. Just prefix the function name with `pure_`:

```krypton
func pure_renderPanel(name) {
    let title = "[" + name + "]"
    let row1 = title + " - some content"
    let row2 = row1 + " - more"
    kp(row2)
}

just run {
    let i = 0
    while i < 10000 {
        pure_renderPanel("frame " + i)
        i = i + 1
    }
    // Slab usage stays bounded across all 10,000 iterations.
    // No leak, no manual cleanup, no `defer`-style scaffolding.
}
```

C equivalent:

```c
void renderPanel(const char *name) {
    char title[256], row1[1024], row2[2048];
    snprintf(title, sizeof(title), "[%s]", name);
    snprintf(row1, sizeof(row1), "%s - some content", title);
    snprintf(row2, sizeof(row2), "%s - more", row1);
    puts(row2);
}
```

The C version achieves bounded memory by using stack allocation with
fixed-size buffers, which means dealing with truncation, sizeof, and
buffer overflow risk. Krypton's heap-from-arena model gives unbounded
strings with bounded total memory.

---

## Diagnostic primitives (added 1.7.5–1.8.0)

Available right now in the Windows native runtime; Linux ELF and macOS
arm64 catch up before final 2.0.

| Primitive | What it returns | Cost |
|---|---|---|
| `gcAllocated()` | Lifetime cumulative bytes ever allocated | O(1) memory read |
| `gcLimit()` | Current soft cap (`"0"` = unlimited) | O(1) |
| `gcSetLimit(n)` | Set the soft cap | O(1) |
| `gcCollect()` | Placeholder, returns `"0"` (real semantics ship in 2.0) | O(1) |
| `gcReset()` | Free all slabs except the first, zero counters | O(slab count) |
| `gcCheckpoint()` | Return token capturing current arena state | O(1) + 1 alloc |
| `gcRestore(token)` | Rewind arena to checkpoint, free intermediate slabs | O(slabs since checkpoint) |
| `gcSlabCount()` | Number of slabs in the chain | O(slab count) |
| `gcSlabBytes()` | Bytes used in current (last) slab | O(1) |

For total current-usage estimate:

```krypton
func currentBytesEstimate() {
    const SLAB = 67108864   // 64 MB
    let count = toInt(gcSlabCount())
    let cur = toInt(gcSlabBytes())
    if count == 0 { emit 0 }
    emit (count - 1) * SLAB + cur
}
```

---

## What Krypton's model is NOT

To stay honest:

- **No mark-sweep yet.** `gcCollect()` is a placeholder. Programs that
  allocate without ever resetting (or without `gcRestore`/`gcReset`-
  style explicit reclaim) still grow until the soft cap fires. Real
  reachability-based collection ships in 2.0 with shadow-stack roots.
- **Single-threaded.** The `ADD [RIP+disp], RCX` in `__rt_alloc_v2` is
  not `LOCK`-prefixed. Multi-threaded use would race. Krypton has no
  threading primitives yet, so this is fine for 1.8.x.
- **No defragmentation.** Slabs don't compact. Long-running programs
  with mixed lifetimes can fragment. Mitigated by the bump-then-reset
  pattern; long-term solved by mark-sweep with compaction in 2.0.
- **`alloc_total` is lifetime, not current.** It only grows; it
  doesn't decrement on `gcReset` or `gcRestore`. For "current usage"
  use `gcSlabCount()` + `gcSlabBytes()`.
- **Off-arena allocations not tracked.** The huge-allocation fallback
  (`size > 64 MB - 8`) goes straight to `HeapAlloc` and isn't reclaimed
  by `gcReset`. These are rare; document if you trip the path.

---

## When Krypton's model is worse than C

C is still the right choice when:

- You need **fine-grained control** over individual allocation lifetimes
  (e.g., a single long-lived data structure with many short-lived
  workspaces around it). Krypton's "everything goes in the arena" gives
  you bulk-free, not per-object free. Workaround: separate scopes via
  `gcCheckpoint`.
- You need **deterministic worst-case latency** under 1 µs.
  `__rt_alloc_v2`'s tracking + limit check adds ~5 instructions over
  raw bump. Usually invisible; matters in hard real-time code.
- You're integrating with **C ABIs that expect malloc'd pointers**.
  Krypton's arena pointers are valid heap pointers (they came from
  `HeapAlloc`), but freeing them via `free()` from C would corrupt
  the slab. Use `rawAlloc` (which IS malloc'd) for hand-off.

For everything else — the 99% case of "I have a program that allocates
a lot of strings and I don't want to think about it" — Krypton 1.8.0
is the easier and safer choice.

---

## See also

- `docs/spec/functions.md` — full primitive reference with version tags
- `docs/v20_plan.md` — Tier 3 mark-sweep design + the road to 2.0
- `CHANGELOG.md` — release-by-release detail
