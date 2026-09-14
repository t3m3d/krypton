import "k:objk_runtime_macos"

let reuseCleanupCount = 0

func churnCleanup(runtime, self) {
    let temporary = okKNew(runtime, okKGet(runtime, self, "temporaryClass"))
    doKSet(runtime, temporary, "value", 99)
    doKRelease(runtime, temporary)
    if okKGet(runtime, self, "value") != 7 { kp("[FAIL] cleanup storage reused early"); exit("1") }
    reuseCleanupCount += 1
    emit 0
}

func check(name, expected, actual) {
    if expected != actual {
        kp("[FAIL] " + name)
        exit("1")
    }
    kp("[PASS] " + name)
}

just run {
    let runtime = okKRuntime(1024)
    let klass = okKClass(runtime, "Reusable", 0)
    doKRegister(runtime, klass)
    let observer = okKNew(runtime, klass)
    let first = okKNew(runtime, klass)
    doKSet(runtime, first, "value", 42)
    doKWeak(runtime, observer, "target", first)
    doKRelease(runtime, first)
    let highWater = bufGetQwordAt(runtime, 8)
    let i = 0
    while i < 2000 {
        let object = okKNew(runtime, klass)
        if object == first { kp("[FAIL] reused ID"); exit("1") }
        doKSet(runtime, object, "value", i)
        if okKGet(runtime, object, "value") != i { kp("[FAIL] reused field"); exit("1") }
        if okKGet(runtime, observer, "target") != 0 { kp("[FAIL] revived weak target"); exit("1") }
        doKRelease(runtime, object)
        i += 1
    }
    check("object, field, and field name storage reused", highWater, bufGetQwordAt(runtime, 8))
    check("old object count remains zero after reuse", 0, okKRefCount(runtime, first))
    doKRelease(runtime, observer)
    gcCollect()
    check("class survives arena churn and GC", "Reusable", okKClassName(runtime, klass))
    let cleanupClass = okKClass(runtime, "Cleanup", 0)
    doKCleanup(runtime, cleanupClass, funcptr(churnCleanup))
    doKRegister(runtime, cleanupClass)
    let releasing = okKNew(runtime, cleanupClass)
    doKSet(runtime, releasing, "temporaryClass", klass)
    doKSet(runtime, releasing, "value", 7)
    doKRelease(runtime, releasing)
    check("cleanup can allocate without reclaiming self early", 1, reuseCleanupCount)
}
