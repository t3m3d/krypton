# Cocoa from Krypton — design notes

**Goal:** make KryptScript a viable native-app language for macOS,
the same way Swift is for Apple. End state is a Krypton program that
opens an `NSWindow`, places `NSButton` / `NSTextField` widgets, handles
clicks, and runs the AppKit event loop — all from pure Krypton, no
Objective-C source files in the project.

**Audience:** agent m, who owns `compiler/macos_arm64/macho_arm64_self.k`
and the macOS bootstrap path.

This doc is the architectural sketch behind the scaffold landed
2026-06-01: `headers/objc.krh`, `headers/cocoa.krh`, `stdlib/objc.k`,
`stdlib/cocoa.k`, `examples/cocoa_hello.ks`.

---

## Layer cake

```
  user code (.ks)              ← examples/cocoa_hello.ks
       ↓
  stdlib/cocoa.k               ← cocoaWindow, cocoaButton, cocoaOnClick
       ↓
  stdlib/objc.k                ← cls, sel, msg, withPool, nsString
       ↓
  headers/objc.krh             ← objc_msgSend, objc_getClass, sel_registerName
       ↓
  libobjc.dylib + Foundation + AppKit (system frameworks, already on every Mac)
```

User code never touches `objc_msgSend` directly. The stdlib hides it.
The header layer is the only place a "C symbol" appears.

---

## What works today (after the scaffold)

- All four files parse and the symbols are reachable via `head:objc`,
  `head:cocoa`, `k:objc`, `k:cocoa` imports.
- `cocoa_hello.ks` is grammatically a complete program — `kcc --ir`
  produces clean IR.
- On Windows / Linux it doesn't link (Cocoa symbols don't exist on
  those platforms) — that's expected. The intent is macOS arm64 only.

## State model — caller threads, no module globals

`stdlib/objc.k` and `stdlib/cocoa.k` are **fully stateless**. No
`let` outside function bodies. Same constraint agent m hit while
shipping `stdlib/server_native.k`:

> *Imported Krypton modules export functions only; their top-level
> `let` state does NOT initialize or persist across the import
> boundary.*

Every public function takes its handles as parameters and returns new
ones. The caller is responsible for keeping the app, window, control,
and callback-state handles alive. Concretely:

```krypton
let app = cocoaInit()
let win = cocoaWindow(app, "Hi", 400, 200)
let btn = cocoaButton(win, "OK", 100, 50, 80, 30)
cocoaShow(win, app)
cocoaRun(app)
```

