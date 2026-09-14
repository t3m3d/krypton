# Krypton Implementation Spec

This is the index and integration contract for the current source checkout,
not a release announcement. Language syntax: [EBNF](grammar/krypton.ebnf) and
[grammar notes](docs/spec/grammar.md). References:
[functions](docs/spec/functions.md), [types](docs/spec/types.md),
[imports](docs/imports.md), [GUI](docs/spec/gui.md).

## Scope Of The Last Three Operations

Documented baseline, in chronological order:

1. `44737cca`: macOS K-owned Objective-K core, module initialization, native
   function-pointer calls, lifetime tests, counter integration, and iOS visuals.
2. `c46a21cf`: integrate Windows changes without dropping macOS/iOS support;
   preserve Windows process/bytes/ConPTY APIs and deployment fixes; rebuild
   the macOS driver and add platform-specific test skips.
3. `c23264f0`: reclaim object/field storage with fresh IDs, reject stale handles,
   and verify churn, weak references, and allocation during cleanup.

These commits do not establish a new published version. README release numbers
remain separate from checkout capabilities. Windows native execution was not
available during this macOS validation; Linux and BSD parity is not implied.

## Language And Compiler Contract

`.k` and `.ks` use the same compiler and syntax. KryptScript can import
Objective-K modules; it is not a separate Objective-K interpreter. The driver
can wrap script statements in an entry block. Explicit `just run` remains valid.

The K-owned object API currently consists of ordinary function calls and
imports. It introduces no method, inheritance, protocol, ownership, or handle
keywords. Existing `class`/`struct`/`type` declarations are not automatically
K-owned runtime classes. Typed methods and protocol declarations remain planned.

Use `-> do` for an explicit no-result contract. Do not add `void` declarations
to new APIs. The unannotated cleanup callbacks in the prototype return an
ignored value; that is not a new return-type rule.

### Imported Globals

`compiler/compile.k` collects module-scope `let`/`const` initializers from files
found by the existing import walker. Their initialization IR is prepended to
executable `__main__` in dependency-first traversal order, before entry work.
Imported functions can read and mutate module globals; local declarations and
parameters continue to shadow them.

Limits: the current walker handles its existing one dependency layer, not an
arbitrary transitive graph. This change does not supply namespaces, entryless
DLL initialization, or imported floating-point type propagation. Do not assume
cyclic imports have defined initialization semantics.

### Native Indirect Calls On macOS arm64

`callPtr(pointer, arg0, ...)` accepts zero through eight native Krypton
arguments. The pointer is not counted among those arguments. Object methods
pass `(runtime, self)` plus zero, one, or two user arguments; cleanup passes
only `(runtime, self)`.

The Mach-O emitter preserves native boxed values and returns. Generated
`BUILTIN callPtr` IR requires one through nine total operands. Missing pointer
or excess arguments produce `callPtr needs a pointer and 0..8 arguments`.
Null pointers trap before branching; the checker expects SIGTRAP/exit 133.
Function signature correctness remains the caller's responsibility. This is
not a generic foreign ABI, closure-capture ABI, or compiler-checked method call.
Handwritten IR must not bypass the builtin validation with an unrelated CALL.

## K-Owned Objective-K On macOS

Implementation: [stdlib/objk_runtime_macos.k](stdlib/objk_runtime_macos.k).
Usage and lifetime examples: [runtime guide](docs/objk_runtime_macos.md).
No Cocoa, Foundation, AppKit, UIKit, or libobjc imports belong to this core.
Existing GUI adapters still use native Apple frameworks. Choc/OKUI changes
the app-facing API; it does not yet replace Apple's windowing implementation.

### Public API

