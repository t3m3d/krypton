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
// FULLY STATELESS — no module-level `let`. Same constraint agent m
// hit shipping `stdlib/server_native.k`: imported Krypton modules
// export functions only; top-level `let` state does NOT persist across
// the import boundary. So everything here takes its inputs from the
// caller and returns values back; no hidden caches, no globals.
//
// Performance note: `objc_getClass` and `sel_registerName` are
// idempotent runtime hash lookups — fast enough that a per-call cache
// isn't worth the state-management complexity. If profiling later
// shows hot spots on selector resolution, the caller can hoist a
// `let SEL_setTitle = sel("setTitle:")` out of any loop, paying the
// lookup cost once at startup.

module objc

import "head:objc"
import "head:cocoa"

// ── Class + selector lookup ────────────────────────────────────────────

func cls(name) { emit objc_getClass(name) }
func sel(name) { emit sel_registerName(name) }

// ── Message dispatch ───────────────────────────────────────────────────
// One thin wrapper per arity. The selector name is resolved through
// sel() each call; for hot loops, hoist via `let s = sel("foo:")`.

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

// Float-returning variant (CGFloat / double on arm64 lands in d0, not
// x0, so a distinct entry point is needed).
func msg_fp(obj, selName) {
    emit objc_msgSend_fpret(obj, sel(selName))
}

// NSRect-taking initialisers. The backend lowers these specially: the 4 rect
// CGFloats go in d0..d3 (arm64 struct ABI), trailing ints in x2.. — what
// objc_msgSend needs for initWithContentRect:styleMask:backing:defer: and
// initWithFrame:.
func msg_rect(obj, selName, x, y, w, h, mask, backing, deferF) {
    emit objc_msgSend_rect(obj, sel(selName), x, y, w, h, mask, backing, deferF)
}
func msg_frame(obj, selName, x, y, w, h) {
    emit objc_msgSend_frame(obj, sel(selName), x, y, w, h)
}
// one CGFloat arg (e.g. fontOfSize:, setAlphaValue:) — lands in d0.
func msg_d1(obj, selName, n) {
    emit objc_msgSend_d1(obj, sel(selName), n)
}
// NSRect arg (d0..d3) + one pointer arg (x2) — e.g. drawInRect:withAttributes:.
func msg_rectp(obj, selName, x, y, w, h, p) {
    emit objc_msgSend_rectp(obj, sel(selName), x, y, w, h, p)
}

// ── Convenience ────────────────────────────────────────────────────────

// [[Class alloc] init] in one call. (Selectors inlined — head consts don't
// survive the native import boundary.)
func allocInit(className) {
    let raw = msg(cls(className), "alloc")
    emit msg(raw, "init")
}

// Convert a Krypton string to an NSString. Use any time a Cocoa setter
// wants an `NSString *` argument: setTitle:, setStringValue:, etc.
func nsString(s) {
    emit msg_1(cls("NSString"), "stringWithUTF8String:", s)
}

// ── Autorelease pool — caller-held handle ──────────────────────────────
// Cocoa's drain-at-scope-exit memory pattern. The pool is just a regular
// NSAutoreleasePool instance; the caller is responsible for `drainPool`
// at the matching scope-end.
//
//   let pool = newPool()
//   let win  = makeWindow(...)
//   drainPool(pool)
//
// Encouraged at the top of every event-callback that allocates Cocoa
// objects, so autoreleased instances don't pile up between events.

func newPool() {
    emit allocInit(NSAutoreleasePool_cls)
}

func drainPool(pool) {
    msg(pool, "drain")
    emit ""
}
