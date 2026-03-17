// v0.7.7 test — run.k parity, list literals, extended interpreter

just run {

    // === List literals ===
    let nums = [1, 2, 3, 4, 5]
    kp("list: " + nums)
    kp("first: " + split(nums, 0))
    kp("length: " + length(nums))

    let empty = []
    kp("empty: '" + empty + "'")

    let mixed = ["hello", "world", "krypton"]
    kp("mixed: " + mixed)

    // === Full expression interpolation ===
    let a = "3"
    let b = "4"
    kp(`a + b = {toInt(a) + toInt(b)}`)
    kp(`len of mixed = {length(mixed)}`)
    kp(`first item = {split(mixed, 0)}`)

    // === Struct with dot access ===
    struct Vec {
        let x
        let y
    }
    let v = Vec { x: "10", y: "20" }
    kp(`vec: ({v.x}, {v.y})`)
    v.x = "99"
    kp(`updated: {v.x}`)

    // === for-in regression ===
    let total = 0
    for n in range(1, 6) {
        total += toInt(n)
    }
    kp("sum 1-5: " + total)

    // === match regression ===
    match "blue" {
        "red"  { kp("warm") }
        "blue" { kp("cool") }
        else   { kp("other") }
    }

    // === try/catch regression ===
    try {
        throw "test error"
    } catch e {
        kp("caught: " + e)
    }

    // === mapGet/mapSet ===
    let m = mapSet("", "lang", "Krypton")
    m = mapSet(m, "ver", "0.7.7")
    kp(`lang: {mapGet(m, "lang")}`)
    kp(`ver: {mapGet(m, "ver")}`)

    // === result.k pattern (manual, without import) ===
    func safeDiv(a, b) {
        if b == "0" { emit "err:division by zero" }
        emit "ok:" + (toInt(a) / toInt(b) + "")
    }
    let r1 = safeDiv("10", "2")
    let r2 = safeDiv("10", "0")
    kp("ok result: " + startsWith(r1, "ok:"))
    kp("err result: " + startsWith(r2, "err:"))

    kp("ALL v0.7.7 TESTS PASSED")
}
