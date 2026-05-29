// Tutorial 29: Lambdas & Higher-Order Functions
// Functions are values: you can pass one function into another.
//
// A lambda is an unnamed function: func(x) { emit toInt(x) * 2 }
// A parameter that receives a function is annotated ': closure' so
// Krypton knows to call it. Lambdas use their own parameters — they
// don't capture outer variables.

import "k:fp"

// applyTwice takes a number and a function, and applies it twice.
func applyTwice(x, f: closure) {
    emit f(f(x))
}

just run {
    // Pass a lambda where a ': closure' parameter is expected.
    kp("applyTwice(5, *2) = " + applyTwice(5, func(x) { emit toInt(x) * 2 }))
    kp("applyTwice(3, +1) = " + applyTwice(3, func(x) { emit toInt(x) + 1 }))

    // fp helpers run a lambda over every element of a comma-list.
    let xs = "1,2,3,4,5"
    kp("doubled: " + fpMap(xs,    func(x) { emit toInt(x) * 2 }))
    kp("evens:   " + fpFilter(xs, func(x) { emit toInt(x) % 2 == 0 }))
    kp("sum:     " + fpReduce(xs, "0", func(acc, x) { emit toInt(acc) + toInt(x) }))
}
