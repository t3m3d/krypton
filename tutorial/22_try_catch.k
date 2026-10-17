// Tutorial 22: Exception Handling
// try, catch, and throw

func divide(a, b) {
    if b == "0" {
        throw "division by zero"
    }
    emit toInt(a) / toInt(b) + ""
}

func parsePositive(s) {
    let n = toInt(s)
    if n < 0 {
        throw `expected positive number, got {s}`
    }
    emit n + ""
}

just run {
    // Basic try/catch
    try {
        throw "something went wrong"
    } catch e {
        print("caught: " + e)
    }

    // Catching from a function
    try {
        let result = divide("10", "0")
        print("result: " + result)
    } catch e {
        print("error: " + e)
    }

    // Successful try (catch never runs)
    let val = "0"
    try {
        val = divide("10", "2")
    } catch e {
        val = "error"
    }
    print("10 / 2 = " + val)

    // Nested try/catch
    try {
        try {
            throw "inner error"
        } catch e {
            print("inner caught: " + e)
            throw "rethrown: " + e
        }
    } catch e {
        print("outer caught: " + e)
    }

    // throw as function call
    try {
        throw("function-form throw")
    } catch e {
        print("got: " + e)
    }

    print("done")
}
