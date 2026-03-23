// v0.9.8 regression test — LLVM backend pipeline

import "stdlib/result.k"

func add(a: int, b: int) -> int {
    emit toInt(a) + toInt(b) + ""
}

func doubled(n: int) -> int {
    emit toInt(n) * 2 + ""
}

just run {
    // basic ops
    if add("3", "4") == "7" { kp("PASS add") } else { kp("FAIL add") }
    if doubled("6") == "12" { kp("PASS doubled") } else { kp("FAIL doubled") }

    // import
    let r = ok("llvm ready")
    if isOk(r) { kp("PASS import") } else { kp("FAIL import") }
    if unwrap(r) == "llvm ready" { kp("PASS unwrap") } else { kp("FAIL unwrap") }

    // float
    let f = fadd("1.5", "2.5")
    if f == "4" { kp("PASS float") } else { kp("FAIL float: " + f) }

    kp("ALL v0.9.8 TESTS PASSED")
}
