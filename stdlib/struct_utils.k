// struct_utils.k — utilities for working with structs and dynamic objects

module struct_utils

// Convert a struct to a display string: "Name{field1: val1, field2: val2}"
func structToString(obj, typeName) {
    let fields = structFields(obj)
    if len(fields) == 0 {
        emit typeName + "{}"
    }
    let sb = sbNew()
    sb = sbAppend(sb, typeName + "{")
    let cnt = length(fields)
    let i = 0
    for field in fields {
        if i > 0 { sb = sbAppend(sb, ", ") }
        sb = sbAppend(sb, field + ": " + getField(obj, field))
        i += 1
    }
    sb = sbAppend(sb, "}")
    emit sbToString(sb)
}

// Copy all fields from src struct to dst struct
func structCopy(src, dst) {
    let fields = structFields(src)
    for field in fields {
        setField(dst, field, getField(src, field))
    }
    emit dst
}

// Create a struct from a map (key-value pairs)
// `map` is a k:map value (a "key=val\n…" string). Parsed inline so this module
// stays self-contained (the old keys()/mapGet() native-map builtins were
// broken/removed; transitive k:map import wouldn't link for importers anyway).
func structFromMap(map) {
    let obj = structNew()
    let lines = lineCount(map)
    let i = 0
    while i < lines {
        let line = getLine(map, i)
        if len(line) > 0 {
            let j = 0
            while j < len(line) { if line[j] == "=" { break }  j += 1 }
            setField(obj, substring(line, 0, j), substring(line, j + 1, len(line)))
        }
        i += 1
    }
    emit obj
}

// Convert a struct to a k:map value (a "key=val\n…" string).
func structToMap(obj) {
    let sb = sbNew()
    let fields = structFields(obj)
    for field in fields {
        sb = sbAppend(sb, field + "=" + getField(obj, field) + "\n")
    }
    emit sbToString(sb)
}

// Check if two structs have identical fields and values
func structEqual(a, b) {
    let fa = structFields(a)
    let fb = structFields(b)
    if fa != fb { emit 0 }
    for field in fa {
        if getField(a, field) != getField(b, field) { emit 0 }
    }
    emit 1
}
