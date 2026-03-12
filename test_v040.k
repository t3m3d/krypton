// Test v0.4.0 features

just run {
    // === continue statement ===
    print("=== continue ===")
    let i = "0"
    let odds = ""
    while i < "10" {
        i += "1"
        if i % "2" == "0" {
            continue
        }
        if odds == "" {
            odds = i
        } else {
            odds = odds + "," + i
        }
    }
    print(odds)

    // === do-while loop ===
    print("=== do-while ===")
    let x = "1"
    do {
        x *= "2"
    } while x < "100"
    print(x)

    // === match statement ===
    print("=== match ===")
    let day = "3"
    match day {
        "1" { print("Monday") }
        "2" { print("Tuesday") }
        "3" { print("Wednesday") }
        "4" { print("Thursday") }
        else { print("Other") }
    }

    let color = "red"
    match color {
        "blue" { print("cool") }
        "red" { print("warm") }
        else { print("neutral") }
    }

    // === range ===
    print("=== range ===")
    print(range("0", "5"))
    let sum = "0"
    for n in range("1", "6") {
        sum += n
    }
    print(sum)

    // === math builtins ===
    print("=== pow ===")
    print(pow("2", "10"))
    print(pow("3", "4"))

    print("=== sqrt ===")
    print(sqrt("144"))
    print(sqrt("50"))

    print("=== sign ===")
    print(sign("-42"))
    print(sign("0"))
    print(sign("7"))

    print("=== clamp ===")
    print(clamp("-5", "0", "100"))
    print(clamp("150", "0", "100"))
    print(clamp("50", "0", "100"))

    // === string builtins ===
    print("=== padLeft ===")
    print(padLeft("42", "6", "0"))
    print(padLeft("hi", "8", " "))

    print("=== padRight ===")
    print(padRight("hi", "8", "."))

    print("=== charCode/fromCharCode ===")
    print(charCode("A"))
    print(fromCharCode("65"))
    print(charCode("0"))

    // === list builtins ===
    print("=== slice ===")
    print(slice("a,b,c,d,e", "1", "4"))

    print("=== length ===")
    print(length("a,b,c,d,e"))
    print(length(""))

    print("=== unique ===")
    print(unique("a,b,a,c,b,d"))

    // === printErr ===
    print("=== printErr ===")
    printErr("this goes to stderr")
    print("ok")

    // === assert ===
    print("=== assert ===")
    assert("1", "true should pass")
    assert(len("hello") == "5", "len check")
    print("assertions passed")

    print("ALL v0.4.0 TESTS PASSED")
}