The matching antipattern (DON'T do this):

```krypton
// Inside a stdlib module:
let _app = ""           // ← reads as garbage when called from imported context
func init() { _app = msg(...) }
```

### Closure-capture via associated objects

The single hard case is `cocoaOnClick(button, fnPtr)`. The user wants
the click handler to "see" some local state. Closures via `funcptr` do
NOT capture upvalues at the funcptr-handle level (the funcptr is a
plain code address). The Cocoa-idiomatic fix is
`objc_setAssociatedObject` — attach a Krypton `env` to the button:

```krypton
let state = envNew()
envSet(state, "label", lbl)
envSet(state, "count", "0")
cocoaSetAssoc(btn, state)
cocoaOnClick(btn, funcptr(onClick))

func onClick(sender) {
    let env = cocoaGetAssoc(sender)
    let lbl = envGet(env, "label")
    cocoaSetText(lbl, "clicked")
}
```

The trampoline (`KrCallbackTarget.krDispatch:`) doesn't need to know
anything about the user's state — it just hands the sender to the
Krypton handler and lets the handler walk the associated env.

## What's missing (agent m's work)

1. **`objc_msgSend` arm64 calling convention.** Cocoa's dispatch ABI:
   - `self` in `x0`
   - `SEL` (selector) in `x1`
   - First six extra args in `x2..x7`
   - Float-returning calls drop their result in `d0`, not `x0` — distinct
     code path. Header declares `objc_msgSend_fpret` separately so the
     backend can route the right register.
   - Variadic in C, but Krypton declares fixed-arity variants (`objc_msgSend`,
     `_1`, `_2`, …, `_6`). All resolve to the same `objc_msgSend` symbol
     at link time. The backend just emits `BL _objc_msgSend` for each.
2. **NSRect struct ABI.** `initWithContentRect:styleMask:backing:defer:` and
   `initWithFrame:` take an `NSRect` (= four `CGFloat`s = four doubles
   on arm64). arm64 passes 4 doubles in `d0..d3` for the *first* struct
   arg. `stdlib/cocoa.k` currently packs NSRect into a comma string
   via `_ns_rect(x,y,w,h)`; the backend needs to recognise that handle
   and explode it back into the four FP registers. Pattern to copy:
   look at how Win32's `RECT` is currently passed in `compiler/windows_x86/x64.k`
   (search for `_rect_`).
3. **Callback bridge for `cocoaOnClick`.** Cocoa wants a target/action
   pair, not a function pointer. Implementation sketch:
   - At app startup, register a private Obj-C class (call it
     `KrCallbackTarget`) via `objc_allocateClassPair(NSObject, "KrCallbackTarget", 0)`,
     then `class_addMethod(cls, sel_registerName("krDispatch:"), &kr_callback_trampoline, "v@:@")`.
     `kr_callback_trampoline` is a tiny machine-code stub the backend emits
     (think `~30 bytes` of arm64) that calls into the registered Krypton
     function for the (target, sender) pair.
   - When `cocoaOnClick(btn, fn)` is called, create one instance of
     `KrCallbackTarget`, record `fn` in a global table indexed by
     the instance pointer, then do `btn.setTarget:(instance)` +
     `btn.setAction:(sel_registerName("krDispatch:"))`.
   - When the user clicks, AppKit sends `krDispatch:` to our instance,
     the trampoline finds the Krypton closure in the table, and dispatches.
   - This is the same pattern as the Win32 `WindowProc` trampoline in
     `stdlib/gui.k:_krkWndProc` — just adapted for Obj-C method dispatch.
4. **Autorelease pool integration with the GC.** `withPool { ... }`
   currently does `pool = alloc+init` and `drain` at exit. That's
   correct AppKit-side but the inner `body` closure runs on a fresh
   Krypton GC shadow-stack frame; if it allocates Cocoa objects with
   `nsString(...)` etc., those go on the *Obj-C* autorelease pool, not
   the Krypton GC. The two memory worlds don't intersect — Krypton's
   GC ignores Cocoa objects (they live outside its heap range), and
   Cocoa doesn't know about Krypton GC frames. The pool drain handles
   AppKit cleanup; Krypton's own `gcCollect()` handles the rest. **No
   special interop needed**, just make sure long-running `cocoaRun()`
   loops `gcCollect()` periodically (`stdlib/cocoa.k` should add a
   per-frame hook eventually).

## Conventions worth keeping

- **Selector caching.** Every `sel("foo")` call goes through a module
  global cache (`_objc_sel_cache`). Same name resolves to the same
  cached pointer next time. Doesn't matter for correctness — Cocoa's
  `sel_registerName` is idempotent — but saves a per-call C call.
- **Class caching.** Same pattern with `_objc_class_cache`. Cheap.
- **NSString conversion.** Always `nsString(krStr)` — never pass raw
  Krypton strings into a Cocoa setter. AppKit doesn't know what to do
  with a non-NSString.
- **All allocation through `allocInit`** unless you specifically need
  to call a non-`init` designated initialiser. Keeps the `alloc/init`
  pair atomic so callers can't forget the `init`.
- **`module cocoa` / `module objc` decls.** Both stdlib files declare a
  module; the new `run.k` enforcement (compile.k 2.3) treats library
  files this way. User scripts (`.ks`) that import these without
  declaring their own module are exempt from the warning.

## Future: SwiftUI-equivalent layer

Once the AppKit primitives are stable, a thin reactive layer on top is
~400 lines of Krypton. The recipe:

- Krypton 2.0 closures and the existing `stdlib/fp.k` are enough for a
  signal/effect model (see Solid.js or Svelte 5 runes for the API
  shape).
- A `view` function returns a tree of `cocoa*` widget descriptors
  (just nested structs).
- A diff pass walks two trees and emits the minimum set of
  `cocoaSetText` / `cocoaAddSubview` / `cocoaRemoveFromSuperview`
  mutations.
- Same code structure works for the browser if `stdlib/dom.k` lands
  with the equivalent `domSetText` / `domAppend` primitives — that's
  the "one language, two targets" pitch from `README.md`.

Not in scope today. Land the primitives first; abstractions later.

## Testing strategy

- **Unit:** `examples/cocoa_hello.ks` is the smoke test. If it opens a
  window with a working button on a Mac, the chain works.
- **Layered:** before the smoke test, agent m's macho backend should
  pass a non-GUI Obj-C call — e.g. `kp(msg(cls(NSString_cls),
  sel_stringFromUTF8: "hi"))`. No window, no event loop, just confirms
  `objc_msgSend` calling convention is right.
- **CI:** add to `tests/` once a Mac runner is available. The pattern
  in `tests/wasm/RUN.sh` (diff golden output to `kcc -r`) works
  identically for a Cocoa CLI smoke test.

## Open questions for agent m

- Should the macho backend emit a built-in `kr_objc_init()` that
  resolves the `_objc_msgSend` import at runtime (via `dlsym`), or
  rely on the static link from `-lobjc`? The latter is simpler.
- NSRect packing — does the existing `_rect_` pattern in `x64.k`
  generalise, or does this need a fresh `_nsrect_` handle so the
  Windows backend doesn't accidentally claim NSRect handles when it
  meets one in cross-platform stdlib code?
- Where does `gcCollect()` get called inside `cocoaRun()` — every
  event, every Nth, or via a CFRunLoop observer?

When you've got opinions, land them in this doc; PRs welcome.

---

## Agent M implementation plan + decisions (2026-06-09)

Picking this up. Reconnaissance done. **All work is in `compiler/macos_arm64/macho_arm64_self.k`** (the Krypton-only macho codegen → built into `macho_host` by `kcc` via the `kcc-arm64` frontend + clang, one-time/stale). The krypton-side scaffold (objc.krh/cocoa.krh/objc.k/cocoa.k/cocoa_hello.ks) is complete and unchanged.

**Core lever:** the backend already contains a *working-but-removed* single-import dyld path (`_puts` from libSystem): `emitStubCode` (adrp x16,got@page / ldr / br), `emitGotSlot` (dyld_chained_ptr_64_bind), `emitChainedFixups` (header + starts_in_image + imports + symbols), symtab/strtab, and in-Krypton SHA-256 ad-hoc signing. It's currently dialed to **zero imports** (C-free static). objk = generalize this to **N imports across M dylibs** + wire the objc builtins. NOTE: this re-introduces dynamic linking — a deliberate, macOS-GUI-only exception to the syscall-only C-free model.

**Decisions (answering the doc's open questions):**
- **Static chained-bind imports, not dlsym.** Revive the existing chained-fixups machinery; add `LC_LOAD_DYLIB` for `/usr/lib/libobjc.A.dylib`, `Foundation.framework/Foundation`, `AppKit.framework/AppKit`. Simpler than runtime dlsym, reuses what's there.
- **Phase-1 strings are literals.** Class names + selectors come from `cocoa.krh` consts → emit each unique literal into `__cstring`, pass its vaddr as `char*`. Defer general runtime Krypton-string→`char*` (needed for `nsString(userText)`) to Phase 2.
- **Dedicated `_nsrect` handle** (not shared with Win32 RECT) → unpack to d0..d3. Phase 3.
- **Callbacks last** (Phase 4): `objc_allocateClassPair`/`class_addMethod` + a small arm64 trampoline + funcptr table.

**Phasing (each phase ends in a runnable on-device test):**
- **P1 — msgSend ABI + N-import link.** Generalize layout/stubs/got/fixups/symtab to N symbols; LC_LOAD_DYLIB libobjc+Foundation; builtins `objc_getClass`, `sel_registerName`, `objc_msgSend`(_0.._2), `class_getName`; literal `char*` args; x0 return. **Test:** `kp(class_getName(objc_getClass("NSObject")))` prints `NSObject`; then NSString `stringWithUTF8String:`→`UTF8String` roundtrip prints "hi".
- **P2 — runtime strings + arity.** Krypton string ⇄ `char*`/NSString both directions; full `objc_msgSend_1.._6`; pointer/int return handling.
- **P3 — NSRect + AppKit window.** `_nsrect` → d0..d3; integer/enum args (styleMask) in xN; add AppKit dylib. **Test:** `cocoaWindow`+`cocoaShow`+`cocoaRun` opens a blank NSWindow.
- **P4 — callbacks.** `KrCallbackTarget` class synthesis + `krDispatch:` trampoline + `funcptr` table + setTarget/setAction. **Test:** `cocoa_hello.ks` button updates the label.
- **P5 — polish.** GC/runloop hook in `cocoaRun`, selector/class caches, expand cocoa.krh surface. End: delete `gui_shim.m`/`gui_editor.m`, kryoterm + kcode GUIs become pure Krypton.

**Iteration loop:** edit `macho_arm64_self.k` → `kcc --native t.ks -o /tmp/t` (auto-rebuilds `macho_host`) → `codesign -s - -f /tmp/t` → `/tmp/t`. Recoverable: revert source + rebuild host. Validate the risky Mach-O byte layout in an isolated single-import experiment before touching the live codegen switch.
