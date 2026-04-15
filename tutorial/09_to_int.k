// Tutorial 09: toInt and Number Conversion
// Converting between strings and numbers

just run {
    // Numbers are strings in Krypton
    // Arithmetic operators handle conversion automatically
    let x = 5 + 3    // Works: gives 8
    kp("5 + 3 = " + x)

    // toInt explicitly converts a string to integer
    let numStr = "42"
    let num = toInt(numStr)
    kp("toInt(\"42\") + 1 = " + (num + 1))

    // Converting string digits
    let digits = "123"
    let i = 0
    let sum = 0
    while i < len(digits) {
        let d = toInt(digits[i])
        sum = sum + d
        i = i + 1
    }
    kp("Digit sum of " + digits + " = " + sum)

    // Number to string is just concatenation with ""
    let n = 100
    let s = "" + n
    kp("Length of " + n + " as string: " + len(s))
}
