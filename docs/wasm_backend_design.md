# `kcc --wasm` — Krypton-to-WebAssembly backend design

**Status:** design draft, not yet implemented.
**Author:** Brian (KryptonBytes) / krypton-lang.org.
**Date:** 2026-05-30.

This is the design note for adding a WebAssembly backend to Krypton —
making `kcc --wasm hello.k → hello.wasm` a first-class native target
alongside the existing ELF / PE / Mach-O backends. Once this lands,
Krypton becomes a language you can ship to the browser, the edge
(Cloudflare Workers, Fastly Compute@Edge, Wasmer), and serverless
runtimes (wasmtime, WASI), in addition to the three OSes the native
backends already target.

This is the **right** answer to "how should code run in the browser on
krypton-lang.org." The current lesson-runner (`web/site/dist/runner.js`)
is a JavaScript mini-interpreter — a deliberate bridge. It covers the
lesson subset (26/31 PASS, 5 GATE) but adds a second toolchain that
isn't Krypton. The WASM backend replaces it with the real `kcc` running
real `.k` source compiled to `.wasm`, executed natively by the browser's
WASM engine.

---

## Goals

1. **First-class target.** `kcc --wasm src.k -o out.wasm` works the same way
   `kcc --native` does today. No second build step, no JS layer in the
   pipeline.
2. **Self-hosted parity.** The WASM backend itself is written in Krypton
   (`compiler/wasm32/wasm_self.k`), mirroring the macOS pattern
   (`compiler/macos_arm64/macho_arm64_self.k`).
3. **Browser-runnable lessons.** Replace `runner.js` with `runner.wasm`
   built from Krypton source. The site's "▶ Run" button then runs **real
   Krypton**, not a JS translation of a subset.
4. **WASI viability.** With WASI bindings, the same `.wasm` runs in
   wasmtime / wasmer / Cloudflare Workers / Fermyon — opens deployment
   paths beyond the browser.

## Non-goals (v1)

- **Full stdlib port.** `k:server`, `k:fs`, `k:http` won't run in pure
  browser WASM (no syscalls). They become host-provided functions when
  the embedding environment supplies them, or no-ops in browser-only mode.
- **GC port.** v1 is no-GC. Krypton already has a `KR_NOGC=1` mode for
  the elf/macho backends; WASM v1 inherits that and only grows linear
  memory until the page is reclaimed. Real GC is a v2 problem.
- **Threading / SharedArrayBuffer.** Single-threaded WASM module.
  Sufficient for lesson runner + most stdlib.
- **Source maps.** Not in v1. Lesson errors will report WASM instruction
  offsets, not Krypton lines. A `.kmap` debug-info section is a v2
  add-on.

---

## What WebAssembly actually is (and why this is easier than Mach-O)

WASM is a **small, well-documented binary format.** The whole spec is
under 200 pages and the binary encoding fits on two cheat-sheet pages.
Compared to Mach-O — which Krypton already emits, including ad-hoc
SHA-256 code signatures for AMFI — WASM is mechanically simpler:

- **One section list, one continuation.** A WASM module is a magic
  number (`\0asm`), version (`\x01\x00\x00\x00`), then a flat sequence
  of typed sections. No load commands, no segment-to-section nesting, no
  alignment slots, no chained fixups.
- **No relocations.** All addresses are abstract indices (function
  index, local index, global index) the VM resolves at instantiation.
- **No linker.** A WASM module IS the final artifact. No `ld`-like
  step.
- **No code signing.** Browsers don't gate WASM by signature.

A first cut of `wasm_self.k` should land in roughly the same line-count
range as `compiler/macos_arm64/macho_arm64_self.k` (~30KB of Krypton).
Plausibly less, since there's no signature work.

---

## Binary format (what we have to emit)

A WASM module is a sequence of sections in this order. Most are optional
in v1.

