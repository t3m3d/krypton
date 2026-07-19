// stdlib/process_win_env.k -- inherited/overridden UTF-16 environment blocks.
//
// Entries use one KEY=VALUE per line until Krypton gains a first-class map.
// Values containing newlines are not supported. A key without = removes it.

module process_win_env

import "k:bytes"
import "head:windows"
import "head:process"
func _processFindEquals(line) {
    let i = 0
    while i < len(line) {
        if substring(line, i, i + 1) == "=" { emit i }
        i += 1
    }
    emit -1
}

func _processEntryKey(line) {
    let eq = _processFindEquals(line)
    if eq < 0 { emit line }
    emit substring(line, 0, eq)
}

func _processSafeEntry(key, value) {
    let out = sbNew()
    out = sbAppend(out, key)
    out = sbAppend(out, "=")
    out = sbAppend(out, value)
    emit sbToString(out)
}

func _processMapValue(entries, key, fallback) {
    let wanted = toLower(key)
    let i = 0
    while i < lineCount(entries) {
        let line = getLine(entries, i)
        let eq = _processFindEquals(line)
        if eq > 0 && toLower(substring(line, 0, eq)) == wanted {
            emit substring(line, eq + 1, len(line))
        }
        i += 1
    }
    emit fallback
}

func _processEnvApply(entries, change) {
    let eq = _processFindEquals(change)
    let key = change
    let remove = 1
    if eq >= 0 {
        key = substring(change, 0, eq)
        remove = 0
    }
    if key == "" { emit entries }

    let wanted = toLower(key)
    let out = sbNew()
    let found = 0
    let i = 0
    while i < lineCount(entries) {
        let line = getLine(entries, i)
        if line != "" {
            let lineKey = toLower(_processEntryKey(line))
            if lineKey == wanted {
                found = 1
                if remove == 0 {
                    out = sbAppend(out, change)
                    out = sbAppend(out, "\n")
                }
            } else {
                out = sbAppend(out, line)
                out = sbAppend(out, "\n")
            }
        }
        i += 1
    }
    if found == 0 && remove == 0 {
        out = sbAppend(out, change)
        out = sbAppend(out, "\n")
    }
    emit sbToString(out)
}

func processEnvironmentNew() { emit "" }
func processEnvironmentSet(environment, key, value) {
    emit _processEnvApply(environment, _processSafeEntry(key, value))
}
func processEnvironmentRemove(environment, key) {
    emit _processEnvApply(environment, key)
}

func processOptionsNew() { emit "" }
func processOptionSet(options, key, value) {
    emit _processEnvApply(options, _processSafeEntry(key, value))
}

func _processTextLess(a, b) {
    let aa = toLower(_processEntryKey(a))
    let bb = toLower(_processEntryKey(b))
    let n = len(aa)
    if len(bb) < n { n = len(bb) }
    let i = 0
    while i < n {
        let ca = toInt(charCode(substring(aa, i, i + 1)))
        let cb = toInt(charCode(substring(bb, i, i + 1)))
        if ca < cb { emit 1 }
        if ca > cb { emit 0 }
        i += 1
    }
    emit len(aa) < len(bb)
}

func _processSortEnvironment(entries) {
    let total = lineCount(entries)
    let used = bytesWithLength(total)
    let out = sbNew()
    let emitted = 0
    while emitted < total {
        let best = -1
        let bestLine = ""
        let i = 0
        while i < total {
            let line = getLine(entries, i)
            if line != "" && bytesGet(used, i) == "0" {
                if best < 0 || _processTextLess(line, bestLine) {
                    best = i
                    bestLine = line
                }
            }
            i += 1
        }
        if best < 0 { break }
        bytesSet(used, best, 1)
        out = sbAppend(out, bestLine)
        out = sbAppend(out, "\n")
        emitted += 1
    }
    emit sbToString(out)
}

func _processParentEnvironment() {
    let block = GetEnvironmentStringsW()
    if ptrToInt(block) == "0" { emit "" }

    let out = sbNew()
    let offset = 0
    let done = 0
    // Bound malformed blocks to 16 MiB.
    while done == 0 && offset < 16777216 {
        let entry = bytesNew(128)
        while offset < 16777216 {
            let unit = toInt(bufGetWordAt(block, offset))
            offset += 2
            if unit == 0 { break }
            entry = bytesAppendU16LE(entry, unit)
        }
        if bytesLen(entry) == 0 {
            done = 1
        } else {
            let line = utf16leDecode(entry, 0)
            // Skip drive-current-directory pseudo variables (=C:=...).
            if line != "" && !startsWith(line, "=") {
                out = sbAppend(out, line)
                out = sbAppend(out, "\n")
            }
        }
    }
    FreeEnvironmentStringsW(block)
    emit sbToString(out)
}

func _processEnvironmentBlock(overrides, inheritEnvironment) {
    let entries = ""
    if inheritEnvironment != "0" && inheritEnvironment != 0 {
        entries = _processParentEnvironment()
    }
    let i = 0
    while i < lineCount(overrides) {
        let change = getLine(overrides, i)
        if change != "" { entries = _processEnvApply(entries, change) }
        i += 1
    }
    emit utf16leEnvironmentBlock(_processSortEnvironment(entries))
}
