// Tutorial 07: Functions
// Defining and calling functions with func/fn

// Functions use 'emit' to return values
func add(a, b) {
    emit a + b
}

// fn is shorthand for func
fn multiply(a, b) {
    emit a * b
}

// Functions with no return just do side effects
func greet(name) {
    kp("Hello, " + name + "!")
}

// Functions can call other functions
func square(n) {
    emit multiply(n, n)
}

// Functions can have multiple return points
func absolute(n) {
    if n < 0 {
        emit 0 - n
    }
    emit n
}

// Recursive functions
func factorial(n) {
    if n <= 1 {
        emit 1
    }
    emit n * factorial(n - 1)
}

just run {
    kp("3 + 4 = " + add(3, 4))
    kp("3 * 4 = " + multiply(3, 4))
    kp("5^2 = " + square(5))
    kp("|-7| = " + absolute(0 - 7))
    kp("5! = " + factorial(5))
    greet("World")
}
