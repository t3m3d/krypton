import "k:objk_runtime_macos"

func identity(runtime, self, value) { emit value }
func wrongInteger(runtime, self, value) { emit "not an integer" }
func wrongText(runtime, self, value) { emit self }

just run {
    let mode = arg("0")
    let runtime = okKRuntime(4096)
    let required = okKProtocol(runtime, "Required", 0)
    doKRegisterProtocol(runtime, required)
    let item = okKClass(runtime, "Item", 0)
    doKRegister(runtime, item)
    let conforming = okKClass(runtime, "Conforming", 0)
    doKConform(runtime, conforming, required)
    doKRegister(runtime, conforming)
    let service = okKClass(runtime, "Service", 0)
    if mode == "signature" { okKTypedMethod(runtime, service, "bad", 1, funcptr(identity), okKText(runtime, "bad type"), 0, 0) }
    if mode == "integer-result" { okKTypedMethod(runtime, service, "test", 1, funcptr(wrongInteger), okKTypeInteger(), 0, okKTypeInteger()) }
    else if mode == "text-result" { okKTypedMethod(runtime, service, "test", 1, funcptr(wrongText), okKTypeText(), 0, okKTypeText()) }
    else if mode == "text-argument" { okKTypedMethod(runtime, service, "test", 1, funcptr(identity), okKTypeText(), 0, 0) }
    else if mode == "protocol-argument" { okKTypedMethod(runtime, service, "test", 1, funcptr(identity), required, 0, 0) }
    else { okKTypedMethod(runtime, service, "test", 1, funcptr(identity), okKTypeInteger(), 0, 0) }
    doKRegister(runtime, service)
    let object = okKNew(runtime, service)
    if mode == "integer-argument" { okKSend1(runtime, object, "test", "not an integer") }
    if mode == "integer-result" { okKSend1(runtime, object, "test", 1) }
    if mode == "text-argument" { okKSend1(runtime, object, "test", object) }
    if mode == "text-result" { okKSend1(runtime, object, "test", okKText(runtime, "text")) }
    if mode == "protocol-argument" { okKSend1(runtime, object, "test", okKNew(runtime, item)) }
    kp("[FAIL] expected value type rejection")
    exit("0")
}
