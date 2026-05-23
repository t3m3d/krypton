// Test for readLine builtin (inline-emitted on Windows x64).
// Reads a single line from stdin, echoes with greeting.
just run {
    let name = readLine("What's your name? ")
    kp("Hello, " + name + "!")
}
