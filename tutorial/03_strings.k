// Tutorial 03: String Operations
// Working with strings in Krypton
// Strings are the fundamental data type

just run {
    let s = "Hello, Krypton!"

    // Length
    kp("Length: " + len(s))

    // Indexing (zero-based)
    kp("First char: " + s[0])
    kp("Last char: " + s[len(s) - 1])

    // Substring(string, start, end)
    kp("First word: " + substring(s, 0, 5))

    // startsWith
    if startsWith(s, "Hello") {
        kp("Starts with Hello: yes")
    }

    // Concatenation with +
    let full = "Part A" + " + " + "Part B"
    kp(full)

    // Numbers convert to strings when concatenated
    kp("The answer is " + 42)
}
