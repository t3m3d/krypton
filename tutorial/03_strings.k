// Tutorial 03: String Operations
// Working with strings in Krypton
// Strings are the fundamental data type

just run {
    let s = "Hello, Krypton!"

    // Length
    print("Length: " + len(s))

    // Indexing (zero-based)
    print("First char: " + s[0])
    print("Last char: " + s[len(s) - 1])

    // Substring(string, start, end)
    print("First word: " + substring(s, 0, 5))

    // startsWith
    if startsWith(s, "Hello") {
        print("Starts with Hello: yes")
    }

    // Concatenation with +
    let full = "Part A" + " + " + "Part B"
    print(full)

    // Numbers convert to strings when concatenated
    print("The answer is " + 42)
}