| ID  | Section      | v1 plan |
|-----|--------------|---------|
| 0   | Custom       | skip (used for source maps / debug names; v2) |
| 1   | Type         | emit — list of `func` signatures              |
| 2   | Import       | emit — host imports (console_log, etc.)       |
| 3   | Function     | emit — declares functions by type index       |
| 4   | Table        | skip in v1 (no funcptr → WASM table mapping yet) |
| 5   | Memory       | emit — one memory, initial 1 page (64KB), max 16384 |
| 6   | Global       | emit — global vars (stack pointer, GC state if any) |
| 7   | Export       | emit — main entry point (`_start` for WASI, or named) |
| 8   | Start        | optional — defaults to `_start` for WASI                  |
| 9   | Element      | skip in v1                                                 |
| 10  | Code         | emit — actual function bodies                              |
| 11  | Data         | emit — static strings, lookup tables                       |

Each section is a length-prefixed payload. Values are LEB128-encoded.
Function bodies are also LEB128 prefixes + a stream of opcodes ending in
`0x0B` (end).

---

## Krypton → WASM lowering

Krypton compiles through Krypton IR (`.kir`), then to native via the
existing backend. WASM is "just another backend" — same IR input, new
emitter.

### Types

Krypton's runtime is dynamically typed — every value is a tagged
pointer (string, int, list, map). On native, that's a `char*` with the
type encoded in low bits or in a header. On WASM, the same encoding
works: 32-bit pointer into linear memory + tag bits.

In v1, treat **all values as i32** (offsets into linear memory or
small immediates). Numeric operations on what Krypton sees as ints
get a runtime check on the pointer tag, then dispatch — same as native.

Future: a static type-narrowing pass could lift hot paths to native
WASM `i32` / `f64` operations and skip the tag-check.

### Memory layout

```
[0x00000000 .. 0x00001000)  reserved (null-pointer guard)
[0x00001000 .. 0x00100000)  static data (string literals, lookup tables)
[0x00100000 .. heap_top)    heap (grows up)
[stack_top .. memory_end)   stack (grows down from end of memory)
```

WASM linear memory grows in 64KB pages. We request `initial:1` and
`maximum:16384` (1GB cap). The Krypton allocator (`_alloc` in native
output) gets re-implemented as a small Krypton stub that:

1. Bumps `heap_top`.
2. If `heap_top` would cross a page boundary, calls `memory.grow` to
   add pages.
3. Returns the allocated pointer (i32 offset).

No `free` in v1. Programs run to completion, memory is reclaimed when
the host frees the WASM instance.

### Functions

Each Krypton `func` lowers to one WASM function. Parameters and locals
are `i32` (or `i64` for 64-bit numerics if Krypton starts emitting them
— currently we don't). Return type is `i32` (or void if the func has
no `emit`).

`callPtr(fn, args...)` lowers to `call_indirect` with the funcptr as
the table index. **This requires the Table section + an Element section
populating the table** — which is the one place in v1 where we
can't skip Section 4/9. Without funcptrs, however, lots of stdlib breaks
(router dispatch, htEach closures), so plan to include it from day 1.

#### Function-index layout (as of 2.2)

`wasm_self.k` emits a fixed function-index map. Imports come first
(WASM spec), then the hand-emitted runtime helpers, then user funcs:

| Index | Kind   | Name |
|-------|--------|------|
|  0..10 | import | `console_log`, `console_log_int`, `canvas_clear`, `canvas_circle`, `canvas_line`, `canvas_set_fill`, `canvas_set_stroke`, `canvas_width`, `canvas_height`, `random_int`, `time_ms` |
| 11    | helper | `$int2str` |
| 12    | helper | `$tostr` |
| 13    | helper | `$concat` |
| 14    | helper | `$index` |
| 15    | helper | `$substring` |
| 16    | helper | `$startsWith` |
| 17    | helper | `$toint` |
| 18    | helper | `$count`     — commas+1 |
| 19    | helper | `$split`     — comma-field by index |
| 20    | helper | **`$lineCount`** — newlines, trailing-`\n` discounted (2.2) |
| 21    | helper | **`$getLine`**   — newline-field by index (2.2) |
| 22+   | user   | `__main__` + every user `func` |

