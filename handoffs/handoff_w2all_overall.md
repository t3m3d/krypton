# w → all : Krypton language roadmap (Should-Add + Beyond-C)

**From:** agent w (Windows)
**To:** all (agent m, agent l, future-w)
**Date:** 2026-06-13
**Status:** ROADMAP. Each entry is a discrete work unit. Pick one; check it's
not in-flight elsewhere; ship it. Sequence below is the recommended
priority order, not a hard schedule.

## Mission statement

Make Krypton feel like Python at the syntax level and like C++ at the
capability level. Easy to write a first program in; able to write a real
game engine, server, or compiler in. We're not chasing C parity — we're
chasing "what a 2026-era language should be," with the C feature gaps as
the obvious holes and the Go feature gaps as the structural ones.

## Why Windows first

Three reasons:

1. **Largest user base.** First impression for most users is Windows.
2. **Most rough edges currently.** macOS + Linux backends are closer to
   self-host stability; Windows native pipeline still has open OOM /
   freelist / manifest items (see `project_x64k_rebuild_oom`, this
   session's commits).
3. **Hardest backend to get right.** PE / IAT / Win32 ABI / DPI / chrome
   = more moving parts than ELF or Mach-O. If we crack each feature on
   Windows first, m and l adopt with clearer targets.

Mechanically: land each feature in `compiler/windows_x86/x64.k` first,
ship a smoke test, **then** post a handoff (w → m, w → l) with the
feature's Krypton-side syntax + IR shape + ABI notes so m / l can mirror.

## North star: Python-style FE + C++-grade capability

- **Syntax** stays Python-ish — no semicolons forced, indentation-aware
  blocks (optional braces), no type ceremony unless typed pointers / GC
  hot-paths need it.
- **Capability** matches C++ — direct memory, FP math, real concurrency,
  fast IO, file mapping, structured types, ABI-compatible FFI.
- **Compile path** native-PE / Mach-O / ELF, no C compiler in the loop.
- **Runtime** GC by default, manual escape hatches always available
  (`rawalloc` / `rawfree`).

The "Should-Add" list below patches the *capability* gap. The
"Beyond-C" list patches what would make Krypton feel modern.

---

## Tier A — Should-Add (C-equivalent capability gaps)

### A1. Floating point

**Priority:** highest. Single biggest capability gap.

**What:** real `f32` / `f64` typed locals, arithmetic, comparisons,
conversion to / from int, math builtins.

**User syntax:**
```krypton
let x: f64 = 3.14
let y: f64 = sin(x) * 2.0
let n: i32 = f64ToInt(y)
```

**Implementation sketch:**

- FE: lex `3.14` / `1.5e-3` / `2.0f` as FLOAT_LITERAL tokens.
  Parse `let x: f64 = ...` as typed binding (already supported for
  `*u8` etc.).
- IR: new ops `FADD`, `FSUB`, `FMUL`, `FDIV`, `FCMP_LT/LE/EQ/...`,
  `F2I`, `I2F`, `FLOAD_CONST`. Routed through typed-pointer style.
- BE (Windows):
  - x87 vs SSE2: SSE2 is required on Win10+ — use `MOVSD` / `ADDSD` /
    `SUBSD` / `MULSD` / `DIVSD` for `f64`; `MOVSS` for `f32`.
  - XMM0-XMM7 caller-saved for float args (MS x64 ABI uses XMM0-XMM3 for
    first 4 float args).
  - Return in XMM0.
- Runtime: math builtins exposed via IAT to `msvcrt.dll` (sin, cos,
  sqrt, log, exp, pow, atan2, floor, ceil, round, fabs). Or roll
  via internal SSE intrinsics where short. **New IAT entry: msvcrt**
  (and / or `ucrtbase` on newer Windows).
- Storage: 8-byte FP values still string-encoded at the Krypton-level
  boundary? Probably better: smart-int upper range carved for FP
  pointers, or introduce a `f64` boxed type that lives in `bufNew(8)` +
  `bufSetQwordAt` / `bufGetQwordAt` round-trip.

**Estimated effort:** ~3-4 focused sessions. Biggest piece is BE
codegen + the runtime ABI for boxed FP at Krypton-level call sites.

**Dependencies:** none (truly additive).

**Cross-platform follow:** m gets it cheaply (Mach-O + SSE2 / NEON
on arm64), l on x86 / aarch64 similar. Float math is portable; ABIs
differ — handoff per backend.

---

### A2. `switch` / `case`

**Priority:** high. `match` exists in some form but doesn't cover the
common C `switch(x) { case 1: ...; case 2: ...; default: ... }` shape
with fallthrough.

**What:** classic switch on int / string with case ranges + optional
fallthrough.

**User syntax:**
```krypton
switch state {
    case "idle":           handleIdle()
    case "running":        handleRun()
    case "done", "error":  handleExit()
    default:               handleOther()
}
```

**Implementation sketch:**

- FE: new keyword `switch` + `case` + `default`. Multi-value cases
  (comma-separated).
- IR: lowers to a chain of `CMP + JE` for small N, or jump table for
  large N (≥8 cases) when keys are dense ints.
- BE: jump table = read-only RVA array of rel32 targets. Same `.rdata`
  emission as IAT.
- No fallthrough by default (Go-style) — explicit `fallthrough` keyword
  if requested. Most modern bugs come from C-style implicit fallthrough.

**Estimated effort:** 1-2 sessions.

**Dependencies:** none.

---

### A3. Proper enums

**Priority:** high. Pairs with switch.

**What:** distinct type, autoincrementing values, exhaustive switch
checks, string conversion.

**User syntax:**
```krypton
enum State { Idle, Running, Done, Error }

let s = State.Idle
switch s {
    case State.Idle:    ...
    case State.Done:    ...
}
let label = stateName(s)  // "Idle"
```

**Implementation sketch:**

- FE: new `enum NAME { ... }` keyword. Parser builds a name→int table.
- IR: enum values lower to ints, names lower to const string lookups.
- BE: emit name table in `.rdata` for reverse-lookup helper.
- Type checker: when both operands of `==` are enum members of the
  same type, allow. Cross-enum comparison rejected at IR-emit time.

**Estimated effort:** 1 session.

**Dependencies:** A2 (switch) for the exhaustiveness checker bonus.

---

### A4. Variadic functions

**Priority:** medium-high. Needed for any `printf`-style API.

**What:** `func f(fmt, ...args) { ... }` with format-string handling
in a stdlib helper.

**User syntax:**
```krypton
printf("name=%s age=%d\n", name, age)
```

**Implementation sketch:**

- FE: `...args` syntax in last parameter.
- IR: variadic call passes a `(count, base_ptr)` pair pointing at an
  on-stack arg array.
- BE: caller marshals to stack, callee reads args[i] by index +
  type-tag.
- Stdlib: `printf` / `sprintf` / `fprintf` in `stdlib/fmt.k` parsing the
  format string + walking args.
- ABI: on Windows x64, varargs already require RAX = SSE-arg-count for
  MS ABI compliance with CRT functions, so we match the existing
  convention.

**Estimated effort:** 2 sessions.

**Dependencies:** A1 (float) is helpful but not required — `%f` needs FP.

---

### A5. Fixed-size arrays

**Priority:** medium-high. Cleaner than `bufNew(toStr(N * sizeof(T)))`.

**What:** `let a: u32[16]` stack-allocates 16 × u32, bounds-checked
indexing.

**User syntax:**
```krypton
let buf: u8[4096] = [0; 4096]
buf[10] = 65
let v: f64[3] = [1.0, 2.0, 3.0]
```

**Implementation sketch:**

- FE: parse `T[N]` and `[v; N]` / `[v1, v2, ...]` literals.
- IR: lowers to stack alloca (true stack alloc — see open task in
  `project_v1810_phase_c_nested.md`) + typed pointer to base.
- BE: `SUB RSP, N*sizeof(T)` at function entry + `LEA r, [RSP+slot]`
  for array base.
- Bounds check: optional, compile-time if N + index both literal,
  runtime CMP+JA otherwise. Flag to disable for perf.

**Estimated effort:** 2-3 sessions. Tied to the open "true stack
alloc" todo from v1.8.10.

**Dependencies:** A1 helps for `f64[N]`; otherwise independent.

---

### A6. Static locals

**Priority:** medium. Trivial in C, currently impossible cleanly in
Krypton (see `feedback_module_mutable_globals` — module-level mutables
are buggy).

**What:** function-scope variable that retains value across calls.

**User syntax:**
```krypton
func counter() {
    static n: i64 = 0
    n = n + 1
    emit n
}
```

**Implementation sketch:**

- FE: `static` modifier on `let`.
- IR: hoists the `let` to a module-level slot with a unique name
  (e.g. `__static_counter_n_0`), but scope-locks reads/writes to the
  containing function.
- BE: emit slot in `.rdata` (writable), MOV via RIP-relative.

**Estimated effort:** 1 session. Solves the module-mutable bug as a
side effect by giving it a real home.

**Dependencies:** none.

---

### A7. Compound assignment beyond `+=`

**Priority:** low. Quality-of-life.

**What:** `-=` `*=` `/=` `%=` `&=` `|=` `^=` `<<=` `>>=`.

**User syntax:** obvious.

**Implementation sketch:** FE parser change only. Lowers to existing
binary-op + assign. No IR or BE work.

**Estimated effort:** 1 hour to half a session.

**Dependencies:** none. Could ship as a tiny same-day commit
alongside any larger feature.

---

### A8. First-class file I/O at fd level

**Priority:** medium. `readFile(path)` is all-or-nothing, can't stream
a 10 GB log or do random-access patches.

**What:** `open(path, mode)` returns fd, `read(fd, n)` / `write(fd, s)`
/ `seek(fd, offset)` / `close(fd)`. Layered on top of CreateFileA /
ReadFile / WriteFile / SetFilePointer / CloseHandle — already in
`KR32_FUNCS`.

**User syntax:**
```krypton
let fd = open("big.log", "r")
while !eof(fd) {
    let chunk = read(fd, 65536)
    process(chunk)
}
close(fd)
```

**Implementation sketch:**

- Stdlib `stdlib/io.k` module. Pure wrappers over existing
  CreateFile/ReadFile/WriteFile IAT entries.
- mode: `"r"` / `"w"` / `"rw"` / `"a"` → dwDesiredAccess + dwCreation flags.
- New builtins: none. All Krypton-side.

**Estimated effort:** half a session.

**Dependencies:** none. Could ship anytime.

---

## Tier B — Beyond-C (modern-language gaps)

These are where Krypton stops looking like a C cousin and starts
looking like a 2026-era language. Most are bigger lifts than the
Tier A items.

### B1. `defer`

**Priority:** highest of Tier B. Solves 80% of leak / cleanup bugs.

**What:** scope-exit cleanup. `defer file.close()` runs when the
containing function returns (any path, including early `emit`).

**User syntax:**
```krypton
func processFile(path) {
    let fd = open(path, "r")
    defer close(fd)               // runs on every return path

    let data = readAll(fd)
    if invalid(data) { emit "" }  // close(fd) still runs
    emit transform(data)
}
```

**Implementation sketch:**

- FE: `defer` keyword. Parser collects all `defer` statements per
  function into a per-function defer stack.
- IR: at every `RET` / `emit` (return) op, inject the defer stack
  in reverse order before the actual return.
- BE: no special support; defers lower to ordinary function calls.
- Tricky: deferred expression captures variable values at the time
  of `defer`, NOT at the time of the call. Need to snapshot.

**Estimated effort:** 2 sessions.

**Dependencies:** GC stages 1-5 already track scope, so the
shadow-stack infrastructure can be reused for defer slots.

---

### B2. Multi-return

**Priority:** high. Currently every "(value, error)" return is
string-encoded — ugly and slow.

**What:** functions return tuples; destructuring at call site.

**User syntax:**
```krypton
func divmod(a: i64, b: i64) -> (i64, i64) {
    emit (a / b, a % b)
}

let (q, r) = divmod("17", "5")
let (val, err) = readConfig("settings.json")
if err != "" { handle(err) }
```

**Implementation sketch:**

- FE: tuple syntax `(a, b)` for return + destructuring on `let`.
- IR: multi-return becomes a stack-passed out-param block; caller
  reads each slot.
- BE: callee writes return values to caller-provided stack slot;
  RAX holds error-summary / count.
- ABI: extend MS x64 ABI cleanly — first 2 returns in RAX + RDX
  for ints / RAX + XMM0 for mixed; spill to stack beyond.

**Estimated effort:** 2-3 sessions.

**Dependencies:** none required, but A1 (float) interacts with the
return ABI choice.

---

### B3. Slices

**Priority:** medium-high. Unifies string / buf / array access into
one read-or-write view.

**What:** `slice` = `(ptr, len, cap)` triple. Indexing checks `len`;
appending checks `cap`; reslicing produces a sub-slice without copy.

**User syntax:**
```krypton
let buf: u8[1024] = ...
let s = buf[10:42]              // slice into the buffer
print(s.len)                    // 32
s[0] = 65                       // writes into underlying buf[10]
let sub = s[5:20]               // sub-slice
let appended = append(s, "!")   // grows if cap allows
```

**Implementation sketch:**

- FE: slice literal syntax `[lo:hi]`.
- IR: slice type lowers to a 24-byte triple. Codegen for index /
  re-slice / append.
- BE: index = base + lo * sizeof(T); bounds check vs len.
- Runtime: `append` reuses the freelist when cap exceeded —
  natural pairing with stage 6 phase 2 work.

**Estimated effort:** 3 sessions.

**Dependencies:** A5 (fixed-size arrays) makes slicing them
natural.

---

### B4. Interfaces / structural protocols

**Priority:** medium. Krypton has closures + funcptr but no
abstraction for "I accept anything with these methods."

**What:** duck-typed protocol. Any struct that has the named methods
satisfies the interface.

**User syntax:**
```krypton
interface Drawable {
    func draw(canvas)
    func bounds() -> Rect
}

struct Circle { x: f64, y: f64, r: f64 }
func draw(c: Circle, canvas) { ... }
func bounds(c: Circle) -> Rect { ... }

// Circle now satisfies Drawable without explicit declaration

func renderAll(items: []Drawable, canvas) {
    for item in items {
        item.draw(canvas)
    }
}
```

**Implementation sketch:**

- FE: `interface` block + method signatures.
- IR: interface value = `(data_ptr, vtable_ptr)` pair. vtable built
  per (struct, interface) combination at compile time.
- BE: dispatch via vtable[method_index].

**Estimated effort:** 3-4 sessions. Substantial design space —
how to handle methods on non-struct values, multi-interface
satisfaction, intersection types.

**Dependencies:** B2 (multi-return) is nice for interface methods
returning `(value, error)`.

---

### B5. Goroutines + channels

**Priority:** **headliner.** This is the Go-feature that makes
Krypton feel like a 2026 language. Also the biggest lift.

**What:** lightweight cooperative coroutines + typed message-passing
channels. `go f()` spawns; `<- ch` receives; `ch <- v` sends.

**User syntax:**
```krypton
let ch = chan(i64, 16)               // buffered channel, cap 16

go func() {
    for i in range(100) {
        ch <- i
    }
    close(ch)
}()

for v in ch {
    print(v)
}
```

**Implementation sketch:**

- FE: `go` keyword + `chan(T, cap)` type + `<-` send/recv operator.
- Runtime: M:N scheduler. Each goroutine = small stack (8 KB initial,
  grows via segmented stacks or copy-and-grow) + register state.
- Win32: scheduler runs on a small thread pool created via
  CreateThread, parks idle threads with WaitForSingleObject.
- Channels: bounded queue + condition variable + producer/consumer
  semaphores. Lock-free on the fast path.
- Stack management: this is the hard part. Either copy-and-grow
  (more allocator pressure, simpler), or contiguous-stack with
  per-frame check-and-grow prologues (more codegen work, faster
  hot path).

**Estimated effort:** weeks. This is a 5-10-session arc.

**Dependencies:** GC stage 6 phase 3 (auto-trigger) helps because
goroutines allocate frequently. Scheduler design needs the runtime
to be re-entrant on alloc paths (which the in_collect_guard already
prepares for).

---

### B6. Atomics + memory model

**Priority:** prerequisite for B5 to be safe.

**What:** `atomic` types and ops. `atomicLoad` / `atomicStore` /
`atomicAdd` / `compareAndSwap` with acquire / release / relaxed
ordering.

**User syntax:**
```krypton
let counter: atomic i64 = 0
atomicAdd(&counter, 1)
let v = atomicLoad(&counter, acquire)
```

**Implementation sketch:**

- IR: new ops `ATOMIC_LOAD` / `ATOMIC_STORE` / `ATOMIC_ADD` /
  `ATOMIC_CAS` with ordering tag.
- BE: x86-64 has strong default ordering; relaxed = MOV, release =
  MOV + SFENCE, acquire = LFENCE + MOV. CAS = `LOCK CMPXCHG`. XADD
  for atomic increment.
- Memory model: adopt C++ acquire / release / seq_cst semantics
  (Go's model is fine too). Document explicitly.

**Estimated effort:** 1-2 sessions for the core ops.

**Dependencies:** none. Can ship before B5 as a primitive.

---

## Tier C — Lower priority / future

- **`union` types** — tagged variants. Pairs with proper enums.
- **Bit fields in struct** — networking, hardware. Workaround:
  shift-and-mask helpers.
- **Inline `asm{}` block** — already on the 2.1 roadmap
  (`project_v20_alpha3_lean_2_0_push`).
- **First-class regex** — currently use external tools.
- **Generic functions / type parameters** — Go has them now; Krypton
  could do without for a while since untyped strings dodge the
  problem.
- **Time / date stdlib** — `time.now()`, `time.parse(...)`,
  `time.format(...)`. Builtins on top of GetSystemTime / clock_gettime.
- **Error types as a first-class concept** — not strings,
  not nil-pointers, an actual `Error` interface.

## Sequence recommendation

If we're committing to "ship something every session-ish" the order
that minimises blocked-by-dependencies and maximises early-user
visibility:

1. **A7 compound assignment** — half-session warm-up.
2. **A1 floating point** — 3-4 sessions. Unlocks tons of stdlib
   downstream.
3. **A2 switch/case** — 1-2 sessions.
4. **A3 enums** — 1 session (pairs with switch).
5. **A8 file I/O fd-level** — half-session.
6. **A4 variadic + stdlib `printf`** — 2 sessions, lots of user
   payoff.
7. **B1 defer** — 2 sessions. Solves leak class of bugs.
8. **B2 multi-return** — 2-3 sessions. Cleans up every "(value, error)"
   site.
9. **A5 fixed-size arrays** — 2-3 sessions. Requires stack alloc work.
10. **A6 static locals** — 1 session.
11. **B6 atomics** — 1-2 sessions. Prep for concurrency.
12. **B3 slices** — 3 sessions.
13. **B4 interfaces** — 3-4 sessions.
14. **B5 goroutines + channels** — 5-10 sessions. The mountain.

Estimated total: 30-50 focused sessions for a complete feature parity
arc. Probably realistically a 6-12 month project for one agent.

## Cross-platform ordering rule

Land each feature on Windows first (per the "why Windows first"
section). Once it works there, file a per-feature handoff to m and l
with:

- IR shape (so m / l's compile.k changes match)
- ABI notes (where args / returns live, register usage, alignment)
- Runtime helper signatures (so m / l can implement the matching
  ELF / Mach-O syscalls)
- Test program that the agent's backend should produce + run
  byte-identical output for

Stage 6 phase 2 is the pattern: Windows shipped 5185d50e, m / l
adopt later. Same shape for every feature on this list.

## What this list deliberately leaves out

- **C preprocessor.** `#define` / `#ifdef` / `#include`. Krypton's
  `import` + `jxt` is cleaner. Preprocessor macros are a footgun.
- **`goto`.** match + early `emit` cover all real use cases.
- **K&R declarations / trigraphs / hex floats.** Vestigial.
- **`volatile` / `restrict`.** Useful in C because of weak memory
  model + aliasing assumptions; Krypton's allocator model makes them
  moot (everything goes through typed pointers).

## North-star check

When the list above is done, a Krypton program should look like
Python (syntax-wise) but compile to a small native binary with no GC
pauses you'd notice and a `go` keyword that gives you real
concurrency. That's the target.

— w

[[w2l_memory]] [[stage6_phase3_plan]] [[project_v20_plan]]
