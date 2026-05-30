# Building a Self-Hosting Compiler — A Krypton Case Study

**Working title.** Subject to platform / publisher tweaks. Alternates:
- "From Bytes to Backend: Writing a Self-Hosting Compiler in 5,000 Lines"
- "The Krypton Compiler Book: ELF, PE, Mach-O, and Now WASM, From Scratch"
- "How to Write a Programming Language That Doesn't Need C"

**Target audience.** Intermediate-to-advanced developers who have shipped
software but never written a real compiler. Compiler students who want
to skip the LLVM tax. Hobby PL designers. People who liked Crafting
Interpreters but want the *native code generation* sequel.

**Length.** 12 chapters, roughly 250 pages PDF. Companion repo (Krypton
itself) is the runnable artifact for every chapter.

**Pricing model.** Pre-launch: $39 early-bird through chapter 6
(self-published on Gumroad / Lemon Squeezy). Full launch: $79. Bundle
with the kcode IDE for $99 ($29 standalone for kcode, so $50 effective
discount on the bundle).

---

## Why this book exists

Most compiler books either stay in interpreter-land (Crafting
Interpreters, brilliant but no machine code), or assume LLVM (every
"build your own LLVM frontend" tutorial), or use a Pascal-era tinytoy
language that doesn't show you how to wire a real stdlib and three
operating-system backends.

Krypton is the proof that a *single person* can ship a self-hosting
language with native backends for Linux, Windows, and macOS arm64,
including a code-signed Mach-O writer, and a web framework on top,
without LLVM and without GCC at user-invocation time. The book is the
walk-through. Every chapter ends with a runnable artifact you can
trace in the actual public repo.

---

## Chapter outline

### Chapter 1 — Why you'd bother (and what you'll have at the end)

- The landscape: LLVM-based, C-targeted, bytecode/VM, native-self.
- The Krypton bet: no LLVM, no GCC user-facing, three native backends.
- What "self-hosting" actually means and why hitting it changes how
  you think about the language.
- The whole pipeline at a glance.
- Setting up the dev environment (Krypton's bootstrap, a host C
  compiler used once, never again).

### Chapter 2 — A language on one EBNF page

- Designing for compiler-writer ergonomics first.
- Krypton's grammar: func/fn, just-run, emit, if/elif/else, while,
  for-in, match, try, struct, lambdas.
- Tokenizer + parser in 500 lines.
- Living with one runtime value type (strings) and "smart int" dispatch.
- First milestone: the parser produces a tree from `01_hello_world.k`.

### Chapter 3 — Tree-walking, then IR

- Why we IR. Why we don't AST-walk forever.
- Krypton's IR shape: SSA-lite, instruction-stream-with-labels.
- Lowering AST → IR in 800 lines.
- Smoke test: every tutorial program lowers without crashing.

### Chapter 4 — Linux x86_64: writing your own ELF (no linker)

- ELF in 30 minutes: program headers, sections, segments, the bit
  about why dynamic linking is irrelevant for this approach.
- Direct syscalls (write, exit, mmap) instead of libc.
- Emitting x86_64 instructions from IR: register allocation
  ignored on purpose (single accumulator + stack).
- First binary: 64-byte ELF that prints "Hello" via `write` syscall.
- Then: `01_hello_world.k` → ELF binary.
- Why "no libc" makes the binary 600 bytes instead of 16KB.

### Chapter 5 — Windows x86_64: PE/COFF without Microsoft's toolchain

- PE/COFF anatomy: DOS stub, NT headers, sections, import directory.
- The minimum viable kernel32 import set (GetStdHandle, WriteFile,
  ExitProcess).
- Emitting PE32+ in 600 lines of Krypton.
- Subtleties: section alignment, the optional header that isn't
  optional, RVA vs file offset.
- A Krypton runtime DLL (krypton_rt.dll) for the bits that don't
  belong inline.
- Same `01_hello_world.k` → Windows `.exe`.

### Chapter 6 — macOS arm64: Mach-O and the AMFI problem

- Mach-O structure: load commands, segments, sections.
- ARM64 instruction encoding (with help from a hand-rolled assembler
  table).
- Chained fixups instead of LC_DYSYMTAB. Why this is the modern path.
- **The AMFI problem on macOS Tahoe.** Apple no longer lets unsigned
  Mach-O binaries execute. We solve it by emitting an ad-hoc SHA-256
  code signature ourselves. No `codesign`, no Apple developer cert.
- Code Signing Blob layout from first principles.
- Same `01_hello_world.k` → arm64 Mach-O. Verified running under AMFI.

### Chapter 7 — Crossing the bootstrap

- The chicken-and-egg: the compiler is written in Krypton, but you
  need Krypton to compile Krypton.
- The seed: one-time use of GCC or clang to bootstrap. Subsequent
  rebuilds are pure native.
- Self-hosting verification: build the compiler with itself,
  diff the output binary against the seed.
- What changes the day this works.

### Chapter 8 — The stdlib problem

