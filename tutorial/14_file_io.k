// Tutorial 14: File I/O
// Reading files in Krypton

just run {
    // readFile reads the entire file as a string
    // arg(0) is the first command-line argument
    if argCount() >= 1 {
        let filename = arg(0)
        let content = readFile(filename)

        // Count lines
        let lc = lineCount(content)
        print("File: " + filename)
        print("Lines: " + lc)
        print("Characters: " + len(content))

        // Print first 5 lines
        let i = 0
        let limit = 5
        if lc < limit { limit = lc }
        print("--- First " + limit + " lines ---")
        while i < limit {
            print(getLine(content, i))
            i = i + 1
        }
    } else {
        print("Usage: provide a filename as argument")
        print("This program reads a file and shows stats")
    }
}
