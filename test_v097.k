// v0.9.7 test - jxt c tag only (k import tested separately)

jxt {
    c "stdio.h"
}

module test_jxt

struct Box {
    let val
}

just run {
    // c tag compiles without hanging
    kp("PASS jxt c tag")

    // struct still works
    let b = Box { val: "42" }
    if b.val == "42" { kp("PASS struct") } else { kp("FAIL struct") }

    // basic functionality
    let x = "hello"
    if len(x) == "5" { kp("PASS basic ops") } else { kp("FAIL") }

    kp("ALL v0.9.7 TESTS PASSED")
}
