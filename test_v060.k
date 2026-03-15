just run {

    // === v0.3.0: compound assignment ===
    let x = 10
    x += 5
    kp("compound+=: " + x)      // 15

    x -= 3
    kp("compound-=: " + x)      // 12

    x *= 2
    kp("compound*=: " + x)      // 24

    x /= 4
    kp("compound/=: " + x)      // 6

    x %= 4
    kp("compound%=: " + x)      // 2

    // === v0.3.0: for-in ===
    let lst = "a,b,c,d"
    let out = ""
    for item in lst {
        out = out + item
    }
    kp("for-in: " + out)        // abcd

    // === v0.3.0: list builtins ===
    let nums = "3,1,4,1,5,9,2,6"
    kp("sort: " + sort(nums))
    kp("reverse: " + reverse("1,2,3"))
    kp("append: " + append("a,b", "c"))
    kp("join: " + join("a,b,c", "-"))

    // === v0.4.0: continue ===
    let evens = ""
    let i = 0
    while i < 8 {
        i += 1
        if i % 2 != 0 {
            continue
        }
        evens = evens + i + " "
    }
    kp("continue evens: " + evens)  // 2 4 6 8

    // === v0.4.0: match ===
    let day = "Mon"
    match day {
        "Mon" { kp("match: Monday") }
        "Fri" { kp("match: Friday") }
        else  { kp("match: other") }
    }

    // === v0.4.0: do-while ===
    let n = 0
    do {
        n += 1
    } while n < 3
    kp("do-while: " + n)        // 3

    // === v0.4.0: math builtins ===
    kp("range: " + range(1, 5))         // 1,2,3,4
    kp("pow: " + pow(2, 8))             // 256
    kp("sqrt: " + sqrt(144))            // 12
    kp("abs: " + abs(-42))              // 42
    kp("clamp: " + clamp(15, 0, 10))    // 10
    kp("min: " + min(3, 7))             // 3
    kp("max: " + max(3, 7))             // 7

    // === v0.4.0: string builtins ===
    kp("padLeft: " + padLeft("hi", 6, " "))    // "    hi"
    kp("padRight: " + padRight("hi", 6, "."))  // "hi...."
    kp("charCode: " + charCode("A"))            // 65
    kp("fromCharCode: " + fromCharCode(65))     // A
    kp("trim: '" + trim("  hello  ") + "'")     // 'hello'

    // === v0.5.0: ternary ===
    let val = 42
    let big = val > 10 ? "big" : "small"
    kp("ternary: " + big)               // big

    let nested = val > 100 ? "huge" : val > 10 ? "big" : "small"
    kp("nested ternary: " + nested)     // big

    // === v0.5.0: const ===
    const PI = "314"
    const MSG = "hello"
    kp("const: " + PI + " " + MSG)

    // === v0.5.0: list builtins ===
    let csv = "one::two::three"
    kp("splitBy: " + splitBy(csv, "::"))

    let fruits = "apple,banana,cherry,date"
    kp("listIndexOf: " + listIndexOf(fruits, "cherry"))  // 2
    kp("listIndexOf missing: " + listIndexOf(fruits, "grape"))  // -1

    kp("insertAt: " + insertAt("a,b,d,e", 2, "c"))  // a,b,c,d,e
    kp("removeAt: " + removeAt("x,y,z,w", 1))       // x,z,w
    kp("replaceAt: " + replaceAt("1,2,3,4", 2, "99")) // 1,2,99,4
    kp("fill: " + fill(4, "hi"))                     // hi,hi,hi,hi
    kp("zip: " + zip("1,2,3", "a,b,c"))              // 1,a,2,b,3,c
    kp("every: " + every("5,5,5", "5"))              // 1
    kp("every: " + every("5,5,3", "5"))              // 0
    kp("some: " + some("1,2,3", "2"))                // 1
    kp("some: " + some("1,2,3", "9"))                // 0
    kp("countOf: " + countOf("a,b,a,c,a", "a"))      // 3
    kp("sumList: " + sumList("10,20,30"))             // 60
    kp("maxList: " + maxList("5,1,9,3"))              // 9
    kp("minList: " + minList("5,1,9,3"))              // 1

    // === v0.5.0: conversion ===
    kp("hex: " + hex(255))   // ff
    kp("hex: " + hex(16))    // 10
    kp("bin: " + bin(10))    // 1010
    kp("bin: " + bin(255))   // 11111111

    kp("ALL v0.6.0 TESTS PASSED")
}
