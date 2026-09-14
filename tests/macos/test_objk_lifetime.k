import "k:objk_runtime_macos"

let cleanupTrace = ""
let cleanupReads = 0
let replacementReads = 0

func check(name, expected, actual) {
    if expected != actual {
        kp("[FAIL] " + name + " expected=" + expected + " actual=" + actual)
        exit("1")
    }
    kp("[PASS] " + name)
}

func resourceCleanup(runtime, self) {
    cleanupTrace = cleanupTrace + "R" + okKGet(runtime, self, "id")
    if okKHas(runtime, self, "owner") {
        let owner = okKGet(runtime, self, "owner")
        let replacement = okKGet(runtime, owner, "child")
        check("replacement visible during old cleanup", 2, okKGet(runtime, replacement, "id"))
        replacementReads += 1
    }
    emit 0
}
func cleanupValue(runtime, self) { emit okKGet(runtime, self, "id") }
func baseCleanup(runtime, self) {
    cleanupTrace = cleanupTrace + "B"
    gcCollect()
    check("cleanup message reads", 7, okKSend(runtime, self, "value"))
    let child = okKGet(runtime, self, "child")
    check("cleanup sees owned child", 1, okKRefCount(runtime, child))
    check("cleanup sees zero refs", 0, okKRefCount(runtime, self))
    cleanupReads += 1
    emit 0
}
func derivedCleanup(runtime, self) {
    cleanupTrace = cleanupTrace + "D"
    emit 0
}

just run {
    let runtime = okKRuntime(65536)
    let plain = okKClass(runtime, "Plain", 0)
    doKRegister(runtime, plain)
    let resource = okKClass(runtime, "Resource", 0)
    doKCleanup(runtime, resource, funcptr(resourceCleanup))
    doKRegister(runtime, resource)

    let owner = okKNew(runtime, plain)
    let first = okKNew(runtime, resource)
    let second = okKNew(runtime, resource)
    doKSet(runtime, first, "id", 1)
    doKSet(runtime, first, "owner", owner)
    doKSet(runtime, second, "id", 2)
    doKOwn(runtime, owner, "child", first)
    check("owned assignment retains", 2, okKRefCount(runtime, first))
    doKRelease(runtime, first)
    let before = bufGetQwordAt(runtime, 8)
    doKOwn(runtime, owner, "child", first)
    check("same child stays alive", 1, okKRefCount(runtime, first))
    check("same child does not allocate", before, bufGetQwordAt(runtime, 8))
    check("same child does not clean up", "", cleanupTrace)

    doKOwn(runtime, owner, "child", second)
    check("replacement releases old child", 0, okKRefCount(runtime, first))
    check("replacement runs cleanup", "R1", cleanupTrace)
    check("replacement cleanup runs once", 1, replacementReads)
    check("replacement retains new child", 2, okKRefCount(runtime, second))
    doKRelease(runtime, second)
    doKOwn(runtime, owner, "child", 0)
    check("clear releases owned child", 0, okKRefCount(runtime, second))
    check("clear keeps null field", 0, okKGet(runtime, owner, "child"))
    check("clear runs cleanup once", "R1R2", cleanupTrace)
    doKOwn(runtime, owner, "child", 0)
    doKRelease(runtime, owner)
    check("empty owner does not clean child twice", "R1R2", cleanupTrace)

    let base = okKClass(runtime, "CleanupBase", 0)
    okKMethod(runtime, base, "value", 0, funcptr(cleanupValue))
    doKCleanup(runtime, base, funcptr(baseCleanup))
    doKRegister(runtime, base)
    let derived = okKClass(runtime, "CleanupDerived", base)
    doKCleanup(runtime, derived, funcptr(derivedCleanup))
    doKRegister(runtime, derived)
    let inherited = okKClass(runtime, "CleanupInherited", derived)
    doKRegister(runtime, inherited)
    let parent = okKNew(runtime, inherited)
    let child = okKNew(runtime, resource)
    doKSet(runtime, parent, "id", 7)
    doKSet(runtime, child, "id", 3)
    doKOwn(runtime, parent, "child", child)
    doKRelease(runtime, child)
    okKRetain(runtime, parent)
    doKRelease(runtime, parent)
    check("cleanup waits for final reference", "R1R2", cleanupTrace)
    gcCollect()
    doKRelease(runtime, parent)
    check("derived then base then child cleanup", "R1R2DBR3", cleanupTrace)
    check("cleanup reads exactly once", 1, cleanupReads)
    check("parent tombstoned", 0, okKRefCount(runtime, parent))
    check("owned child tombstoned", 0, okKRefCount(runtime, child))

    let borrowedOwner = okKNew(runtime, plain)
    let borrowed = okKNew(runtime, resource)
    doKSet(runtime, borrowed, "id", 4)
    doKSet(runtime, borrowedOwner, "child", borrowed)
    doKRelease(runtime, borrowedOwner)
    check("borrowed field does not release child", 1, okKRefCount(runtime, borrowed))
    doKRelease(runtime, borrowed)

    let shared = okKNew(runtime, resource)
    doKSet(runtime, shared, "id", 5)
    let firstOwner = okKNew(runtime, plain)
    let secondOwner = okKNew(runtime, plain)
    doKSet(runtime, firstOwner, "child", shared)
    doKOwn(runtime, firstOwner, "child", shared)
    doKOwn(runtime, secondOwner, "child", shared)
    check("two owners retain independently", 3, okKRefCount(runtime, shared))
    doKRelease(runtime, shared)
    doKRelease(runtime, firstOwner)
    check("remaining owner preserves child", 1, okKRefCount(runtime, shared))
    doKRelease(runtime, secondOwner)
    check("last owner releases child", 0, okKRefCount(runtime, shared))
    check("shared child cleans once", "R1R2DBR3R4R5", cleanupTrace)

    let left = okKNew(runtime, plain)
    let right = okKNew(runtime, plain)
    doKOwn(runtime, left, "right", right)
    doKOwn(runtime, right, "left", left)
    doKRelease(runtime, right)
    doKOwn(runtime, left, "right", 0)
    check("explicit cycle break releases peer", 0, okKRefCount(runtime, right))
    check("explicit cycle break preserves caller", 1, okKRefCount(runtime, left))
    doKRelease(runtime, left)

    let root = okKNew(runtime, plain)
    let current = root
    let i = 0
    while i < 64 {
        let next = okKNew(runtime, plain)
        doKOwn(runtime, current, "next", next)
        doKRelease(runtime, next)
        current = next
        i += 1
    }
    doKRelease(runtime, root)
    check("owned chain releases tail", 0, okKRefCount(runtime, current))
}
