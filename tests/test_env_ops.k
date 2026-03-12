// Test environment operations (envGet, envSet)

func check(name, expected, actual) {
    if expected == actual {
        kp("[PASS] " + name)
    } else {
        kp("[FAIL] " + name + " expected=" + expected + " actual=" + actual)
    }
}

just run {
    kp("Environment Operation Tests")
    kp("===========================")

    // Create and use environment
    let env = ""
    env = envSet(env, "x", "10")
    check("set and get x", "10", envGet(env, "x"))

    // Set multiple values
    env = envSet(env, "y", "20")
    env = envSet(env, "z", "30")
    check("get x after multi", "10", envGet(env, "x"))
    check("get y", "20", envGet(env, "y"))
    check("get z", "30", envGet(env, "z"))

    // Update existing
    env = envSet(env, "x", "100")
    check("updated x", "100", envGet(env, "x"))

    // Get non-existent (should return empty)
    let val = envGet(env, "nonexistent")
    check("nonexistent", "0", "" + len(val))

    emit "ok"
}
