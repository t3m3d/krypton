// stdlib/objc.k — Krypton wrappers over the Objective-C runtime.
//
// Hides the `objc_msgSend(objc_getClass("…"), sel_registerName("…"), …)`
// boilerplate so user code reads almost like Swift / Obj-C:
//
//   import "k:objc"
//   import "head:cocoa"
//
//   just run {
//       let app = msg(cls(NSApplication_cls), sel_sharedApplication)
//       msg_1(app, sel_setActivationPolicy, NSApplicationActivationPolicyRegular)
//       msg(app, sel_run)
//   }
//
// Three layers:
//   1. cls(name), sel(name)  — raw class/selector lookup with module-local
//                              cache so each name is resolved once.
//   2. msg / msg_1 / … / msg_6 — typed message sends. The suffix is the
//                              EXTRA arg count after (self, sel).
//   3. withPool { ... }      — autorelease pool helper. Allocations made
//                              inside the block drain at exit. Pair with
//                              every Cocoa entry point that creates
//                              temporary objects.
//
// SCAFFOLD — agent m owns the codegen side. The dispatch functions below
// (msg, msg_1, …) all route through the matching objc_msgSend_N variant
// declared in headers/objc.krh. Once macho_arm64_self.k emits the right
// BL instruction for each variant, calls land in libobjc with the
// correct arm64 calling convention (self in x0, SEL in x1, extras in
// x2..x7).

module objc

import "head:objc"
import "head:cocoa"

// ── Class + selector cache ─────────────────────────────────────────────
//
// Naive impl: every `cls("NSWindow")` call goes through objc_getClass,
// every `sel("setTitle:")` goes through sel_registerName. Both are
// idempotent — the runtime returns the same pointer every time — so
// caching their results once per process is a strict win.
//
// We model the cache as a comma-separated `name=ptr` string in a module
// global. This is the same pattern stdlib/gui.k uses for its state
// store; it's GC-safe and survives `gcCollect()`. Real hash-table
// caching is a v2 optimisation.

let _objc_class_cache = ""
let _objc_sel_cache   = ""

func cls(name) {
    let cached = _cache_get(_objc_class_cache, name)
    if cached != "" { emit cached }
    let v = objc_getClass(name)
    _objc_class_cache = _cache_set(_objc_class_cache, name, v)
    emit v
}

func sel(name) {
    let cached = _cache_get(_objc_sel_cache, name)
    if cached != "" { emit cached }
    let v = sel_registerName(name)
    _objc_sel_cache = _cache_set(_objc_sel_cache, name, v)
    emit v
}

// ── Message dispatch ───────────────────────────────────────────────────
// One thin wrapper per arity. The selector name is registered via sel()
// (cached) before the underlying objc_msgSend_N is called.

func msg(obj, selName) {
    emit objc_msgSend(obj, sel(selName))
}

func msg_1(obj, selName, a) {
    emit objc_msgSend_1(obj, sel(selName), a)
}

func msg_2(obj, selName, a, b) {
    emit objc_msgSend_2(obj, sel(selName), a, b)
}

func msg_3(obj, selName, a, b, c) {
    emit objc_msgSend_3(obj, sel(selName), a, b, c)
}

func msg_4(obj, selName, a, b, c, d) {
    emit objc_msgSend_4(obj, sel(selName), a, b, c, d)
}

func msg_5(obj, selName, a, b, c, d, e) {
    emit objc_msgSend_5(obj, sel(selName), a, b, c, d, e)
}

func msg_6(obj, selName, a, b, c, d, e, f) {
    emit objc_msgSend_6(obj, sel(selName), a, b, c, d, e, f)
}

// Float-returning variant (CGFloat / double on arm64). Routes to the
// distinct symbol so the codegen pulls the result from d0 instead of x0.
func msg_fp(obj, selName) {
    emit objc_msgSend_fpret(obj, sel(selName))
}

// ── Convenience: alloc + init in one ───────────────────────────────────
// The classic Obj-C dance:  [[Class alloc] init]
func allocInit(className) {
    let raw = msg(cls(className), sel_alloc)
    emit msg(raw, sel_init)
}

// Convert a Krypton string to an NSString instance. Use whenever a Cocoa
// API wants a CFStringRef / NSString * — setTitle:, setStringValue:, etc.
func nsString(s) {
    emit msg_1(cls(NSString_cls), sel_stringWithUTF8String, s)
}

// ── Autorelease pool ───────────────────────────────────────────────────
// Cocoa's drain-at-scope-exit memory pattern, expressed as a closure.
// Every msg_1(..., sel_autorelease, ...) inside `body` is held until
// drain. Pair with every long-running event loop or batched UI build.
//
//   withPool(func() {
//       let win = makeWindow("Hi", 300, 200)
//       ...
//   })
func withPool(body) {
    let pool = allocInit(NSAutoreleasePool_cls)
    body()
    msg(pool, sel_drain)
}

// `drain` isn't in the canonical sel_* list above — define here.
const sel_drain = "drain"

// ── Internal: comma-separated `name=value` cache ───────────────────────
// Crude but GC-safe. Replace with a proper hashtable once the rest of
// the macOS pipeline is stable.

func _cache_get(table, key) {
    let needle = "," + key + "="
    let body = "," + table
    let p = indexOf(body, needle)
    if p < 0 { emit "" }
    let start = p + len(needle)
    let end = indexOf(substring(body, start, len(body)), ",")
    if end < 0 { emit substring(body, start, len(body)) }
    emit substring(body, start, start + end)
}

func _cache_set(table, key, value) {
    if len(table) == 0 { emit key + "=" + value }
    emit table + "," + key + "=" + value
}
