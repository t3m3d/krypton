// Test v0.3.0 features: compound assignment, for-in, new builtins

just run {
    // === Compound Assignment ===
    print("=== Compound Assignment ===")
    let x = "10"
    x += "5"
    print(x)
    x -= "3"
    print(x)
    x *= "4"
    print(x)
    x /= "6"
    print(x)
    x %= "3"
    print(x)

    // += with strings (concatenation)
    let s = "hello"
    s += " world"
    print(s)

    // === For-In Loop ===
    print("=== For-In Loop ===")
    let items = "apple,banana,cherry"
    for fruit in items {
        print(fruit)
    }

    // For-in with numbers
    let nums = "3,1,4,1,5"
    let total = "0"
    for n in nums {
        total += n
    }
    print(total)

    // === New Builtins ===
    print("=== append ===")
    let list = "a,b,c"
    print(append(list, "d"))

    print("=== join ===")
    print(join("hello,world,test", " "))

    print("=== reverse ===")
    print(reverse("1,2,3,4,5"))

    print("=== sort ===")
    print(sort("3,1,4,1,5,9,2,6"))

    print("=== keys/values ===")
    let map = "name,Alice,age,30,city,NYC"
    print(keys(map))
    print(values(map))

    print("=== hasKey ===")
    print(hasKey(map, "name"))
    print(hasKey(map, "email"))

    print("=== remove ===")
    print(remove("a,b,c,b,d", "b"))

    print("=== repeat ===")
    print(repeat("abc", "3"))
    print(repeat("-", "10"))

    print("=== format ===")
    print(format("Hello, {}!", "world"))
    print(format("x = {}", "42"))

    print("=== parseInt ===")
    print(parseInt("  42  "))
    print(parseInt("007"))

    print("=== toStr ===")
    print(toStr("123"))

    print("ALL v0.3.0 TESTS PASSED")
}
