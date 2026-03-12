// v0.5.0 test — ternary, const, and 15 new builtins

just run {
    // === Ternary operator ===
    let x = 10
    let result = x > 5 ? "big" : "small"
    print("ternary1: " + result)

    let y = 3
    let result2 = y > 5 ? "big" : "small"
    print("ternary2: " + result2)

    // nested ternary
    let z = 0
    let t3 = z > 0 ? "positive" : z == 0 ? "zero" : "negative"
    print("ternary3: " + t3)

    // === const declaration ===
    const pi = "314"
    const greeting = "hello"
    print("const1: " + pi)
    print("const2: " + greeting)

    // === splitBy ===
    let csv = "one::two::three"
    let parts = splitBy(csv, "::")
    print("splitBy: " + parts)

    // === listIndexOf ===
    let lst = "apple,banana,cherry,date"
    print("listIndexOf1: " + listIndexOf(lst, "cherry"))
    print("listIndexOf2: " + listIndexOf(lst, "grape"))

    // === insertAt ===
    let lst2 = "a,b,d,e"
    print("insertAt: " + insertAt(lst2, 2, "c"))

    // === removeAt ===
    let lst3 = "x,y,z,w"
    print("removeAt: " + removeAt(lst3, 1))

    // === replaceAt ===
    let lst4 = "1,2,3,4"
    print("replaceAt: " + replaceAt(lst4, 2, "99"))

    // === fill ===
    print("fill: " + fill(4, "hi"))

    // === zip ===
    let a = "1,2,3"
    let b = "a,b,c"
    print("zip: " + zip(a, b))

    // === every ===
    let allSame = "5,5,5,5"
    let mixed = "5,5,3,5"
    print("every1: " + every(allSame, "5"))
    print("every2: " + every(mixed, "5"))

    // === some ===
    let nones = "1,2,3"
    print("some1: " + some(nones, "2"))
    print("some2: " + some(nones, "9"))

    // === countOf ===
    let data = "a,b,a,c,a,b"
    print("countOf1: " + countOf(data, "a"))
    print("countOf2: " + countOf(data, "b"))

    // === sumList ===
    let nums = "10,20,30,40"
    print("sumList: " + sumList(nums))

    // === maxList / minList ===
    let nums2 = "5,1,9,3,7"
    print("maxList: " + maxList(nums2))
    print("minList: " + minList(nums2))

    // === hex ===
    print("hex1: " + hex(255))
    print("hex2: " + hex(16))

    // === bin ===
    print("bin1: " + bin(10))
    print("bin2: " + bin(255))

    print("ALL v0.5.0 TESTS PASSED")
}
