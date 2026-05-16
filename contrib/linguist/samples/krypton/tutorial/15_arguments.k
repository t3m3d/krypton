// Tutorial 15: Command Line Arguments
// Working with program arguments

just run {
    let argc = argCount()
    kp("Number of arguments: " + argc)

    if argc == 0 {
        kp("No arguments provided.")
        kp("Try running with some arguments!")
    } else {
        // arg(0) through arg(n-1)
        let i = 0
        while i < argc {
            kp("  arg(" + i + ") = " + arg(i))
            i = i + 1
        }

        // Example: use first arg as name
        kp("Hello, " + arg(0) + "!")
    }
}