When you add helpers, you must also:

- Bump the `+22` constant in `funcIndexOf` and `mainIdx` (`compile.k:1321`).
- Update the helper count in `wasmFuncs()` (`11 + cnt`) and append the
  new helper's type-index byte after `b(3) + b(4)`.
- Add a `BUILTIN <name> ` dispatch arm in `emitFuncBody` that emits
  `iCALL(<index>)`.
- Append the helper body to `helperBodies` in `buildModule()`.

### Strings

Krypton strings on native are length-prefixed `char*` allocations. On
WASM the same encoding works — allocate `[len:u32][bytes...]` in
linear memory, store the pointer.

String literals from source go in the Data section (immutable, addressed
by their offset into linear memory).

### Imports (host functions)

WASM modules can import functions from the host (JS, wasmtime, etc.).
The minimal set for "hello world to console" in a browser:

```
(import "env" "console_log"    (func (param i32 i32)))   ; ptr, len
(import "env" "console_log_int" (func (param i32)))      ; int value
```

For a richer set (WASI compatibility), import `wasi_snapshot_preview1`:

```
(import "wasi_snapshot_preview1" "fd_write"  (func (param i32 i32 i32 i32) (result i32)))
(import "wasi_snapshot_preview1" "proc_exit" (func (param i32)))
```

`kp(x)` (Krypton print) lowers to whichever import is wired up.

---

## Stdlib subset

The browser doesn't have file I/O, sockets, or a process model. The
stdlib divides into three buckets:

### Bucket A — runs unchanged

Pure-Krypton modules with no `cfunc` blocks. These compile to WASM
exactly like any user code.

```
htmk, kcss, ks, list_utils, math_utils, range, set, stack, queue,
sort, search, string_utils, char_utils, hex, base64, bitwise, fp,
collections, counter, csv, datetime (string-only), float_utils,
format, json_emit, json_parse, json, jsonrpc, lines, map,
option, pair, path, result, struct_utils
```

That's about 70% of stdlib. The web stack (`htmk` + `kcss` + `ks`)
runs in WASM untouched — which means a Krypton program in WASM can
generate HTML/CSS/JS strings to inject into the host DOM.

### Bucket B — needs host imports

Modules whose `cfunc` blocks become WASM `(import)`s mapped to host
functions.

```
io_utils    — host provides console_log
proc        — partial (no fork/exec; getenv → host import)
random      — host provides Math.random
fs          — host-provided in WASI/Node; no-op in browser-only
http        — host fetch() in browser, fetch_xhr in WASI
server      — only on WASI hosts that support sockets (rare)
```

### Bucket C — won't port in v1

```
gui  — terminal UI; no analog
mmap — no
proc.fork — no
```

For the lesson runner specifically, we only need Bucket A + console_log,
which is the easiest possible host integration.

---

## MVP scope

**Phase 0 — paper proof.** Write the binary format emitter in a
standalone `compiler/wasm32/wasm_emit.k`. Test by hand-emitting a
`hello.wasm` that prints "Hello" via console_log import. Validate with
`wasm2wat` and run in Node / Wasmer.

**Phase 1 — IR → WASM.** Take `.kir` as input. Emit:
- Type section
- Import section (env.console_log)
- Function section
- Memory section (1 page, max 16k)
- Export section (`_start`)
- Code section (one function: load string constant, call_indirect-free
  call to console_log import)
- Data section (one string)

Test against `tutorial/01_hello_world.k`. Output must match
`kcc -r tutorial/01_hello_world.k` byte-for-byte.

**Phase 2 — control flow + funcs.** if/while/for-in, multi-function
modules. Test against tutorials 1-13. Match `kcc -r` output for each.

**Phase 3 — stdlib.** Compile `k:htmk`, `k:kcss`, `k:ks`, `k:fp`,
`k:math_utils`, `k:list_utils`, `k:string_utils` to WASM. Verify each
exports the same surface as native.

**Phase 4 — lesson runner.** Replace `web/site/dist/runner.js` with a
loader that pulls `lesson.wasm` (generated at build time per lesson)
and runs it. The "▶ Run" button now executes real Krypton.

