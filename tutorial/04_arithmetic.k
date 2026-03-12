// Tutorial 04: Arithmetic
// Number operations in Krypton
// All values are strings, but numeric operations work on numeric strings

just run {
    let a = 10
    let b = 3

    print("a = " + a)
    print("b = " + b)

    // Basic operations
    print("a + b = " + (a + b))
    print("a - b = " + (a - b))
    print("a * b = " + (a * b))
    print("a / b = " + (a / b))   // Integer division
    print("a % b = " + (a % b))   // Modulo (remainder)

    // Order of operations
    let result = 2 + 3 * 4
    print("2 + 3 * 4 = " + result)

    let result2 = (2 + 3) * 4
    print("(2 + 3) * 4 = " + result2)
}
