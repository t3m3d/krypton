// Tutorial 04: Arithmetic
// Number operations in Krypton
// All values are strings, but numeric operations work on numeric strings

just run {
    let a = 10
    let b = 3

    kp("a = " + a)
    kp("b = " + b)

    // Basic operations
    kp("a + b = " + (a + b))
    kp("a - b = " + (a - b))
    kp("a * b = " + (a * b))
    kp("a / b = " + (a / b))   // Integer division
    kp("a % b = " + (a % b))   // Modulo (remainder)

    // Order of operations
    let result = 2 + 3 * 4
    kp("2 + 3 * 4 = " + result)

    let result2 = (2 + 3) * 4
    kp("(2 + 3) * 4 = " + result2)
}
