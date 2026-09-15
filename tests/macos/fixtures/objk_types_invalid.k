import "k:objk_runtime_macos"

func identity(runtime, self, value) {
    if value == self { kp("[FAIL] bad argument reached callback"); exit("0") }
    emit value
}
func wrongResult(runtime, self, value) { emit self }

just run {
    let mode = arg("0")
    let runtime = okKRuntime(4096)
    let item = okKClass(runtime, "Item", 0)
    doKRegister(runtime, item)
    let service = okKClass(runtime, "Service", 0)
    if mode == "absent" { okKObjectMethod(runtime, service, "id", 0, funcptr(identity), item, 0, item) }
    if mode == "class" { okKObjectMethod(runtime, service, "id", 1, funcptr(identity), 8, 0, item) }
    if mode == "result" { okKObjectMethod(runtime, service, "id", 1, funcptr(wrongResult), item, 0, item) }
    else { okKObjectMethod(runtime, service, "id", 1, funcptr(identity), item, 0, item) }
    doKRegister(runtime, service)
    let derived = okKClass(runtime, "Derived", service)
    if mode == "override" { okKObjectMethod(runtime, derived, "id", 1, funcptr(identity), 0, 0, 0) }
    if mode == "override-arity" { okKMethod(runtime, derived, "id", 0, funcptr(identity)) }
    okKMethod(runtime, derived, "id", 1, funcptr(identity))
    doKRegister(runtime, derived)
    let object = okKNew(runtime, derived)
    let value = okKNew(runtime, item)
    if mode == "result" { okKSend1(runtime, okKNew(runtime, service), "id", value) }
    if mode == "argument" { okKSend1(runtime, object, "id", object) }
    if mode == "null" { okKSend1(runtime, object, "id", 0) }
    if mode == "stale" { doKRelease(runtime, value); okKNew(runtime, item) }
    okKSend1(runtime, object, "id", value)
    kp("[FAIL] expected typed rejection")
    exit("0")
}