| API | Contract |
| --- | --- |
| `okKRuntime(capacity)` | Rooted arena, 64..1048576 bytes; small capacities may not fit records. |
| `okKText(runtime, text)` / `okKTextValue` | Copy text into arena / return text value. |
| `okKClass(runtime, name, parent)` | Nonempty name; parent 0 or registered class. |
| `okKClassName` | Retrieve stored class name. |
| `okKMethod(runtime, klass, name, arity, pointer)` | Before sealing; unique nonempty name, nonnull pointer, arity 0..2. |
| `doKCleanup(runtime, klass, pointer)` | Before sealing; one nonnull cleanup callback per class. |
| `doKRegister(runtime, klass)` | Seal class; instance creation then permitted. |
| `okKNew(runtime, klass)` | Live instance with one independent reference. |
| `okKObjectClass` / `okKIsA` | Dynamic class / ancestry check. |
| `okKResponds` | Check method lookup on a readable object. |
| `okKSend` / `okKSend1` / `okKSend2` | Dispatch with matching user-argument count. |
| `okKSuper(runtime, object, definingClass, name)` | Zero-user-argument dispatch from defining class's parent. |
| `doKSet(runtime, object, name, value)` | Borrowed integer/arena ID, range -1000000000..1000000000. |
| `doKOwn(runtime, object, name, child)` | Retain new child before replacement; release previous owned child; 0 clears. |
| `doKWeak(runtime, object, name, target)` | No retain/release; read as 0 once target starts releasing. |
| `okKHas` / `okKGet` | Distinguish absent field from stored 0 / read field. |
| `okKRetain` / `doKRelease` | Balanced manual ownership; reference-count overflow rejected. |
| `okKRefCount` | Count for object ID; 0 for previously issued ID whose storage was freed. |

Functions for allocation, lookup, raw record access, invocation, and freeing
are implementation helpers, not supported app APIs. In particular, do not call
`doKFree` directly or modify arena bytes. This prototype has no module-private
access enforcement; its checks are not a security boundary against buffer writes
or guessed valid IDs.

### Dispatch And Lifetime

Lookup starts at dynamic class and walks ancestors. Child methods override
matching names. Unknown methods, wrong arity, invalid IDs/kinds, and invalid
ownership operations fail with an `Objective-K:` diagnostic and exit 1.
`super` validates that its defining class belongs to the object's ancestry.

Borrowed fields do not manage references. Owned and weak policies cannot be
overwritten by `doKSet` or converted to each other; a borrowed field can acquire
either policy. Clearing with the matching API preserves that policy. Getters
return borrowed values: retain before keeping an independent object reference.
Strong cycles are not collected. Break them explicitly or use weak back-links.

Final release sets references to 0 and state to releasing. It runs cleanup
most-derived first through all ancestors, then releases owned children and
reclaims private field names, field records, and the object record. Cleanup may
read fields, send read-only messages, run GC, and allocate other objects. It
cannot retain, release again, mutate, or install the releasing object in an
owned/weak field. Weak references to it already read 0. Hooks are automatic;
do not invoke parent cleanup manually. Field-release order is unspecified.
Failures are fail-fast, with no exception unwinding or transactional rollback.

### Arena And IDs

The runtime buffer must remain reachable while any ID is in use. Records store
integer IDs, not interior heap pointers: macOS GC does not traverse this object
graph. External native control/code pointers must not be placed in value fields.
Keep native controls separately, as the counter demo does.

Arena header qwords: capacity at 0, high-water end at 8, next ID at 16;
allocation blocks begin at 32. Each block has total aligned size and issued ID
in a 16-byte header, followed by payload. Payload kinds are class 1, method 2,
object 3, field 4, text 5; free payloads use 0 and allocation initialization uses
6. Class payload is 48 bytes; method/object/field payloads are 40 bytes; text
payload is 16 bytes plus copied bytes, rounded to qword alignment. These are
internal layouts, not a serialized format or a stable ABI.

IDs start at 24 and increase by 16. Every allocation, including reused storage,
gets a fresh ID. Lookup scans block headers rather than treating an ID as an
offset. Stale strong access fails; weak reads remain 0 after slot reuse.
`okKRefCount` cannot recover a freed record's original kind, so callers must
pass object IDs, not arbitrary previously issued IDs. Do not add offsets to IDs.
IDs are local to their runtime; cross-runtime identity is not encoded.

Allocation uses first-fit free blocks or appends at high-water end. No block
splitting, coalescing, or compaction exists. Variable-sized workloads can
fragment the arena despite unused bytes. Classes, methods, their names, and
caller-created text are not individually reclaimed. The whole arena is
host-GC-owned. Fresh IDs fail before exceeding the integer guard instead of
wrapping, after approximately 62 million allocations per runtime. Neither
unbounded allocation nor thread safety is promised.

## GUI, iOS, And Deployment Integration

The macOS counter demonstrates a K-owned model, owned state, read-only dispatch,
native callbacks, and exactly-once cleanup on `Quit`. Native window handles must
stay raw pointers: converting `okWindow` results to text previously caused a
`setMinSize:` crash. [Demo](examples/objk/k_owned_counter_macos.ks).

`kweb` uses `k:okui`; its global app menu has `Quit` with Command-Q and Edit
actions. Closing a window alone is not documented as terminating the app.
Its bundle name is `kweb.app`. [Build/deploy guide](web/README.md).

