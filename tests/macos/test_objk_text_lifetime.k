import "k:objk_runtime_macos"

func check(name, expected, actual) {
    if expected != actual { kp("[FAIL] " + name); exit("1") }
    kp("[PASS] " + name)
}

just run {
    let runtime = okKRuntime(2048)
    let klass = okKClass(runtime, "TextOwner", 0)
    doKRegister(runtime, klass)
    let object = okKNew(runtime, klass)
    let first = okKText(runtime, "first")
    doKText(runtime, object, "title", first)
    check("text field retains", 2, okKTextRefCount(runtime, first))
    doKReleaseText(runtime, first)
    let before = bufGetQwordAt(runtime, 8)
    doKText(runtime, object, "title", first)
    check("same text assignment balanced", 1, okKTextRefCount(runtime, first))
    check("same text assignment does not allocate", before, bufGetQwordAt(runtime, 8))
    check("owned text readable", "first", okKTextValue(runtime, okKGet(runtime, object, "title")))
    let second = okKText(runtime, "second")
    doKText(runtime, object, "title", second)
    doKReleaseText(runtime, second)
    check("replacement releases old text", 0, okKTextRefCount(runtime, first))
    check("replacement retained", 1, okKTextRefCount(runtime, second))
    doKText(runtime, object, "title", 0)
    check("clear releases text", 0, okKTextRefCount(runtime, second))
    check("cleared text field remains", 1, okKHas(runtime, object, "title"))

    let final = okKText(runtime, "final")
    doKText(runtime, object, "title", final)
    doKReleaseText(runtime, final)
    doKRelease(runtime, object)
    check("owner release releases text", 0, okKTextRefCount(runtime, final))

    let highWater = bufGetQwordAt(runtime, 8)
    let i = 0
    while i < 1000 {
        let owner = okKNew(runtime, klass)
        let value = okKText(runtime, "reused text")
        doKText(runtime, owner, "title", value)
        doKReleaseText(runtime, value)
        doKRelease(runtime, owner)
        i += 1
    }
    check("owned text storage reused", highWater, bufGetQwordAt(runtime, 8))
    gcCollect()
    check("class name survives text churn", "TextOwner", okKClassName(runtime, klass))
}