**Phase 5 — WASI host.** Add `wasi_snapshot_preview1` imports.
Krypton WASM modules run in wasmtime / wasmer. Opens deploy targets:
Cloudflare Workers (with workers-rs polyfill), Fermyon, etc.

---

## Workflow in code

```krypton
// compiler/wasm32/wasm_self.k (sketch)

module wasm_self

import "k:fs"

// Emit a 32-bit LEB128-encoded unsigned integer.
func wasmLeb128u(n) {
    let out = sbNew()
    while n >= 128 {
        out = sbAppend(out, fromCharCode((n % 128) | 128))
        n = n / 128
    }
    out = sbAppend(out, fromCharCode(n))
    emit sbToString(out)
}

// Emit a section: 1-byte ID, LEB128 length, payload.
func wasmSection(id, payload) {
    emit fromCharCode(id) + wasmLeb128u(len(payload)) + payload
}

func wasmHeader() {
    emit fromCharCode(0) + "asm" + fromCharCode(1) + fromCharCode(0) +
         fromCharCode(0) + fromCharCode(0)
}

// ... (Type, Import, Function, Memory, Export, Code sections)

just run {
    let ir = readFile(arg("0"))
    let mod = wasmHeader() +
              wasmSection(1, buildTypeSection(ir)) +
              wasmSection(2, buildImportSection(ir)) +
              wasmSection(3, buildFunctionSection(ir)) +
              wasmSection(5, buildMemorySection(ir)) +
              wasmSection(7, buildExportSection(ir)) +
              wasmSection(10, buildCodeSection(ir)) +
              wasmSection(11, buildDataSection(ir))
    writeFile(arg("1"), mod)
}
```

`kcc.sh` grows a `--wasm` mode that does:

```bash
"$KCC_EXE" --ir "$SRCFILE" > "$TMPIR"
"$WASM_BIN" "$TMPIR" "$OUTFILE"
```

Same shape as the existing `--native` macho path.

---

## Browser embedding (the lesson runner replacement)

In `web/site/dist/runner.html` (or inline in each lesson page):

```js
async function runLesson(srcText) {
    // Compile in browser via a kcc.wasm (Krypton compiler itself
    // compiled to WASM — phase 5+ ambition). For phase 1 we precompile
    // each lesson at site-build time:
    const lessonId = currentLessonId();
    const wasmBytes = await fetch(`/lessons/${lessonId}.wasm`).then(r =>
        r.arrayBuffer());
    const output = [];
    const imports = {
        env: {
            console_log(ptr, len) {
                const mem = new Uint8Array(instance.exports.memory.buffer);
                output.push(new TextDecoder().decode(mem.slice(ptr, ptr + len)));
            },
            console_log_int(n) { output.push(String(n)); }
        }
    };
    const { instance } = await WebAssembly.instantiate(wasmBytes, imports);
    instance.exports._start();
    return output.join('\n');
}
```

No JS interpreter. The "▶ Run" button runs **real Krypton compiled to
WASM at build time**. Source edits in the contenteditable require a
roundtrip to the server (or eventually a Krypton-compiler-in-WASM).

For lessons-as-written (no in-browser editing of arbitrary `.k`), this
is enough to ship and feels like real execution.

---

## Compatibility with the existing JS bridge

Keep `runner.js` checked in. It stays the fallback path for browsers
that disable WebAssembly (rare) or for the editable-code-box case
(arbitrary source from the user requires a compiler — until we ship
kcc-in-WASM, the JS bridge is the only thing that can run user-edited
code in-page).

Long-term, the JS bridge gets deprecated. Initially they coexist.

---

## Open questions

1. **Funcptr → WASM table.** WASM's `call_indirect` works through a
   table. How do we map Krypton funcptrs (currently raw code pointers)
   to table indices? Probably: every funcptr-taken function gets
   registered in the Element section at build time; funcptrs are
   indices into the table.

