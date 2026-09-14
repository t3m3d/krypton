// stdlib/process_win_argv.k -- binary argv collection and Windows quoting.

module process_win_argv

import "k:bytes"
// argv payload: [count:u32][len:u32][UTF-8 bytes]...
func processArgsNew() {
    let args = bytesWithLength(4)
    bytesWriteU32LE(args, 0, 0)
    emit args
}

func processArgsCount(args) {
    if bytesLen(args) < 4 { emit 0 }
    emit toInt(bytesReadU32LE(args, 0))
}

func processArgsAdd(args, value) {
    let out = args
    if bytesLen(out) < 4 {
        out = bytesWithLength(4)
        bytesWriteU32LE(out, 0, 0)
    }
    let encoded = bytesFromUtf8(value)
    let at = bytesLen(out)
    out = bytesReserve(out, at + 4 + bytesLen(encoded))
    bytesWriteU32LE(out, at, bytesLen(encoded))
    bytesCopy(out, at + 4, encoded, 0, bytesLen(encoded))
    bytesWriteU32LE(out, 0, processArgsCount(out) + 1)
    emit out
}

func processArgAt(args, index) {
    let wanted = toInt(index)
    if wanted < 0 || wanted >= processArgsCount(args) { emit "" }
    let at = 4
    let i = 0
    while i < processArgsCount(args) {
        if at + 4 > bytesLen(args) { emit "" }
        let n = toInt(bytesReadU32LE(args, at))
        at += 4
        if n < 0 || at + n > bytesLen(args) { emit "" }
        if i == wanted { emit bytesToUtf8(bytesSlice(args, at, at + n)) }
        at += n
        i += 1
    }
    emit ""
}

func _processAppendByteRepeated(sb, value, count) {
    let i = 0
    while i < count {
        sb = sbAppend(sb, fromCharCode(value))
        i += 1
    }
    emit sb
}

// Microsoft C-runtime argv quoting. Preserves spaces, quotes, Unicode UTF-8
// bytes, and trailing backslashes before the closing quote.
func processQuoteArg(value) {
    let quote = len(value) == 0
    let i = 0
    while i < len(value) {
        let c = toInt(charCode(substring(value, i, i + 1)))
        if c == 32 || c == 9 || c == 34 { quote = 1 }
        i += 1
    }
    if quote == 0 { emit value }

    let out = sbAppend(sbNew(), "\"")
    i = 0
    while i < len(value) {
        let slashes = 0
        while i < len(value) && toInt(charCode(substring(value, i, i + 1))) == 92 {
            slashes += 1
            i += 1
        }
        if i >= len(value) {
            out = _processAppendByteRepeated(out, 92, slashes * 2)
            break
        }
        let c = toInt(charCode(substring(value, i, i + 1)))
        if c == 34 {
            out = _processAppendByteRepeated(out, 92, slashes * 2 + 1)
            out = sbAppend(out, "\"")
        } else {
            out = _processAppendByteRepeated(out, 92, slashes)
            out = sbAppend(out, substring(value, i, i + 1))
        }
        i += 1
    }
    out = sbAppend(out, "\"")
    emit sbToString(out)
}

func processCommandLine(executable, args) {
    let out = sbAppend(sbNew(), processQuoteArg(executable))
    let i = 0
    while i < processArgsCount(args) {
        out = sbAppend(out, " ")
        out = sbAppend(out, processQuoteArg(processArgAt(args, i)))
        i += 1
    }
    emit sbToString(out)
}
