// 2.0-alpha-2 stage 2: shadow-stack runtime API.
// Diagnostic API. Compiler doesn't yet emit at STORE points (stage 3).

just run {
    print("count at start = " + gcShadowCount() + " (expect 0)")

    gcShadowPush("ptr-A")
    gcShadowPush("ptr-B")
    gcShadowPush("ptr-C")
    print("after 3 pushes = " + gcShadowCount() + " (expect 3)")

    gcShadowPop(2)
    print("after pop 2    = " + gcShadowCount() + " (expect 1)")

    gcShadowPop(1)
    print("after pop 1    = " + gcShadowCount() + " (expect 0)")

    let i = 0
    while i < 1000 {
        gcShadowPush("burst")
        i = i + 1
    }
    print("after 1000 pushes = " + gcShadowCount() + " (expect 1000)")

    gcShadowPop(1000)
    print("after pop 1000    = " + gcShadowCount() + " (expect 0)")
}
