// Test suite for the short-form runtime API + missing subsystems.
import "k:objc"
import "k:objk"

let fails = 0
func ok(name, cond) {
    if cond == 1 { print("[PASS] " + name) } else { print("[FAIL] " + name); fails = fails + 1 }
    emit cond
}
func checkFn() { emit 777 }

just run {
    print("objk full-suite")

    // Selector cache: identity check.
    let a = okSel("alloc")
    let b = okSel("alloc")
    ok("sel cache identity", okSameHandle(a, b))

    // Selector cache: 10,000 repeated lookups.
    let i = 0
    let h = 0
    while i < 10000 {
        h = okSel("alloc")
        i = i + 1
    }
    ok("sel cache 10k lookups", h == b)

    // Explicit autorelease pool scoping.
    let pool = okPoolPush()
    ok("pool push returns non-zero", (pool - 0) != 0)
    okPoolPop(pool)

    // Dynamic subclass + method injection.
    let mainPool = newPool()
    let c = objc_allocateClassPair(cls("NSObject"), "KTestWidget", 0)
    ok("class pair allocated", (c - 0) != 0)

    let addRc = class_addMethod(c, sel("krMeaning"), funcptr(checkFn), "q@:@")
    ok("method added", (addRc - 0) != 0)
    objc_registerClassPair(c)

    let inst = msg_1(c, sel("alloc"), sel("init"))
    ok("instance allocated", (inst - 0) != 0)
    let meaning = msg(inst, "krMeaning")
    ok("injected method returns 777", meaning == 777)

    // Zeroing weak references.
    let loc = bufNew(8)
    let zeroByte = 0
    let zi = 0
    while zi < 8 { bufSetByte(loc, zi, zeroByte); zi = zi + 1 }
    let obj = msg_1(cls("NSObject"), sel("alloc"), sel("init"))
    okWeakSet(loc, obj)
    msg(obj, "release")
    let loaded = okWeakGet(loc)
    ok("weak load returns zeroed", loaded == 0)

    msg(inst, "release")
    drainPool(mainPool)

    print("objk full-suite done")
    if fails > 0 { print("FAILED"); exit("1") }
    exit("0")
}