FTP remote paths are relative to the account root. Empty folder means root;
`test` places `dist/index.html` at `test/index.html`. Do not automatically insert
`public_html`: Hostinger accounts already rooted there would create a duplicate
directory. CLI and both GUIs retain remote-path normalization, parent-traversal
rejection, quoting guards, and fail-fast upload behavior. A smoke build is not
proof of a live FTP deployment. Website output is `web/site/dist`; preserve its
existing design and separate platform release information.

The same macOS-hosted arm64 emitter supports `ios-sim-arm64` and
`ios-device-arm64` profiles. `-r` cannot directly execute an iOS target on macOS;
use the bundle script and simulator. UIKit/Objective-C/SpriteKit remain backend
dependencies. `k:visual` supports scene shapes, labels, sprites, one-shot motion,
physics bodies, touch coordinates, and interpolated painting. Painting still
adds circle nodes, not a retained vector stroke, and needs node-budget/performance
work for long sessions. Repeat/sequence action ABI wrappers, device signing,
device execution, and distribution remain separate work.
[iOS roadmap](docs/ios_native_roadmap.md), [examples](examples/ios/README.md).
iOS feature work remains paused while macOS core hardening proceeds.

## Windows Merge Boundaries

Windows retains `--target windows-x86_64` (`windows-x64` alias) on Windows hosts
and `--subsystem console|windows` (`gui` alias for windows). Default is console;
GUI emits PE subsystem 2, console emits 3. Driver source selection consumes
target/output/subsystem flag values rather than treating them as source files.
These flags do not enable PE compilation on the macOS host.

Preserved incoming work includes wide process creation, environment/job APIs,
Windows header structs, bytes/file helpers, argv/environment encoding, ConPTY,
and Win32 colors/flat controls. Do not port these modules by swapping platform
names: memory representation, FFI structs, and runtime imports need validation.
No Windows executable tests were run here. Backend IR generation and driver
argument checks do not substitute for Windows runtime tests.

## Validation And Outstanding Work

Run from checkout root with current macOS bootstrap artifacts:

```sh
export KRYPTON_ROOT="$PWD"
./bootstrap/kcc_driver_macos_aarch64 -r scripts/check_objk_runtime_macos.ks
./bootstrap/kcc_driver_macos_aarch64 -r scripts/check_objk_runtime_macos.ks --gui
./bootstrap/kcc_driver_macos_aarch64 -r scripts/check_okui.ks
./bootstrap/kcc_driver_macos_aarch64 -r scripts/check_ios.ks
./build.sh test
```

`--gui` needs a desktop session. The intentional null-call trap is expected,
not a checker regression. Core checks cover imports, indirect calls, ancestry,
dispatch, text, fields, lifetime/cleanup, weak references, and failure cases;
they inspect dependencies to reject Apple object frameworks. Reuse tests run
2,000 object/field/name cycles in a 1KB arena without high-water growth, test
expired weak IDs and stale strong access, GC, and allocation during cleanup.

Last recorded full macOS suite after integration: 70 pass, 1 failure
(`test_negative_nums.k` assertion), 8 skips. This is not an all-green release
gate. Win32 tests are skipped off Windows; macOS additionally skips
`test_bytes.k` and `test_process_win_argv.k` because `ptrAdd`/`ptrToInt` are
not emitted there. Generic-looking module names do not establish parity.

Next work, in order:

1. Harden allocator behavior for fragmented/variable-size workloads and design
   explicit text ownership. Preserve stale-ID and cleanup reentrancy tests.
2. Specify typed method arguments/results, registration compatibility and
   override rules; validate signatures before native calls. Then add compiler
   diagnostics and tests. Metadata alone is not compile-time type safety.
3. Specify protocols/interfaces, inherited conformance and required-method
   checks. Keep proposed syntax separate until parser/codegen support lands.
4. Move more Choc widget state/events into K-owned objects and generate native
   adapters without losing pointer identity or platform ABI correctness.
5. Repair remaining macOS pointer primitives, negative-number regression, import
   graph depth/global type propagation, then run platform-specific parity tests.

Do not claim ARC, cycle collection, thread-safe dispatch, dispatch caching,
compiler-native Objective-K class syntax, a Cocoa replacement, or a released
2.4.6 from this work. Rebuild compiler/driver seeds only when compiler/driver
source changes; runtime-module edits are compiled into their consuming programs.
