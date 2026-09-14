import "k:objk_runtime_macos"

func check(name, expected, actual) {
    if expected != actual {
        kp("[FAIL] " + name + " expected=" + expected + " actual=" + actual)
        exit("1")
    }
    kp("[PASS] " + name)
}

func counterValue(runtime, self) { emit okKGet(runtime, self, "value") }
func counterAdd(runtime, self, delta) {
    emit doKSet(runtime, self, "value", okKGet(runtime, self, "value") + delta)
}
func counterPair(runtime, self, a, b) { emit a * 10 + b }
func counterDescribe(runtime, self) { emit "Counter=" + okKGet(runtime, self, "value") }
func childValue(runtime, self) {
    emit okKSuper(runtime, self, okKGet(runtime, self, "definingClass"), "value") * 2
}

just run {
    let runtime = okKRuntime(65536)
    let base = okKClass(runtime, "Counter", 0)
    okKMethod(runtime, base, "value", 0, funcptr(counterValue))
    okKMethod(runtime, base, "add", 1, funcptr(counterAdd))
    okKMethod(runtime, base, "pair", 2, funcptr(counterPair))
    okKMethod(runtime, base, "describe", 0, funcptr(counterDescribe))
    doKRegister(runtime, base)

    let child = okKClass(runtime, "DoubleCounter", base)
    okKMethod(runtime, child, "value", 0, funcptr(childValue))
    doKRegister(runtime, child)

    let object = okKNew(runtime, base)
    let other = okKNew(runtime, base)
    let derived = okKNew(runtime, child)
    doKSet(runtime, object, "value", 7)
    doKSet(runtime, other, "value", 99)
    doKSet(runtime, derived, "value", 10)
    doKSet(runtime, derived, "definingClass", child)

    check("class name", "Counter", okKClassName(runtime, base))
    check("object class", base, okKObjectClass(runtime, object))
    check("base identity", 1, okKIsA(runtime, object, base))
    check("inherited identity", 1, okKIsA(runtime, derived, base))
    check("child identity", 1, okKIsA(runtime, derived, child))
    check("unrelated identity", 0, okKIsA(runtime, object, child))
    check("zero-arg dispatch", 7, okKSend(runtime, object, "value"))
    check("one-arg dispatch", 12, okKSend1(runtime, object, "add", 5))
    check("two-arg order", 23, okKSend2(runtime, object, "pair", 2, 3))
    check("inherited method", 13, okKSend1(runtime, derived, "add", 3))
    check("override and super", 26, okKSend(runtime, derived, "value"))
    check("string return", "Counter=12", okKSend(runtime, object, "describe"))
    check("independent fields", 99, okKSend(runtime, other, "value"))
    check("responds inherited", 1, okKResponds(runtime, derived, "add"))
    check("responds absent", 0, okKResponds(runtime, object, "missing"))
    check("has absent field", 0, okKHas(runtime, object, "missing"))
    check("has field", 1, okKHas(runtime, object, "value"))

    let text = okKText(runtime, "owned in K")
    doKSet(runtime, object, "text", text)
    check("owned text", "owned in K", okKTextValue(runtime, okKGet(runtime, object, "text")))
    check("text comparison", 1, okKTextEquals(runtime, text, "owned in K"))
    check("text mismatch", 0, okKTextEquals(runtime, text, "owned in X"))

    let before = bufGetQwordAt(runtime, 8)
    doKSet(runtime, object, "value", 14)
    check("field update does not allocate", before, bufGetQwordAt(runtime, 8))
    check("new refcount", 1, okKRefCount(runtime, object))
    okKRetain(runtime, object)
    check("retained refcount", 2, okKRefCount(runtime, object))
    check("release retained", 1, doKRelease(runtime, object))
    check("still alive", 14, okKSend(runtime, object, "value"))
    check("final release", 0, doKRelease(runtime, object))
    check("dead refcount", 0, okKRefCount(runtime, object))
    check("other survives release", 99, okKSend(runtime, other, "value"))

    let secondRuntime = okKRuntime(4096)
    let secondBase = okKClass(secondRuntime, "Other", 0)
    doKRegister(secondRuntime, secondBase)
    check("runtime isolation", "Other", okKClassName(secondRuntime, secondBase))
    check("first runtime unchanged", "Counter", okKClassName(runtime, base))

    // No interior heap pointers in records. Collection must preserve the arena,
    // then names, methods, and fields remain readable through offset handles.
    gcCollect()
    check("arena after GC", 26, okKSend(runtime, derived, "value"))
    check("owned text after GC", "owned in K", okKTextValue(runtime, text))
}
