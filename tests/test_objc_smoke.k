// Non-GUI Obj-C smoke test (macOS arm64 only).
//
// The "layered" objc test the cocoa design doc (docs/cocoa_design.md) asks for:
// exercise the objc_msgSend calling convention + the dyld chained-bind import
// path WITHOUT opening a window or entering the AppKit run loop. If this passes,
// the foreign-call ABI is sound; cocoa_hello.ks (the GUI smoke test) builds on it.
//
// Regression guard: the objc emitter hardcodes per-variant instruction counts
// (cfCount). A mismatch corrupts bl offsets → SIGBUS/SIGILL on EVERY objc program
// (bit us twice — see commits a4d2d123, f453601f). There was no objc test in the
// suite to catch it. This is that test.
//
// macOS-only: Linux/Windows have no libobjc — build.sh skips it there.
import "k:objc"
import "head:objc"

just run {
    // 1. objc_getClass + class_getName (char* in, char* out — no msgSend yet).
    let nsObj = objc_getClass("NSObject")
    if class_getName(nsObj) != "NSObject" { kp("[FAIL] objc_getClass NSObject"); exit("1") }
    let nsStrCls = objc_getClass("NSString")
    if class_getName(nsStrCls) != "NSString" { kp("[FAIL] objc_getClass NSString"); exit("1") }

    // 2. NSString roundtrip — exercises objc_msgSend with a pointer/string return
    //    and Krypton-string <-> char*/NSString conversion both directions (P2).
    let ns = nsString("hello-objc")
    if msg(ns, "UTF8String") != "hello-objc" { kp("[FAIL] NSString UTF8String roundtrip"); exit("1") }

    // 3. objc_msgSend with an integer return.
    if msg(ns, "length") != 10 { kp("[FAIL] NSString length"); exit("1") }

    kp("[PASS] objc smoke: getClass + msgSend (string + int return)")
}