- "Standard library" in a no-libc-no-C world.
- 36 stdlib modules, all pure Krypton.
- Walking through a tricky one: `k:server` (the cfunc bridge, POSIX
  vs Winsock).
- Walking through an easy one: `k:list_utils` (comma-format lists
  built on string + concat).
- The maps decision: comma-format builtins vs the `map.k` module —
  why two flavors coexist.

### Chapter 9 — Building a web framework in your own language

- `htmk`: HTML emit DSL. ~200 helpers, all one-liners.
- `kcss`: CSS emit DSL. The DSL I almost didn't write, why it earns
  its keep.
- `ks`: KryptonScript → JavaScript emit DSL. Server-emits-client JS
  patterns.
- `k:server` + `k:router`: Express-style HTTP, in pure Krypton, with
  one cfunc block for socket I/O.
- Building `krypton-lang.org` itself with the framework. The whole
  site is one `.htk` file.

### Chapter 10 — The browser bridge (mini-interpreter detour)

- The lesson runner problem: how do you run user-edited code in the
  browser without shipping a real Krypton runtime there?
- A JavaScript mini-interpreter as a bridge: 300 lines of regex-and-eval
  that handle 26/31 lessons cleanly.
- The bridges you build are temporary. The point is to acknowledge
  them as bridges and plan their retirement.

### Chapter 11 — WebAssembly: the real answer

- WebAssembly binary format from first principles. It's simpler than
  Mach-O.
- Adding a `--wasm` backend: type section, import section, code section,
  data section.
- Browser embedding: `WebAssembly.instantiate`, host imports for
  console.log.
- WASI: where the same `.wasm` runs in wasmtime / wasmer / Cloudflare
  Workers.
- Replacing `runner.js` with `runner.wasm`. The lesson runner becomes
  real Krypton.
- The 12-week roadmap from "hand-emit hello.wasm" to "kcc.wasm runs in
  the browser."

### Chapter 12 — Shipping and beyond

- Packaging: Homebrew taps, signed installers (macOS pkg, Windows Inno
  Setup, Linux .deb).
- The infrastructure side: Hostinger Apache vs dedicated VPS, cache
  policies, CSP, when to use which.
- Decisions you'll wish you made earlier.
- Where Krypton is heading: SSE, session middleware, form parsing,
  course companion features.
- How to monetize a niche language project: the path Brian took
  (consulting + paid IDE + sponsors + this book), with actual numbers.

---

## Code repo cadence

Every chapter includes:
1. A "starting state" git tag of the Krypton repo.
2. Embedded code listings (chunks small enough to read on a phone).
3. A "diff this chapter" git command that shows exactly what changed.
4. Exercises at the end: 1 trivial, 1 medium, 1 advanced. Solutions
   in an appendix.
5. A "real world" sidebar: where this technique shows up in a
   production language (Go's linker, Rust's no-std, Zig's
   cross-compilation, etc.).

## Marketing

- Each chapter's writing process gets a public dev-log post on
  krypton-lang.org/blog and HN-tier title attempts (`Show HN: I wrote
  my own Mach-O writer because Apple won't let me ship unsigned
  binaries`).
- One chapter free as the lead-magnet: chapter 4 (Linux ELF) — the most
  approachable + tweetable.
- Pre-order phase opens after chapter 6 is drafted. Buyers get an
  every-two-weeks update + early access to subsequent chapters.

## Risks

- **Scope creep.** Each chapter could be its own book. Discipline: 20
  pages max, code-heavy, one main concept per chapter.
- **The WASM chapter outpaces the implementation.** Mitigation: write
  chapter 10 (JS bridge) immediately, chapter 11 (WASM) when phase 2
  of the WASM backend lands.
- **The reader audience overlap with HN/Twitter people is narrow.**
  This is fine — niche price + niche audience is the model.

## Comparable products

- *Crafting Interpreters* (Robert Nystrom) — free online, paid print.
  Different domain (interpreter, not native compiler) but the
  authoring model is the comparison: a single author, one runnable
  artifact, deeply technical, sells well.
- *Writing An Interpreter In Go* / *Writing A Compiler In Go* (Thorsten
  Ball) — $39 each, ~3000 sold on launch. Same audience, different
  language target.
- *Pikuma compiler course* — $40-60, video-first.

## Timeline

- Weeks 1-4: chapters 1-2 written.
- Weeks 5-8: chapters 3-4 written. Pre-order opens with sample chapter 4.
- Weeks 9-16: chapters 5-7 written. First HN post.
- Weeks 17-24: chapters 8-11 written. Mid-cycle launch.
- Weeks 25-28: chapter 12 + polish + full launch.

~7 months to full release. ~3 months to first revenue (chapter 4 lead-
magnet + pre-order).

---

## See also

- `docs/kcss_design.md`           — module designed during chapter 9
- `docs/wasm_backend_design.md`   — the chapter 11 implementation plan
- `docs/LAUNCH_POSTS.md`          — HN / X / Reddit copy for chapter 4
                                    and the pre-order launch
