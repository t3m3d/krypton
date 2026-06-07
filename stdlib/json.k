// json.k — Simple JSON builder for Krypton
// Produces JSON strings from Krypton values

module json

func jsonStr(s) {
    emit "\"" + replace(replace(s, "\\", "\\\\"), "\"", "\\\"") + "\""
}

func jsonNum(n) {
    emit n + ""
}

func jsonBool(b) {
    if b == "1" || b == "true" { emit "true" }
    emit "false"
}

func jsonNull() {
    emit "null"
}

func jsonArray(lst) {
    if len(lst) == 0 { emit "[]" }
    let sb = sbNew()
    sb = sbAppend(sb, "[")
    let cnt = length(lst)
    let i = 0
    for item in lst {
        if i > 0 { sb = sbAppend(sb, ",") }
        sb = sbAppend(sb, jsonStr(item))
        i += 1
    }
    sb = sbAppend(sb, "]")
    emit sbToString(sb)
}

// jsonObject(map) — `map` is a k:map value (a "key=val\n…" string). Parsed
// directly here so json.k stays self-contained (no k:map import needed — and
// the old keys()/mapGet() native-map builtins were broken/removed).
func jsonObject(map) {
    let sb = sbNew()
    sb = sbAppend(sb, "{")
    let lines = lineCount(map)
    let i = 0
    let first = 1
    while i < lines {
        let line = getLine(map, i)
        if len(line) > 0 {
            let j = 0
            while j < len(line) { if line[j] == "=" { break }  j += 1 }
            let k = substring(line, 0, j)
            let v = substring(line, j + 1, len(line))
            if first == 0 { sb = sbAppend(sb, ",") }
            sb = sbAppend(sb, jsonStr(k) + ":" + jsonStr(v))
            first = 0
        }
        i += 1
    }
    sb = sbAppend(sb, "}")
    emit sbToString(sb)
}
