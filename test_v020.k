// Test v0.2.0 built-in functions

just run {
    // String builtins
    print("=== indexOf ===")
    print(indexOf("hello world", "world"))
    print(indexOf("hello", "xyz"))

    print("=== contains ===")
    print(contains("hello world", "world"))
    print(contains("hello", "xyz"))

    print("=== replace ===")
    print(replace("hello world", "world", "krypton"))

    print("=== charAt ===")
    print(charAt("abcdef", "2"))

    print("=== trim ===")
    print(trim("  hello  "))

    print("=== toLower/toUpper ===")
    print(toLower("Hello World"))
    print(toUpper("Hello World"))

    print("=== endsWith ===")
    print(endsWith("hello.k", ".k"))
    print(endsWith("hello.c", ".k"))

    print("=== startsWith ===")
    print(startsWith("hello.k", "hello"))

    // Math builtins
    print("=== abs ===")
    print(abs("-42"))
    print(abs("7"))

    print("=== min/max ===")
    print(min("3", "7"))
    print(max("3", "7"))

    // Type
    print("=== type ===")
    print(type("42"))
    print(type("hello"))

    // writeFile
    print("=== writeFile ===")
    let ok = writeFile("test_v020_output.txt", "v0.2.0 works!")
    print(ok)
    let content = readFile("test_v020_output.txt")
    print(content)

    print("ALL TESTS PASSED")
}
