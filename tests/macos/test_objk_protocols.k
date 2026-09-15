import "k:objk_runtime_macos"

func value(runtime, self) { emit okKGet(runtime, self, "value") }
func identity(runtime, self, item) { emit item }
func pair(runtime, self, first, second) { emit second }

func check(name, expected, actual) {
    if expected != actual { kp("[FAIL] " + name); exit("1") }
    kp("[PASS] " + name)
}

just run {
    let mode = ""
    if argCount() > 0 { mode = arg("0") }
    let runtime = okKRuntime(8192)
    let itemClass = okKClass(runtime, "Item", 0)
    doKRegister(runtime, itemClass)
    if mode == "kind" { doKRegisterProtocol(runtime, itemClass) }
    if mode == "empty" { okKProtocol(runtime, "", 0) }
    let readable = okKProtocol(runtime, "Readable", 0)
    if mode == "parent" { okKProtocol(runtime, "Child", readable) }
    if mode == "absent" { doKRequireMethod(runtime, readable, "value", 0, itemClass, 0, 0) }
    doKRequireMethod(runtime, readable, "value", 0, 0, 0, itemClass)
    if mode == "duplicate" { doKRequireMethod(runtime, readable, "value", 0, 0, 0, itemClass) }
    doKRegisterProtocol(runtime, readable)
    if mode == "sealed" { doKRequireMethod(runtime, readable, "extra", 0, 0, 0, 0) }
    let identityProtocol = okKProtocol(runtime, "Identity", readable)
    if mode == "inherited-duplicate" { doKRequireMethod(runtime, identityProtocol, "value", 0, 0, 0, itemClass) }
    doKRequireMethod(runtime, identityProtocol, "identity", 1, itemClass, 0, itemClass)
    doKRegisterProtocol(runtime, identityProtocol)
    let pairProtocol = okKProtocol(runtime, "Pair", 0)
    doKRequireMethod(runtime, pairProtocol, "pair", 2, 0, 0, 0)
    doKRegisterProtocol(runtime, pairProtocol)
    let unrelated = okKProtocol(runtime, "Unrelated", 0)
    let service = okKClass(runtime, "Service", 0)
    if mode == "unregistered" { doKConform(runtime, service, unrelated) }
    doKRegisterProtocol(runtime, unrelated)
    if mode != "missing" {
        if mode == "arity" { okKMethod(runtime, service, "value", 1, funcptr(identity)) }
        else if mode == "signature" { okKMethod(runtime, service, "value", 0, funcptr(value)) }
        else { okKObjectMethod(runtime, service, "value", 0, funcptr(value), 0, 0, itemClass) }
    }
    okKObjectMethod(runtime, service, "identity", 1, funcptr(identity), itemClass, 0, itemClass)
    okKMethod(runtime, service, "pair", 2, funcptr(pair))
    doKConform(runtime, service, identityProtocol)
    doKConform(runtime, service, pairProtocol)
    if mode == "duplicate-conformance" { doKConform(runtime, service, identityProtocol) }
    doKRegister(runtime, service)
    if mode == "sealed-class" { doKConform(runtime, service, unrelated) }
    let derived = okKClass(runtime, "Derived", service)
    okKMethod(runtime, derived, "value", 0, funcptr(value))
    if mode == "override" { okKMethod(runtime, derived, "pair", 1, funcptr(identity)) }
    doKRegister(runtime, derived)
    let object = okKNew(runtime, derived)
    let item = okKNew(runtime, itemClass)
    doKSet(runtime, object, "value", item)
    check("inherits declared protocol", 1, okKConforms(runtime, object, identityProtocol))
    check("inherits protocol parent", 1, okKConforms(runtime, object, readable))
    check("multiple protocols", 1, okKConforms(runtime, object, pairProtocol))
    check("no structural conformance", 0, okKConforms(runtime, object, unrelated))
    check("inherited typed override dispatch", item, okKSend(runtime, object, "value"))
    check("protocol method dispatch", item, okKSend1(runtime, object, "identity", item))
    check("protocol arity two", 42, okKSend2(runtime, object, "pair", 1, 42))
    gcCollect()
    check("protocol metadata survives GC", 1, okKConforms(runtime, object, readable))
    doKRelease(runtime, object)
    doKRelease(runtime, item)
    if mode != "" { kp("[FAIL] expected protocol rejection"); exit("0") }
}