2. **GC strategy.** v1 is no-GC. For programs that run to completion,
   that's fine. The lesson runner re-instantiates WASM per click, so
   leaks reset between runs.

3. **Source maps.** Mapping a runtime error back to a Krypton source
   line requires a `.kmap` debug section (or a parallel `.kmap` file).
   Punt to v2.

4. **WASI vs browser split.** Two `kcc --wasm` modes: `--wasm-browser`
   imports only `env.console_log`; `--wasm-wasi` imports
   `wasi_snapshot_preview1`. Or a single output that depends on the
   host's imports being present. The latter is more standard but
   adds complexity. Default to `--wasm-browser`; expose `--wasm-wasi`
   later.

5. **Self-hosting kcc.** Can the Krypton compiler itself compile to
   WASM? Probably yes, once the stdlib subset is ported. Then
   `kcc.wasm` runs in the browser, lessons become *truly* editable in
   the page, and we're fully self-hosted top to bottom. That's the
   "1.0 of in-browser Krypton" milestone.

---

## Timeline (rough)

| Phase | Scope                       | Estimate |
|-------|-----------------------------|----------|
| 0     | Hand-emit hello.wasm        | 1 week   |
| 1     | IR → WASM, lesson 01        | 2 weeks  |
| 2     | Control flow, lessons 1-13  | 2 weeks  |
| 3     | Pure stdlib ports           | 2 weeks  |
| 4     | Replace runner.js per lesson| 1 week   |
| 5     | WASI host                   | 1-2 weeks|
| 6     | kcc.wasm (self-hosted)      | 3-4 weeks|

6-8 weeks to phase 4 (lesson runner is real Krypton). Phase 6 is the
HN-headline moment.

---

## See also

- `compiler/macos_arm64/macho_arm64_self.k` — model for `wasm_self.k`
- `compiler/linux_x86/elf.k`                — second model
- `web/site/dist/runner.js`                 — the bridge to be retired
- `docs/kcss_design.md`                     — sibling module, already shipped
- WebAssembly Binary Encoding spec:
  https://webassembly.github.io/spec/core/binary/index.html
- WASI snapshot preview1:
  https://github.com/WebAssembly/WASI/blob/main/legacy/preview1/docs.md

---

## Phase 0 finding (2026-05-30)

A hand-emit proof (`wasm_proof/hello_wasm.htk`) was written before kcc
gains a `--wasm` mode. **It surfaced a runtime issue:** Krypton strings
drop `\0` bytes (C-string semantics on `fromCharCode(0) + ...` concat),
so any WASM module built via string concat loses every null byte —
which is most of the magic, version, and section structure.

Workarounds and the audit path are documented in
`wasm_proof/FINDING.md`. The existing ELF and Mach-O backends both
emit binaries with embedded `\0`s, so the answer is already in the
codebase; lift their byte-write pattern into a documented helper before
starting Phase 1.

This does not invalidate the design — section layouts, LEB128 encoding,
and the helper structure (`wasmSection`, `leb`, `b`) are correct. The
issue is purely at the byte-IO boundary.

---

## Phase 0 finding (resolved, 2026-05-30)

The Phase 0 hand-emit proof (`wasm_proof/hello_wasm.htk`) now produces
a valid 95-byte `hello.wasm` that loads via `WebAssembly.instantiate`
in JavaScriptCore (verified via `osascript -l JavaScript`) and prints
"Hello" via a host `console_log` import.

The two issues that needed solving were:
1. **Null bytes drop with `fromCharCode(0) + ...` concat.** Fixed by
   using the `writeBytes(path, hexString)` pattern from elf.k —
   encode bytes as `"x" + HH`, let `writeBytes` decode hex pairs.
2. **`s[i]` returns a 1-char string, not an int.** Fixed by using
   `toInt(charCode(s[i]))` (the pattern from stdlib/url.k:35).

Phase 1 (IR → WASM lowering) is unblocked. The proof's helpers
(`hexByte`, `b`, `leb`, `bstr`, `wasmSection`) lift directly into
`compiler/wasm32/wasm_self.k`.
