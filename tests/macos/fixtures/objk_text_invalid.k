import "k:objk_runtime_macos"

just run {
    let mode = arg("0")
    let runtime = okKRuntime(1024)
    let klass = okKClass(runtime, "Owner", 0)
    doKRegister(runtime, klass)
    let object = okKNew(runtime, klass)
    let value = okKText(runtime, "value")
    if mode == "kind" { doKText(runtime, object, "title", object) }
    doKText(runtime, object, "title", value)
    if mode == "overwrite" { doKSet(runtime, object, "title", 0) }
    if mode == "own" { doKOwn(runtime, object, "other", value) }
    doKReleaseText(runtime, value)
    doKRelease(runtime, object)
    if mode == "released" { okKTextValue(runtime, value) }
    if mode == "double-release" { doKReleaseText(runtime, value) }
    if mode == "retain-dead" { okKRetainText(runtime, value) }
    kp("[FAIL] expected text rejection")
    exit("0")
}
