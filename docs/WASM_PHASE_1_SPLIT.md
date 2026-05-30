# WASM Phase 1 — work split for two agents

**Goal:** lessons 1-7 of `tutorial/` produce a runnable `.wasm` that
prints the same output as `kcc -r tutorial/0X.k`.

**Two agents, no overlap.** Agent A produces `.wasm` bytes. Agent B
consumes them. They meet at one shared file — `docs/WASM_HOST_ABI.md` —
which documents the host imports the emitted modules expect. Pin that
file first; everything else hangs off it.

---

## Shared contract (write FIRST, then split)

**File:** `docs/WASM_HOST_ABI.md` (~50 lines, both agents read; either
writes the first cut).

Locks the import surface so emitter and loader can't drift apart:

```
Module: env
  console_log(ptr: i32, len: i32) -> ()        # write [ptr..ptr+len) to host stdout
  console_log_int(v: i32) -> ()                # print decimal int + newline
  console_log_int64(hi: i32, lo: i32) -> ()    # 64-bit fallback (2x i32)
  console_log_f64(v: f64) -> ()                # print decimal float + newline

Memory: exported as "memory", initial 1 page (64 KiB).
Entry:  exported as "_start", () -> ().

Strings: pointer + length (no null terminator). Encoding: UTF-8.
```

Both agents code against this. Anything either side needs added →
edit `WASM_HOST_ABI.md` first, then commit, then implement.

---

## Agent A — emitter (Krypton-side)

**Owns:** `compiler/wasm32/wasm_self.k` (only file).

**Already done (Phase 1.0):** skeleton, byte-emit helpers, hardcoded
"Hello" module. Compiles + emits a valid 95-byte .wasm.

**Phase 1.1 — IR-driven sections (~1 day)**
- Read the .kir text (already wired).
- Parse `FUNC <name> <nparams>` headers + `END` markers into per-func
  IR blocks. Treat anything between as the body.
- Build a function table: name → index, signature.
- Emit Type/Function/Export sections from that table (one type entry
  per unique signature; one export per non-private func; `_start` is
  the body of `just run { ... }`, which IR names `__main__`).
- Done when: empty-bodied IR → valid `.wasm` with correct function
  decls + exports, even if every body just `nop`s.

**Phase 1.2 — constants + arithmetic + `kp` (~2 days)**
- Lower these IR opcodes:
  - `PUSH <int|"string">`  → `i32.const` (for ints) or string table
    address (for strings).
  - `STORE <local>` / `LOAD <local>` → `local.set` / `local.get`.
  - `ADD` / `SUB` / `MUL` / `DIV` / `MOD` → `i32.add` etc.
  - `POP` → `drop`.
  - `BUILTIN kp N` → load string ptr+len, `call $console_log`.
- Build a string table in the Data section; record byte offsets so
  `PUSH "x"` emits `i32.const <offset_to_x>`.
- Done when: `tutorial/01_hello_world.k` and `02_variables.k` produce
  `.wasm` whose console_log output matches `kcc -r` output exactly.

**Phase 1.3 — function calls (~2 days)**
- Lower `BUILTIN <userFunc> N` → `call $<userFunc>`.
- Track parameter shapes per function so the call site emits the right
  arg order.
- Done when: `tutorial/07_functions.k` (fib + recursion + multiple
  funcs) produces matching output.

**Phase 1.4 — control flow (~2 days)**
- Lower `JUMPIF` / `JUMPIFNOT` / `JUMP <label>` into WASM
  `block`/`loop`/`if`/`br` structured-control-flow. WASM doesn't have
  goto; everything has to wrap into a labeled block.
- Done when: lessons 05 (conditionals), 06 (while), 23 (for-in) all
  match `kcc -r`.

**Out of Agent A's scope (later phases):**
- Strings >stack (string ops as builtins)
- Dynamic dispatch
- Stdlib funcs
- GC

**Verification command (run after each phase):**
```bash
kcc --ir tutorial/0X.k > /tmp/0X.kir
./compiler/wasm32/wasm_self /tmp/0X.kir /tmp/0X.wasm
node scripts/run_wasm.js /tmp/0X.wasm > /tmp/0X.out
diff <(kcc -r tutorial/0X.k) /tmp/0X.out    # must be empty
```

