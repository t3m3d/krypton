// Tutorial 05: Conditionals
// if, else if, else

just run {
    let age = 25

    // Simple if
    if age >= 18 {
        print("You are an adult")
    }

    // If-else
    if age >= 65 {
        print("Senior citizen")
    } else {
        print("Not yet a senior")
    }

    // If-else if-else chain
    let score = 85
    if score >= 90 {
        print("Grade: A")
    } else if score >= 80 {
        print("Grade: B")
    } else if score >= 70 {
        print("Grade: C")
    } else {
        print("Grade: F")
    }

    // Nested if
    let x = 10
    if x > 0 {
        if x % 2 == 0 {
            print("" + x + " is positive and even")
        } else {
            print("" + x + " is positive and odd")
        }
    }
}
