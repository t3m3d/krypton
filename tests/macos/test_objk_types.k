import "k:objk_runtime_macos"

func identity(runtime, self, value) { emit value }
func pair(runtime, self, first, second) { emit second }
func stored(runtime, self) { emit okKGet(runtime, self, "value") }

func check(name, expected, actual) {
    if expected != actual { kp("[FAIL] " + name); exit("1") }
    kp("[PASS] " + name)
}

just run {
    let runtime = okKRuntime(4096)
    let item = okKClass(runtime, "Item", 0)
    doKRegister(runtime, item)
    let child = okKClass(runtime, "Child", item)
    doKRegister(runtime, child)
    let service = okKClass(runtime, "Service", 0)
    okKObjectMethod(runtime, service, "identity", 1, funcptr(identity), item, 0, item)
    okKObjectMethod(runtime, service, "pair", 2, funcptr(pair), item, item, item)
    okKObjectMethod(runtime, service, "stored", 0, funcptr(stored), 0, 0, item)
    doKRegister(runtime, service)
    let derived = okKClass(runtime, "Derived", service)
    okKMethod(runtime, derived, "identity", 1, funcptr(identity))
    doKRegister(runtime, derived)
    let object = okKNew(runtime, service)
    let override = okKNew(runtime, derived)
    let value = okKNew(runtime, child)
    doKSet(runtime, object, "value", value)
    check("typed argument accepts subclass", value, okKSend1(runtime, object, "identity", value))
    check("two typed arguments", value, okKSend2(runtime, object, "pair", value, value))
    check("zero-argument typed result", value, okKSend(runtime, object, "stored"))
    check("legacy override inherits object contract", value, okKSend1(runtime, override, "identity", value))
    check("typed dispatch does not retain argument", 1, okKRefCount(runtime, value))
    doKRelease(runtime, value)
    doKRelease(runtime, object)
    doKRelease(runtime, override)
}
