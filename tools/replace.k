// replace - Find and replace text in a file.
// Uses the native builtins `contains(haystack, needle)` and
// `replace(s, old, new)` directly — the previous user-defined helpers
// shadowed them on the C path and were dead code on native (the IR
// dispatcher routes those names to BUILTIN regardless).

just run {
    if argCount() < 3 {
        kp("Usage: replace <find> <replace> <file>")
    } else {
        let find = arg(0)
        let repl = arg(1)
        let content = readFile(arg(2))
        let lc = lineCount(content)
        let changes = 0
        let i = 0
        while i < lc {
            let line = getLine(content, i)
            if contains(line, find) {
                kp(replace(line, find, repl))
                changes = changes + 1
            } else {
                kp(line)
            }
            i = i + 1
        }
        kp("(" + changes + " lines changed)")
    }
}
