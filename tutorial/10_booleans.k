// Tutorial 10: Comparisons and Boolean Logic
// Comparison operators and logical operators

just run {
    let a = 10
    let b = 20

    // Comparison operators: ==, !=, <, >, <=, >=
    if a < b {
        kp("" + a + " < " + b)
    }
    if a != b {
        kp("" + a + " != " + b)
    }

    // Logical AND (&&): both must be true
    let x = 15
    if x >= 10 && x <= 20 {
        kp("" + x + " is between 10 and 20")
    }

    // Logical OR (||): at least one must be true
    let day = "Saturday"
    if day == "Saturday" || day == "Sunday" {
        kp("It's the weekend!")
    }

    // Logical NOT (!): inverts truth
    let empty = ""
    if !empty {
        kp("The string is empty (falsy)")
    }

    // Boolean values: 0 is false, everything else is truthy
    if 1 { kp("1 is truthy") }
    if !0 { kp("0 is falsy") }
    if "hello" { kp("non-empty string is truthy") }
}
