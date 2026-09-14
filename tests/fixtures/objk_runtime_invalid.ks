import "k:objk_runtime_macos"

func value(runtime, self) { emit 1 }
let cleanupMode = ""

func badCleanup(runtime, self) {
    if cleanupMode == "cleanup-retain" { okKRetain(runtime, self) }
    if cleanupMode == "cleanup-release" { doKRelease(runtime, self) }
    if cleanupMode == "cleanup-write" { doKSet(runtime, self, "bad", 1) }
    if cleanupMode == "cleanup-own" {
        doKOwn(runtime, okKGet(runtime, self, "other"), "bad", self)
    }
    emit 0
}

just run {
    let mode = arg("0")
    cleanupMode = mode
    let runtime = okKRuntime(4096)
    let base = okKClass(runtime, "Base", 0)
    if mode == "unregistered" { okKNew(runtime, base) }
    if mode == "parent" { okKClass(runtime, "Child", base) }
    okKMethod(runtime, base, "value", 0, funcptr(value))
    if mode == "duplicate" { okKMethod(runtime, base, "value", 0, funcptr(value)) }
    if mode == "cleanup-null" { doKCleanup(runtime, base, 0) }
    doKCleanup(runtime, base, funcptr(badCleanup))
    if mode == "cleanup-duplicate" { doKCleanup(runtime, base, funcptr(badCleanup)) }
    doKRegister(runtime, base)
    if mode == "sealed" { okKMethod(runtime, base, "late", 0, funcptr(value)) }
    if mode == "cleanup-sealed" { doKCleanup(runtime, base, funcptr(badCleanup)) }
    let object = okKNew(runtime, base)
    let other = okKNew(runtime, base)
    doKSet(runtime, object, "other", other)
    if mode == "own-class" { doKOwn(runtime, object, "bad", base) }
    if mode == "own-invalid" { doKOwn(runtime, object, "bad", 8) }
    if mode == "own-dead" { doKRelease(runtime, other); doKOwn(runtime, object, "bad", other) }
    if mode == "own-overwrite" {
        doKOwn(runtime, object, "child", other)
        doKSet(runtime, object, "child", 0)
    }
    if mode == "weak-class" { doKWeak(runtime, object, "bad", base) }
    if mode == "weak-invalid" { doKWeak(runtime, object, "bad", 8) }
    if mode == "weak-dead" { doKRelease(runtime, other); doKWeak(runtime, object, "bad", other) }
    if mode == "weak-overwrite" {
        doKWeak(runtime, object, "child", other)
        doKSet(runtime, object, "child", 0)
    }
    if mode == "weak-to-owned" {
        doKWeak(runtime, object, "child", other)
        doKOwn(runtime, object, "child", other)
    }
    if mode == "owned-to-weak" {
        doKOwn(runtime, object, "child", other)
        doKWeak(runtime, object, "child", other)
    }
    if mode == "method" { okKSend(runtime, object, "missing") }
    if mode == "arity" { okKSend1(runtime, object, "value", 1) }
    if mode == "field" { okKGet(runtime, object, "missing") }
    if mode == "handle" { okKGet(runtime, 8, "value") }
    if mode == "interior" { okKGet(runtime, object + 8, "value") }
    if mode == "kind" { okKGet(runtime, base, "value") }
    if mode == "pointer" { doKSet(runtime, object, "bad", "heap string") }
    if mode == "capacity" {
        let small = okKRuntime(64)
        okKText(small, "this string is too long to fit inside this arena allocation")
    }
    doKRelease(runtime, object)
    if mode == "released" { okKSend(runtime, object, "value") }
    if mode == "double-release" { doKRelease(runtime, object) }
    if mode == "retain-dead" { okKRetain(runtime, object) }
    kp("[FAIL] expected rejection: " + mode)
    exit("0")
}
