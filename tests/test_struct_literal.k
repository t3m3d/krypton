// Struct literals + dynamic reflection API (macho). Struct-literal detection was
// dead on the macho-built compiler (startsWith==1 deadness), so `T { f: v }` fell
// through and desynced the parser, dropping the rest of the block. Fixed in the
// FE. The dynamic structNew/getField/setField/hasField/structFields builtins now
// ride the same (keyPtr,value) env buffer as the struct ops. Strong [FAIL]
// markers (test_structs only detects crashes).
struct V { x y z }

just run {
    // Struct literal — and code after it must survive.
    let a = V { x: "1", y: "2", z: "3" }
    if a.x != "1" { kp("[FAIL] literal x"); exit("1") }
    if a.y != "2" { kp("[FAIL] literal y"); exit("1") }
    if a.z != "3" { kp("[FAIL] literal z"); exit("1") }
    let marker = "reached"
    if marker != "reached" { kp("[FAIL] code after literal dropped"); exit("1") }

    // Dynamic reflection API over the same env.
    let obj = structNew()
    obj = setField(obj, "a", "hello")
    obj = setField(obj, "b", "world")
    if getField(obj, "a") != "hello" { kp("[FAIL] dynamic get a"); exit("1") }
    if getField(obj, "b") != "world" { kp("[FAIL] dynamic get b"); exit("1") }
    obj = setField(obj, "a", "HELLO")            // update existing key
    if getField(obj, "a") != "HELLO" { kp("[FAIL] dynamic update"); exit("1") }
    if hasField(obj, "b") != "1" { kp("[FAIL] hasField present"); exit("1") }
    if hasField(obj, "z") != "0" { kp("[FAIL] hasField missing"); exit("1") }
    let fields = structFields(obj)
    if !contains(fields, "a") { kp("[FAIL] structFields a"); exit("1") }
    if !contains(fields, "b") { kp("[FAIL] structFields b"); exit("1") }

    kp("[PASS] struct literals + dynamic reflection API")
}
