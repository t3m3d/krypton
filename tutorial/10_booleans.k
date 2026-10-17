// Tutorial 10: Comparisons and Boolean Logic
// Comparison operators and logical operators

just run {
    let a = 10
    let b = 20

    // Comparison operators: ==, !=, <, >, <=, >=
    if a < b {
        print("" + a + " < " + b)
    }
    if a != b {
        print("" + a + " != " + b)
    }

    // Logical AND (&&): both must be true
    let x = 15
    if x >= 10 && x <= 20 {
        print("" + x + " is between 10 and 20")
    }

    // Logical OR (||): at least one must be true
    let day = "Saturday"
    if day == "Saturday" || day == "Sunday" {
        print("It's the weekend!")
    }

    // Logical NOT (!): inverts truth
    let empty = ""
    if !empty {
        print("The string is empty (falsy)")
    }

    // Boolean values: 0 is false, everything else is truthy
    if 1 { print("1 is truthy") }
    if !0 { print("0 is falsy") }
    if "hello" { print("non-empty string is truthy") }
}
