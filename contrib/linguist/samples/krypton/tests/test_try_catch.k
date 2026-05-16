// Test: try/catch/throw exception handling

func mayThrow(x) {
    if x == "0" {
        throw "zero error"
    }
    emit "ok"
}

just run {
    // Basic throw and catch
    let caught = "no"
    try {
        throw "test error"
    } catch e {
        caught = e
    }
    if caught == "test error" { kp("PASS basic throw") } else { kp("FAIL basic throw") }

    // No throw - catch skipped
    let ran = "no"
    try {
        ran = "yes"
    } catch e {
        ran = "caught"
    }
    if ran == "yes" { kp("PASS no throw") } else { kp("FAIL no throw") }

    // Throw from function
    let result = ""
    try {
        result = mayThrow("0")
    } catch e {
        result = "caught: " + e
    }
    if result == "caught: zero error" { kp("PASS throw from func") } else { kp("FAIL throw from func: " + result) }

    // Successful function call in try
    let r2 = ""
    try {
        r2 = mayThrow("1")
    } catch e {
        r2 = "error"
    }
    if r2 == "ok" { kp("PASS success in try") } else { kp("FAIL success in try") }

    // Nested try/catch
    let outer = ""
    try {
        try {
            throw "inner"
        } catch e {
            throw "rethrown"
        }
    } catch e {
        outer = e
    }
    if outer == "rethrown" { kp("PASS nested+rethrow") } else { kp("FAIL nested+rethrow") }

    // throw as function
    let tf = ""
    try {
        throw("func form")
    } catch e {
        tf = e
    }
    if tf == "func form" { kp("PASS throw func form") } else { kp("FAIL throw func form") }

    kp("try/catch tests done")
}
