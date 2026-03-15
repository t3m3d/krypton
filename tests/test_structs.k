// Test: Struct declaration, instantiation, field access, field assignment

struct Vec {
    let x
    let y
    let z
}

struct Box {
    let label
    let value
}

just run {
    // Constructor
    let v = Vec()
    v.x = "1"
    v.y = "2"
    v.z = "3"
    if v.x == "1" { kp("PASS constructor+assign") } else { kp("FAIL constructor+assign") }
    if v.z == "3" { kp("PASS multi-field") } else { kp("FAIL multi-field") }

    // Struct literal
    let v2 = Vec { x: "10", y: "20", z: "30" }
    if v2.x == "10" { kp("PASS literal x") } else { kp("FAIL literal x") }
    if v2.y == "20" { kp("PASS literal y") } else { kp("FAIL literal y") }
    if v2.z == "30" { kp("PASS literal z") } else { kp("FAIL literal z") }

    // Field update
    v2.x = "99"
    if v2.x == "99" { kp("PASS field update") } else { kp("FAIL field update") }

    // Struct in function
    func boxVal(b) { emit b.value }
    let b = Box { label: "score", value: "42" }
    if boxVal(b) == "42" { kp("PASS struct in func") } else { kp("FAIL struct in func") }

    // Dynamic struct
    let obj = structNew()
    setField(obj, "a", "hello")
    setField(obj, "b", "world")
    if getField(obj, "a") == "hello" { kp("PASS dynamic get") } else { kp("FAIL dynamic get") }
    if hasField(obj, "b") == "1" { kp("PASS hasField") } else { kp("FAIL hasField") }
    if hasField(obj, "z") == "0" { kp("PASS hasField missing") } else { kp("FAIL hasField missing") }
    let fields = structFields(obj)
    if contains(fields, "a") { kp("PASS structFields") } else { kp("FAIL structFields") }

    kp("struct tests done")
}
