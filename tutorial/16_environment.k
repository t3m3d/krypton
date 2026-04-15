// Tutorial 16: Environment (Scoped Key-Value Store)
// Using envGet/envSet for variable environments

func createScope() {
    emit ""
}

func setVar(env, name, value) {
    emit envSet(env, name, value)
}

func getVar(env, name) {
    emit envGet(env, name)
}

just run {
    // envSet and envGet provide key-value storage
    let env = createScope()

    // Set variables in the environment
    env = setVar(env, "x", "10")
    env = setVar(env, "y", "20")
    env = setVar(env, "name", "Krypton")

    // Get variables back
    kp("x = " + getVar(env, "x"))
    kp("y = " + getVar(env, "y"))
    kp("name = " + getVar(env, "name"))

    // Update a variable
    env = setVar(env, "x", "100")
    kp("x updated = " + getVar(env, "x"))

    // Use in computation
    let a = toInt(getVar(env, "x"))
    let b = toInt(getVar(env, "y"))
    kp("x + y = " + (a + b))
}
