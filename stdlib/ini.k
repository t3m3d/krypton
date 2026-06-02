// stdlib/ini.k — INI / .conf parser in PURE KRYPTON. No C.
//
// Stateless & text-threaded (like k:server_native): you hold the raw file
// text and query it. No map state crosses the import boundary, so this is
// safe to import.
//
//   let cfg = readFile("app.ini")
//   iniGet(cfg, "server", "port", "8080")   // section/key, with default
//   iniGet(cfg, "", "name", "?")            // "" section = keys before any [section]
//   iniHas(cfg, "server", "tls")            // "1" / "0"
//
// Format: "[section]" headers, "key = value" or "key: value" pairs, ";" or "#"
// line comments, surrounding whitespace trimmed. Section/key match is
// case-insensitive.

module ini

// toLower is a no-op on the native backend; do ASCII lowercasing by hand.
func _lc(s) {
    let out = ""
    let i = 0
    while i < len(s) {
        let v = toInt(charCode(s[i]))
        if v >= 65 && v <= 90 { out = out + fromCharCode(v + 32) }
        else { out = out + s[i] }
        i += 1
    }
    emit out
}

// strip an inline/full-line comment starting at ';' or '#'.
func _stripComment(line) {
    let semi = indexOf(line, ";")
    let hash = indexOf(line, "#")
    let cut = 0 - 1
    if semi >= 0 { cut = semi }
    if hash >= 0 {
        if cut < 0 { cut = hash }
        else if hash < cut { cut = hash }
    }
    if cut >= 0 { emit substring(line, 0, cut) }
    emit line
}

func _sectName(line) {
    let t = trim(line)
    if startsWith(t, "[") {
        let close = indexOf(t, "]")
        if close > 0 { emit _lc(trim(substring(t, 1, close))) }
    }
    emit ""
}

func _keyOf(line) {
    let eq = indexOf(line, "=")
    let colon = indexOf(line, ":")
    let cut = eq
    if cut < 0 { cut = colon }
    else if colon >= 0 {
        if colon < cut { cut = colon }
    }
    if cut < 0 { emit "" }
    emit _lc(trim(substring(line, 0, cut)))
}

func _valOf(line) {
    let eq = indexOf(line, "=")
    let colon = indexOf(line, ":")
    let cut = eq
    if cut < 0 { cut = colon }
    else if colon >= 0 {
        if colon < cut { cut = colon }
    }
    if cut < 0 { emit "" }
    emit trim(substring(line, cut + 1, len(line)))
}

// iniGet(text, section, key, dflt) -> the value, or dflt if not found.
// section "" means keys appearing before the first [section] header.
func iniGet(text, section, key, dflt) {
    let want = _lc(section)
    let wantKey = _lc(key)
    let cur = ""
    let total = lineCount(text)
    let i = 0
    while i < total {
        let raw = _stripComment(getLine(text, i))
        let line = trim(raw)
        if len(line) > 0 {
            let sect = _sectName(line)
            if sect != "" {
                cur = sect
            } else {
                if cur == want {
                    if _keyOf(line) == wantKey {
                        emit _valOf(line)
                    }
                }
            }
        }
        i += 1
    }
    emit dflt
}

// iniHas(text, section, key) -> "1" if the key exists in the section.
func iniHas(text, section, key) {
    let sentinel = fromCharCode(1)
    if iniGet(text, section, key, sentinel) == sentinel { emit "0" }
    emit "1"
}

// iniInt(text, section, key, dflt) -> value parsed as int (dflt is an int).
func iniInt(text, section, key, dflt) {
    let v = iniGet(text, section, key, "")
    if v == "" { emit dflt }
    emit toInt(v)
}

// iniBool(text, section, key) -> "1" for true/yes/on/1, else "0".
func iniBool(text, section, key) {
    let v = _lc(iniGet(text, section, key, ""))
    if v == "1" { emit "1" }
    if v == "true" { emit "1" }
    if v == "yes" { emit "1" }
    if v == "on" { emit "1" }
    emit "0"
}

// iniSections(text) -> comma-separated list of section names (lowercased).
func iniSections(text) {
    let out = ""
    let total = lineCount(text)
    let i = 0
    while i < total {
        let line = trim(_stripComment(getLine(text, i)))
        let sect = _sectName(line)
        if sect != "" {
            if len(out) > 0 { out = out + "," }
            out = out + sect
        }
        i += 1
    }
    emit out
}
