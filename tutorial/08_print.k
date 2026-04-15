// Tutorial 08: Print and kp
// Output functions in Krypton

just run {
    // print() adds a newline
    kp("Line one")
    kp("Line two")

    // kp() also prints with newline (shorthand)
    kp("Using kp shorthand")

    // Printing numbers
    kp("The answer: " + 42)

    // Printing expressions
    let x = 10
    let y = 20
    kp("x=" + x + " y=" + y + " sum=" + (x + y))

    // Multiple items via concatenation
    kp("Name: " + "Alice" + ", Age: " + 30)

    // Print in a loop
    let i = 1
    while i <= 5 {
        kp("  Item #" + i)
        i = i + 1
    }
}
