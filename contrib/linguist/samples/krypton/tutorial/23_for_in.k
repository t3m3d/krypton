// Tutorial 23: For-In Loops
// Iterating over comma-separated lists

just run {
    // Basic for-in
    let fruits = "apple,banana,cherry,date"
    for fruit in fruits {
        kp(fruit)
    }

    // For-in with index tracking
    let nums = "10,20,30,40,50"
    let i = 0
    for n in nums {
        kp(i + ": " + n)
        i += 1
    }

    // Nested for-in
    let rows = "1,2,3"
    let cols = "a,b,c"
    for row in rows {
        for col in cols {
            kp(row + col + " ")
        }
    }

    // Building a result with for-in
    let words2 = "hello,world,krypton"
    let upper = ""
    for w in words2 {
        if len(upper) > 0 {
            upper = upper + ","
        }
        upper = upper + toUpper(w)
    }
    kp(upper)

    // For-in with range
    let total = 0
    for n in range(1, 11) {
        total += toInt(n)
    }
    kp("sum 1-10: " + total)
}
