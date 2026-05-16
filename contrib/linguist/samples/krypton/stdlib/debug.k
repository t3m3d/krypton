// Debugging utilities for Krypton
// Helpers for inspecting program state

module debug


// Print a value with label
func inspect(label, val) {
    kp("[INSPECT] " + label + " = " + val)
}

// Print the type and length info of a value
func inspectDetail(label, val) {
    kp("[INSPECT] " + label)
    kp("  value:  " + val)
    kp("  length: " + len(val))
}

// Print a hexdump-style view of first n chars
func hexView(s, n) {
    let limit = n
    if limit > len(s) {
        limit = len(s)
    }
    kp("HexView (first " + limit + " chars):")
    let i = 0
    while i < limit {
        let ch = s[i]
        kp("  [" + i + "] '" + ch + "'")
        i += 1
    }
}

// Print a separator line for debug output
func debugSep(label) {
    kp("=== DEBUG: " + label + " ===")
}

// Trace function entry
func traceEnter(funcName) {
    kp(">> ENTER " + funcName)
}

// Trace function exit
func traceExit(funcName, result) {
    kp("<< EXIT  " + funcName + " => " + result)
}

// Assert with abort message
func assertOrDie(condition, msg) {
    if condition == 0 {
        kp("ASSERTION FAILED: " + msg)
        emit "ABORT"
    }
}

// Print a list with indices
func dumpList(label, list) {
    kp("[DUMP] " + label + ":")
    let size = count(list)
    let i = 0
    while i < size {
        kp("  [" + i + "] = " + split(list, i))
        i += 1
    }
    kp("  (size: " + size + ")")
}

// Print lines with line numbers
func dumpLines(label, text) {
    kp("[DUMP] " + label + ":")
    let lines = lineCount(text)
    let i = 0
    while i < lines {
        let num = i + 1
        kp("  " + num + ": " + getLine(text, i))
        i += 1
    }
    kp("  (lines: " + lines + ")")
}

// Log a timestamped message (using a counter)
func log(counter, msg) {
    kp("[LOG " + counter + "] " + msg)
    emit counter + 1
}