(`run_wasm.js` is Agent B's deliverable.)

---

## Agent B — host loader + test harness

**Owns:** four files, none shared with Agent A.

- `scripts/run_wasm.js`  (Node CLI test runner)
- `scripts/run_wasm.sh`  (osascript wrapper for the Mac, since Node
  isn't always installed)
- `tests/wasm/RUN.sh`    (loops every tutorial through the verifier)
- `web/site/dist/wasm_runner.js`  (browser-side WASM loader that
  replaces runner.js's JS-bridge path when a `.wasm` for the lesson
  exists)

**Phase B.1 — Node test runner (~1 day)**

```js
// scripts/run_wasm.js   ← Agent B writes this
// Usage: node run_wasm.js path/to/lesson.wasm
const fs = require('fs');
const wasmBytes = fs.readFileSync(process.argv[2]);
const out = [];
const dec = new TextDecoder();
const imports = {
  env: {
    console_log(ptr, len) {
      const mem = new Uint8Array(instance.exports.memory.buffer);
      out.push(dec.decode(mem.slice(ptr, ptr + len)));
    },
    console_log_int(v)     { out.push(String(v)); },
    console_log_int64(h,l) { out.push(String(BigInt.asUintN(32,BigInt(h)) << 32n | BigInt.asUintN(32,BigInt(l)))); },
    console_log_f64(v)     { out.push(String(v)); },
  }
};
let instance;
WebAssembly.instantiate(wasmBytes, imports).then(({instance: i}) => {
  instance = i;
  i.exports._start();
  process.stdout.write(out.join(''));
});
```

Make it work for the Phase-0 "Hello" module first (existing
`/tmp/hello.wasm`). That's the smoke test before Agent A starts
producing real `.wasm`.

**Phase B.2 — osascript fallback (~half day)**
Same logic, but using JavaScriptCore (`osascript -l JavaScript`).
For machines without Node. Pattern matches the approach in
`wasm_proof/FINDING.md`.

**Phase B.3 — tutorial loop (~half day)**
```bash
# tests/wasm/RUN.sh   ← Agent B writes this
for k in tutorial/[0-9][0-9]_*.k; do
    name=$(basename "$k" .k)
    kcc --ir "$k" > "/tmp/$name.kir"
    ./compiler/wasm32/wasm_self "/tmp/$name.kir" "/tmp/$name.wasm" 2>/dev/null || { echo "SKIP $name (emitter)"; continue; }
    expected=$(kcc -r "$k" 2>/dev/null)
    actual=$(node scripts/run_wasm.js "/tmp/$name.wasm" 2>/dev/null)
    if [[ "$expected" == "$actual" ]]; then
        echo "PASS $name"
    else
        echo "FAIL $name"
    fi
done
```

**Phase B.4 — browser WASM loader (~1 day, can wait for Agent A's
Phase 1.2 to land)**
Drop-in for `web/site/dist/wasm_runner.js`. The Run button in lessons
prefers `<slug>.wasm` if the site ships one; falls back to the existing
JS bridge `runner.js`. Architecture diff: when `/learn/<slug>.wasm`
exists, fetch+instantiate+run+capture output exactly like
`run_wasm.js`. Output goes into the same `.run-out` element.

The build step (Agent A's `wasm_self`) produces these
`.wasm` files at site build time:

```
dist/learn/01_hello_world.wasm
dist/learn/02_variables.wasm
...
```

`export.htk` gains a small loop in `just run { ... }` to call
`wasm_self` for each `lessonFiles()` entry. Agent B specs this hook
in their PR; Agent A's emitter just needs to exist.

---

## Suggested sync schedule

| When | What |
|---|---|
| T+0    | Both: write/review `docs/WASM_HOST_ABI.md`. Lock the contract. |
| T+1d   | Agent A: Phase 1.1 lands. Agent B: Phase B.1 lands (smoke-tests with Phase-0 hello.wasm). |
| T+3d   | Agent A: Phase 1.2 (lesson 01-02 match). Agent B: Phase B.3 (tutorial loop). |
| T+5d   | Agent A: Phase 1.3 (lesson 07). Agent B: Phase B.4 (browser loader). |
| T+7d   | Agent A: Phase 1.4 (lessons 05/06/23). Agent B: tutorial loop reports 7+ PASS. |
| T+10d  | Phase 1 milestone: lessons 1-7 ship as real Krypton WASM in the playground. |

If either agent finishes ahead of the other, work on phase 1.5 / B.5
(strings + tagged-pointer encoding) — that's the next-hardest item and
needs ABI design first.

---

## Conflict avoidance rules

1. **Never both write `wasm_self.k`.** Agent A owns it. If Agent B
   needs something from it, file an issue describing the contract
   change, Agent A implements.
2. **Never both write `run_wasm.js`** or `wasm_runner.js`. Agent B
   owns those.
3. **`docs/WASM_HOST_ABI.md` is locked** — additions only through PR
   with both agents reviewing. Removals not allowed mid-phase.
4. **Compile-side regressions:** if Agent A's emitter breaks (e.g.
   `kcc --c compiler/wasm32/wasm_self.k` fails), Agent B doesn't try to
   fix it; surface the breakage and Agent A reverts.
5. **Runtime regressions** (a `.wasm` that used to work now crashes
   the host): Agent B reports the failing wasm + expected output;
   Agent A debugs.

## Output of Phase 1 (definition of done)

- `kcc --wasm tutorial/01_hello_world.k -o /tmp/hello.wasm` produces a
  module that, when loaded by `scripts/run_wasm.js`, prints exactly
  what `kcc -r tutorial/01_hello_world.k` prints.
- Same for lessons 02-07.
- The Hacker News thread for Krypton 2.1.1 gets a follow-up post:
  "Phase 1 done — Krypton compiles to WASM, tutorials 1-7 run in your
  browser." That's the milestone.

## See also

- `docs/wasm_backend_design.md` — the long-arc design
- `wasm_proof/hello_wasm.htk` — the Phase 0 proof
- `compiler/wasm32/wasm_self.k` — Agent A's working file
- `compiler/macos_arm64/macho_arm64_self.k` — the architectural twin
  Agent A should mirror (same shape: read IR, emit binary)
