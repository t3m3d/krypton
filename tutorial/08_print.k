// Tutorial 08: Print and kp
// Output functions in Krypton

just run {
    // print() adds a newline
    print("Line one")
    print("Line two")

    // kp() also prints with newline (shorthand)
    kp("Using kp shorthand")

    // Printing numbers
    print("The answer: " + 42)

    // Printing expressions
    let x = 10
    let y = 20
    print("x=" + x + " y=" + y + " sum=" + (x + y))

    // Multiple items via concatenation
    print("Name: " + "Alice" + ", Age: " + 30)

    // Print in a loop
    let i = 1
    while i <= 5 {
        print("  Item #" + i)
        i = i + 1
    }
}
