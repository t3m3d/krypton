// Tutorial 15: Command Line Arguments
// Working with program arguments

just run {
    let argc = argCount()
    print("Number of arguments: " + argc)

    if argc == 0 {
        print("No arguments provided.")
        print("Try running with some arguments!")
    } else {
        // arg(0) through arg(n-1)
        let i = 0
        while i < argc {
            print("  arg(" + i + ") = " + arg(i))
            i = i + 1
        }

        // Example: use first arg as name
        print("Hello, " + arg(0) + "!")
    }
}
