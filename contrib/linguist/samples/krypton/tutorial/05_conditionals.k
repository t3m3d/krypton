// Tutorial 05: Conditionals
// if, else if, else

just run {
    let age = 25

    // Simple if
    if age >= 18 {
        kp("You are an adult")
    }

    // If-else
    if age >= 65 {
        kp("Senior citizen")
    } else {
        kp("Not yet a senior")
    }

    // If-else if-else chain
    let score = 85
    if score >= 90 {
        kp("Grade: A")
    } else if score >= 80 {
        kp("Grade: B")
    } else if score >= 70 {
        kp("Grade: C")
    } else {
        kp("Grade: F")
    }

    // Nested if
    let x = 10
    if x > 0 {
        if x % 2 == 0 {
            kp("" + x + " is positive and even")
        } else {
            kp("" + x + " is positive and odd")
        }
    }
}
