import "k:objk_runtime_macos"

let weakCleanupCount = 0

func check(name, expected, actual) {
    if expected != actual {
        kp("[FAIL] " + name + " expected=" + expected + " actual=" + actual)
        exit("1")
    }
    kp("[PASS] " + name)
}

func weakCleanup(runtime, self) {
    check("weak parent zero during release", 0, okKGet(runtime, self, "parent"))
    check("weak self zero during cleanup", 0, okKGet(runtime, self, "self"))
    weakCleanupCount += 1
    emit 0
}

just run {
    let runtime = okKRuntime(65536)
    let base = okKClass(runtime, "Base", 0)
    doKRegister(runtime, base)
    let observer = okKNew(runtime, base)
    let first = okKNew(runtime, base)
    let second = okKNew(runtime, base)
    doKSet(runtime, observer, "target", 0)
    doKWeak(runtime, observer, "target", first)
    check("weak assignment does not retain", 1, okKRefCount(runtime, first))
    check("weak reads live target", first, okKGet(runtime, observer, "target"))
    let before = bufGetQwordAt(runtime, 8)
    doKWeak(runtime, observer, "target", second)
    check("weak replacement does not allocate", before, bufGetQwordAt(runtime, 8))
    check("weak replacement does not release old target", 1, okKRefCount(runtime, first))
    check("weak replacement does not retain new target", 1, okKRefCount(runtime, second))
    doKRelease(runtime, second)
    check("weak reads dead target as zero", 0, okKGet(runtime, observer, "target"))
    check("expired weak field still exists", 1, okKHas(runtime, observer, "target"))
    let fresh = okKNew(runtime, base)
    check("new allocation does not revive weak target", 0, okKGet(runtime, observer, "target"))
    doKWeak(runtime, observer, "target", first)
    doKWeak(runtime, observer, "target", 0)
    check("weak clear", 0, okKGet(runtime, observer, "target"))
    doKWeak(runtime, observer, "target", first)
    gcCollect()
    check("weak offset survives GC", first, okKGet(runtime, observer, "target"))
    doKRelease(runtime, observer)
    check("observer release leaves weak target alive", 1, okKRefCount(runtime, first))
    doKRelease(runtime, first)
    doKRelease(runtime, fresh)

    let childClass = okKClass(runtime, "Child", base)
    doKCleanup(runtime, childClass, funcptr(weakCleanup))
    doKRegister(runtime, childClass)
    let parent = okKNew(runtime, base)
    let child = okKNew(runtime, childClass)
    doKOwn(runtime, parent, "child", child)
    doKWeak(runtime, child, "parent", parent)
    doKWeak(runtime, child, "self", child)
    check("weak back-reference does not form strong cycle", 1, okKRefCount(runtime, parent))
    doKRelease(runtime, child)
    doKRelease(runtime, parent)
    check("weak graph releases parent", 0, okKRefCount(runtime, parent))
    check("weak graph releases child", 0, okKRefCount(runtime, child))
    check("weak graph cleanup once", 1, weakCleanupCount)
}
