import "k:objk_runtime_macos"

func identity(runtime, self, value) { emit value }
func pair(runtime, self, first, second) { emit second }
func stored(runtime, self) { emit okKGet(runtime, self, "value") }
func integerAdd(runtime, self, value) { emit value + 1 }
func textIdentity(runtime, self, value) { emit value }
func protocolIdentity(runtime, self, value) { emit value }
func score(runtime, self) { emit 1 }

func check(name, expected, actual) {
    if expected != actual { kp("[FAIL] " + name); exit("1") }
    kp("[PASS] " + name)
}

just run {
    let runtime = okKRuntime(4096)
    let scoreable = okKProtocol(runtime, "TypedScoreable", 0)
    doKRequireMethod(runtime, scoreable, "score", 0, 0, 0, okKTypeInteger())
    doKRegisterProtocol(runtime, scoreable)
    let item = okKClass(runtime, "Item", 0)
    okKTypedMethod(runtime, item, "score", 0, funcptr(score), 0, 0, okKTypeInteger())
    doKConform(runtime, item, scoreable)
    doKRegister(runtime, item)
    let child = okKClass(runtime, "Child", item)
    doKRegister(runtime, child)
    let service = okKClass(runtime, "Service", 0)
    okKObjectMethod(runtime, service, "identity", 1, funcptr(identity), item, 0, item)
    okKObjectMethod(runtime, service, "pair", 2, funcptr(pair), item, item, item)
    okKObjectMethod(runtime, service, "stored", 0, funcptr(stored), 0, 0, item)
    okKTypedMethod(runtime, service, "integerAdd", 1, funcptr(integerAdd), okKTypeInteger(), 0, okKTypeInteger())
    okKTypedMethod(runtime, service, "textIdentity", 1, funcptr(textIdentity), okKTypeText(), 0, okKTypeText())
    okKTypedMethod(runtime, service, "protocolIdentity", 1, funcptr(protocolIdentity), scoreable, 0, scoreable)
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
    check("integer argument and result", 42, okKSend1(runtime, object, "integerAdd", 41))
    let textValue = okKText(runtime, "typed text")
    check("text argument and result", textValue, okKSend1(runtime, object, "textIdentity", textValue))
    check("protocol argument and result", value, okKSend1(runtime, object, "protocolIdentity", value))
    check("typed dispatch does not retain text", 1, okKTextRefCount(runtime, textValue))
    doKReleaseText(runtime, textValue)
    doKRelease(runtime, value)
    doKRelease(runtime, object)
    doKRelease(runtime, override)
}
