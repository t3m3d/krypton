// v0.7.2 test — isKW fix, string interpolation, full regression

just run {

    // === isKW fix: struct keywords now tokenize correctly ===
    struct Color {
        let r
        let g
        let b
    }

    let red = Color { r: "255", g: "0", b: "0" }
    kp("struct r: " + red.r)
    kp("struct g: " + red.g)

    red.r = "200"
    kp("updated r: " + red.r)

    // === isKW fix: try/catch/throw now tokenize correctly ===
    let caught = "no"
    try {
        throw "test"
    } catch e {
        caught = e
    }
    kp("try/catch: " + caught)

    // === String interpolation ===
    let name = "Krypton"
    let ver = "0.7.2"
    kp(`Hello from {name} {ver}!`)

    let x = "10"
    let y = "20"
    kp(`coords: ({x}, {y})`)

    // Interpolation in function
    func describe(item, count) {
        emit `{count} {item}s`
    }
    kp(describe("apple", "3"))

    // === Nested for-in (regression) ===
    let matrix = ""
    for r in "1,2,3" {
        for c in "a,b" {
            matrix = matrix + r + c + " "
        }
    }
    kp("matrix: " + matrix)

    // === All v0.7.1 struct features still work ===
    let obj = structNew()
    setField(obj, "lang", "Krypton")
    kp("dynamic: " + getField(obj, "lang"))
    kp("hasField: " + hasField(obj, "lang"))
    kp("hasField missing: " + hasField(obj, "nope"))

    // === v0.7.0 try/catch nesting ===
    let outer = ""
    try {
        try { throw "inner" }
        catch e { throw "outer: " + e }
    } catch e {
        outer = e
    }
    kp("nested: " + outer)

    kp("ALL v0.7.2 TESTS PASSED")
}
