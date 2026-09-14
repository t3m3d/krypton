module objc

import "head:objc"
import "head:cocoa"

func cls(name) { emit objc_getClass(name) }
func sel(name) { emit sel_registerName(name) }

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
// NSTimer-style: a TimeInterval (ms/1000 -> d0) + target + selector + userInfo + repeats.
func msg_timer(obj, methodSel, ms, target, actionSel, info, rep) {
    emit objc_msgSend_timer(obj, sel(methodSel), ms, target, sel(actionSel), info, rep)
}

func allocInit(className) {
    let raw = msg(cls(className), "alloc")
    emit msg(raw, "init")
}

func nsString(s) {
    emit msg_1(cls("NSString"), "stringWithUTF8String:", s)
}

// Caller drains the pool at scope exit; callbacks need their own pool.
func newPool() {
    emit allocInit(NSAutoreleasePool_cls)
}

func drainPool(pool) {
    msg(pool, "drain")
    emit ""
}

// colorWithRed:green:blue:alpha: — r/g/b as 0-255 ints (/255 -> d0..d2, alpha 1.0).
func msg_rgb(obj, selName, r, g, b) {
    emit objc_msgSend_rgb(obj, sel(selName), r, g, b)
}

// NSSize arg (a->d0, b->d1) — e.g. setSize:/setMaxSize:.
func msg_d2(obj, selName, a, b) {
    emit objc_msgSend_d2(obj, sel(selName), a, b)
}

// Three CGFloat args, used by visual motion APIs.
func msg_d3(obj, selName, a, b, c) {
    emit objc_msgSend_d3(obj, sel(selName), a, b, c)
}

// CGPoint-returning message helpers. Objective-C returns x/y in d0/d1;
// backend converts selected component to Krypton integer coordinates.
func msgPointX(obj, selName, relativeTo) {
    emit objc_msgSend_point_x(obj, sel(selName), relativeTo)
}

func msgPointY(obj, selName, relativeTo) {
    emit objc_msgSend_point_y(obj, sel(selName), relativeTo)
}
