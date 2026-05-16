// Key-value map for Krypton
// Map is represented as "key1=val1\nkey2=val2\n..." string

module map


// Create new empty map
func mapNew() {
    emit ""
}

// Set a key-value pair in the map
func mapSet(m, key, val) {
    let sb = sbNew()
    let lines = lineCount(m)
    let found = 0
    let i = 0
    while i < lines {
        let line = getLine(m, i)
        // Find the = separator
        let eqPos = 0
        let j = 0
        while j < len(line) {
            if line[j] == "=" {
                eqPos = j
                break
            }
            j += 1
        }
        let lineKey = substring(line, 0, eqPos)
        if lineKey == key {
            sb = sbAppend(sb, key + "=" + val + "\n")
            found = 1
        } else {
            if len(line) > 0 {
                sb = sbAppend(sb, line + "\n")
            }
        }
        i += 1
    }
    if found == 0 {
        sb = sbAppend(sb, key + "=" + val + "\n")
    }
    emit sbToString(sb)
}

// Get a value by key, returns "" if not found
func mapGet(m, key) {
    let lines = lineCount(m)
    let i = 0
    while i < lines {
        let line = getLine(m, i)
        let eqPos = 0
        let j = 0
        while j < len(line) {
            if line[j] == "=" {
                eqPos = j
                break
            }
            j += 1
        }
        let lineKey = substring(line, 0, eqPos)
        if lineKey == key {
            emit substring(line, eqPos + 1, len(line))
        }
        i += 1
    }
    emit ""
}

// Check if key exists in map
func mapHas(m, key) {
    let lines = lineCount(m)
    let i = 0
    while i < lines {
        let line = getLine(m, i)
        if startsWith(line, key + "=") {
            emit 1
        }
        i += 1
    }
    emit 0
}

// Remove a key from the map
func mapRemove(m, key) {
    let sb = sbNew()
    let lines = lineCount(m)
    let i = 0
    while i < lines {
        let line = getLine(m, i)
        if len(line) > 0 {
            if startsWith(line, key + "=") == 0 {
                sb = sbAppend(sb, line + "\n")
            }
        }
        i += 1
    }
    emit sbToString(sb)
}

// Count entries in map
func mapSize(m) {
    if m == "" {
        emit 0
    }
    let cnt = 0
    let lines = lineCount(m)
    let i = 0
    while i < lines {
        let line = getLine(m, i)
        if len(line) > 0 {
            cnt += 1
        }
        i += 1
    }
    emit cnt
}

// Get all keys as comma-separated list
func mapKeys(m) {
    let result = ""
    let lines = lineCount(m)
    let i = 0
    while i < lines {
        let line = getLine(m, i)
        if len(line) > 0 {
            let j = 0
            while j < len(line) {
                if line[j] == "=" {
                    break
                }
                j += 1
            }
            let key = substring(line, 0, j)
            if result == "" {
                result = key
            } else {
                result = result + "," + key
            }
        }
        i += 1
    }
    emit result
}

// Print all map entries
func mapPrint(m) {
    let lines = lineCount(m)
    let i = 0
    while i < lines {
        let line = getLine(m, i)
        if len(line) > 0 {
            kp(line)
        }
        i += 1
    }
}
