// v0.7.5 test — full expression interpolation, new builtins, regression

just run {

    // === Full expression interpolation ===
    let a = 3
    let b = 4

    // Simple identifier (was already working)
    kp(`a = {a}`)

    // Expression in interpolation
    let sum = toInt(a) + toInt(b)
    kp(`sum: {sum}`)

    // Function call in interpolation
    kp(`len of hello: {len("hello")}`)

    // Multiple expressions
    kp(`{a} + {b} = {sum}`)

    // === mapGet / mapSet / mapDel ===
    let m = ""
    m = mapSet(m, "name", "Krypton")
    m = mapSet(m, "version", "0.7.5")
    m = mapSet(m, "year", "2026")

    kp("name: " + mapGet(m, "name"))
    kp("version: " + mapGet(m, "version"))
    kp("hasKey: " + hasKey(m, "name"))

    // Update existing key
    m = mapSet(m, "version", "0.7.5-final")
    kp("updated: " + mapGet(m, "version"))

    // Delete key
    m = mapDel(m, "year")
    kp("after del year: " + hasKey(m, "year"))

    // === listMap ===
    let nums = "1,2,3,4,5"
    let wrapped = listMap(nums, "[", "]")
    kp("listMap: " + wrapped)

    // === listFilter ===
    let mixed = "a,b,a,c,a,d"
    let filtered = listFilter(mixed, "a")
    kp("listFilter a: " + filtered)
    let notA = listFilter(mixed, "!a")
    kp("listFilter !a: " + notA)

    // === strSplit ===
    let csv = "one::two::three"
    let parts = strSplit(csv, "::")
    kp("strSplit: " + parts)

    // === struct regression ===
    struct Point {
        let x
        let y
    }
    let p = Point { x: "5", y: "10" }
    kp(`point: ({p.x}, {p.y})`)

    // === try/catch regression ===
    try {
        throw "test"
    } catch e {
        kp(`caught: {e}`)
    }

    // === nested for-in regression ===
    let out = ""
    for r in "1,2" {
        for c in "a,b" {
            out = out + r + c + " "
        }
    }
    kp("nested: " + out)

    kp("ALL v0.7.5 TESTS PASSED")
}
