// Tutorial 06: While Loops
// Krypton's only loop construct: while

just run {
    // Count from 1 to 5
    let i = 1
    while i <= 5 {
        kp("Count: " + i)
        i = i + 1
    }

    // Sum numbers 1 to 100
    let sum = 0
    i = 1
    while i <= 100 {
        sum = sum + i
        i = i + 1
    }
    kp("Sum 1-100: " + sum)

    // Break exits the loop early
    i = 0
    while i < 1000 {
        if i == 10 {
            kp("Breaking at " + i)
            break
        }
        i = i + 1
    }

    // Nested loops: multiplication table
    i = 1
    while i <= 3 {
        let j = 1
        while j <= 3 {
            kp("" + i + " x " + j + " = " + (i * j))
            j = j + 1
        }
        i = i + 1
    }
}
