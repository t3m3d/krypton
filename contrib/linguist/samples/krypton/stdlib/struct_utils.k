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
func structFromMap(map) {
    let obj = structNew()
    let ks = keys(map)
    for k in ks {
        setField(obj, k, mapGet(map, k))
    }
    emit obj
}

// Convert a struct to a map
func structToMap(obj) {
    let map = ""
    let fields = structFields(obj)
    for field in fields {
        map = mapSet(map, field, getField(obj, field))
    }
    emit map
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
