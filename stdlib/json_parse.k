// lsp/json_parse.k — JSON parser producing flat dot-path map
//
// Strategy: rather than build a tree (awkward without rich struct
// support), walk JSON and record every leaf at its dotted path:
//
//     {"id":3,"params":{"textDocument":{"uri":"file:///x"}}}
//
//   id=3
//   params.textDocument.uri=file:///x
//
// Arrays use numeric path segments:
//
//     {"changes":[{"text":"foo"},{"text":"bar"}]}
//
//   changes.0.text=foo
//   changes.1.text=bar
//
// Plus a `__type__` sidecar map records the type of each leaf
// (s=string, n=number, b=bool, z=null) so consumers can distinguish
// "true" the string from true the bool. Arrays/objects record their
// length under `path.__len__` and `path.__keys__`.
//
// Storage is a custom string-encoded map where entries are joined by
// \x03 and key/value within an entry by \x04. These bytes never appear
// in JSON-RPC payloads, so values can contain anything (commas,
// newlines, tabs) without ambiguity. We can't use the C-path mapSet
// builtin (its comma-list format collides with JSON commas) and we
// can't use envSet (envGet writes "undefined variable" warnings to
// stderr on miss, which would pollute the LSP transport).

module json_parse

// Krypton string literals only honour \n \t \r \\ \" — there is no
// \xNN form. Build raw control-byte separators at runtime.
func sepRes()   { emit fromCharCode(2) }   // st<sepRes>m
func sepEntry() { emit fromCharCode(3) }   // entry<sepEntry>entry
func sepKV()    { emit fromCharCode(4) }   // key<sepKV>value

// === custom map ops ===

func jmNew() { emit "" }

func jmSet(m, k, v) {
    // Replace existing key if present; otherwise append.
    let n = len(m)
    let i = 0
    let entryStart = 0
    let sb = sbNew()
    let replaced = 0
    while i < n {
        if m[i] == sepEntry() {
            // entry from entryStart..i-1
            let entry = substring(m, entryStart, i)
            let sep = -1
            let j = 0
            while j < len(entry) {
                if entry[j] == sepKV() { sep = j  break }
                j += 1
            }
            if sep >= 0 {
                let kk = substring(entry, 0, sep)
                if kk == k {
                    sb = sbAppend(sb, kk + sepKV() + v + sepEntry())
                    replaced = 1
                } else {
                    sb = sbAppend(sb, entry + sepEntry())
                }
            }
            entryStart = i + 1
        }
        i += 1
    }
    if replaced == 0 {
        sb = sbAppend(sb, k + sepKV() + v + sepEntry())
    }
    emit sbToString(sb)
}

func jmGet(m, k) {
    let n = len(m)
    let i = 0
    let entryStart = 0
    while i < n {
        if m[i] == sepEntry() {
            let entry = substring(m, entryStart, i)
            let sep = -1
            let j = 0
            while j < len(entry) {
                if entry[j] == sepKV() { sep = j  break }
                j += 1
            }
            if sep >= 0 {
                let kk = substring(entry, 0, sep)
                if kk == k {
                    emit substring(entry, sep + 1, len(entry))
                }
            }
            entryStart = i + 1
        }
        i += 1
    }
    emit ""
}

func jmHas(m, k) {
    let n = len(m)
    let i = 0
    let entryStart = 0
    while i < n {
        if m[i] == sepEntry() {
            let entry = substring(m, entryStart, i)
            let sep = -1
            let j = 0
            while j < len(entry) {
                if entry[j] == sepKV() { sep = j  break }
                j += 1
            }
            if sep >= 0 {
                let kk = substring(entry, 0, sep)
                if kk == k { emit 1 }
            }
            entryStart = i + 1
        }
        i += 1
    }
    emit 0
}

// === public API ===

// Parse JSON text. Returns the flat-path map (suitable for jpGet/etc).
func jpParse(text) {
    let m = jmNew()
    let st = jpNew(text)
    st = jpSkipWS(st)
    let r = jpParseValue(st, "", m)
    emit jpMap(r)
}

// Lookup a leaf by dot path. Returns "" if missing.
func jpGet(m, path) {
    emit jmGet(m, path)
}

// Lookup the type of a leaf: "s","n","b","z","arr","obj","" (missing).
func jpTypeOf(m, path) {
    emit jmGet(m, "__type__\t" + path)
}

func jpHas(m, path) {
    emit jmHas(m, path)
}

// Array length at path (0 if missing/not array).
func jpArrLen(m, path) {
    let v = jmGet(m, path + ".__len__")
    if v == "" { emit 0 }
    emit toInt(v)
}

// Object keys at path as comma-separated string.
func jpObjKeys(m, path) {
    emit jmGet(m, path + ".__keys__")
}

// === parser state encoded as "i\tline\tcol\ttext" ===
// Carrying text inline keeps the API single-arg friendly across emits.
// (Krypton funcs return one value; struct shimming is heavier.)

func jpNew(text) {
    emit "0\t0\t0\t" + text
}

// Pull the Nth tab-separated header field (i, line, col) without using
// splitBy — JSON text certainly contains commas and would corrupt a
// comma-joined list. We only ever want the first three fields, so a
// linear scan is fine.

func jpHeaderField(st, idx) {
    let n = len(st)
    let i = 0
    let cur = 0
    let start = 0
    while i < n {
        if st[i] == "\t" {
            if cur == idx { emit substring(st, start, i) }
            cur += 1
            start = i + 1
            if cur > idx { break }
        }
        i += 1
    }
    emit "0"
}

func jpI(st)    { emit toInt(jpHeaderField(st, 0)) }
func jpLine(st) { emit toInt(jpHeaderField(st, 1)) }
func jpCol(st)  { emit toInt(jpHeaderField(st, 2)) }
func jpText(st) {
    let i = 0
    let tabs = 0
    while i < len(st) && tabs < 3 {
        if st[i] == "\t" { tabs += 1 }
        i += 1
    }
    emit substring(st, i, len(st))
}

func jpAdv(st, n) {
    let txt = jpText(st)
    let i = jpI(st)
    let line = jpLine(st)
    let col = jpCol(st)
    let k = 0
    while k < n {
        if i < len(txt) && txt[i] == "\n" { line += 1  col = 0 }
        else { col += 1 }
        i += 1
        k += 1
    }
    emit i + "\t" + line + "\t" + col + "\t" + txt
}

func jpPeek(st) {
    let txt = jpText(st)
    let i = jpI(st)
    if i >= len(txt) { emit "" }
    emit txt[i]
}

func jpSkipWS(st) {
    let txt = jpText(st)
    let i = jpI(st)
    while i < len(txt) {
        let c = txt[i]
        if c == " " || c == "\t" || c == "\n" || c == "\r" {
            st = jpAdv(st, 1)
            i = jpI(st)
            txt = jpText(st)
        } else {
            break
        }
    }
    emit st
}

// Result wrapper: "st<sepRes>map" so we can return both new state + map.
func jpRes(st, m) { emit st + sepRes() + m }
func jpStOf(r) {
    let i = 0
    while i < len(r) {
        if r[i] == sepRes() { emit substring(r, 0, i) }
        i += 1
    }
    emit r
}
func jpMap(r) {
    let i = 0
    while i < len(r) {
        if r[i] == sepRes() { emit substring(r, i + 1, len(r)) }
        i += 1
    }
    emit ""
}

func jpRecord(m, path, typ, val) {
    m = jmSet(m, path, val)
    m = jmSet(m, "__type__\t" + path, typ)
    emit m
}

// === recursive value parser ===

func jpParseValue(st, path, m) {
    st = jpSkipWS(st)
    let c = jpPeek(st)
    if c == "\"" { emit jpParseString(st, path, m) }
    if c == "{"  { emit jpParseObject(st, path, m) }
    if c == "["  { emit jpParseArray(st, path, m) }
    if c == "t" || c == "f" { emit jpParseBool(st, path, m) }
    if c == "n"  { emit jpParseNull(st, path, m) }
    if c == "-" || (c >= "0" && c <= "9") { emit jpParseNumber(st, path, m) }
    // Unknown — skip one char and bail with empty record.
    st = jpAdv(st, 1)
    emit jpRes(st, m)
}

func jpParseString(st, path, m) {
    // Consume opening "
    st = jpAdv(st, 1)
    let txt = jpText(st)
    let i = jpI(st)
    let sb = sbNew()
    while i < len(txt) {
        let c = txt[i]
        if c == "\"" { st = jpAdv(st, i - jpI(st) + 1)  break }
        if c == "\\" && i + 1 < len(txt) {
            let esc = txt[i + 1]
            if esc == "\"" { sb = sbAppend(sb, "\"") }
            else if esc == "\\" { sb = sbAppend(sb, "\\") }
            else if esc == "/"  { sb = sbAppend(sb, "/")  }
            else if esc == "n"  { sb = sbAppend(sb, "\n") }
            else if esc == "t"  { sb = sbAppend(sb, "\t") }
            else if esc == "r"  { sb = sbAppend(sb, "\r") }
            else if esc == "b"  { sb = sbAppend(sb, "\b") }
            else if esc == "f"  { sb = sbAppend(sb, "\f") }
            else if esc == "u" && i + 5 < len(txt) {
                // Decode \uXXXX → ASCII subset only (LSP messages are UTF-8;
                // upper bytes are passed through unchanged for now).
                let h = substring(txt, i + 2, i + 6)
                let v = 0
                let k = 0
                while k < 4 {
                    let hc = h[k]
                    let d = 0
                    if hc >= "0" && hc <= "9" { d = charCode(hc) - charCode("0") }
                    else if hc >= "a" && hc <= "f" { d = charCode(hc) - charCode("a") + 10 }
                    else if hc >= "A" && hc <= "F" { d = charCode(hc) - charCode("A") + 10 }
                    v = v * 16 + d
                    k += 1
                }
                if v < 128 { sb = sbAppend(sb, fromCharCode(v)) }
                i += 4   // 2 below for \u, then 4 for the hex digits
            }
            else { sb = sbAppend(sb, esc) }
            i += 2
            continue
        }
        sb = sbAppend(sb, c)
        i += 1
    }
    if path != "" {
        m = jpRecord(m, path, "s", sbToString(sb))
    }
    emit jpRes(st, m)
}

func jpParseNumber(st, path, m) {
    let txt = jpText(st)
    let start = jpI(st)
    let i = start
    if i < len(txt) && txt[i] == "-" { i += 1 }
    while i < len(txt) && txt[i] >= "0" && txt[i] <= "9" { i += 1 }
    if i < len(txt) && txt[i] == "." {
        i += 1
        while i < len(txt) && txt[i] >= "0" && txt[i] <= "9" { i += 1 }
    }
    if i < len(txt) && (txt[i] == "e" || txt[i] == "E") {
        i += 1
        if i < len(txt) && (txt[i] == "+" || txt[i] == "-") { i += 1 }
        while i < len(txt) && txt[i] >= "0" && txt[i] <= "9" { i += 1 }
    }
    let val = substring(txt, start, i)
    st = jpAdv(st, i - start)
    if path != "" {
        m = jpRecord(m, path, "n", val)
    }
    emit jpRes(st, m)
}

func jpParseBool(st, path, m) {
    let txt = jpText(st)
    let i = jpI(st)
    if i + 4 <= len(txt) && substring(txt, i, i + 4) == "true" {
        st = jpAdv(st, 4)
        if path != "" { m = jpRecord(m, path, "b", "true") }
        emit jpRes(st, m)
    }
    if i + 5 <= len(txt) && substring(txt, i, i + 5) == "false" {
        st = jpAdv(st, 5)
        if path != "" { m = jpRecord(m, path, "b", "false") }
        emit jpRes(st, m)
    }
    emit jpRes(st, m)
}

func jpParseNull(st, path, m) {
    let txt = jpText(st)
    let i = jpI(st)
    if i + 4 <= len(txt) && substring(txt, i, i + 4) == "null" {
        st = jpAdv(st, 4)
        if path != "" { m = jpRecord(m, path, "z", "") }
    }
    emit jpRes(st, m)
}

func jpJoin(parent, child) {
    if parent == "" { emit child }
    emit parent + "." + child
}

func jpParseObject(st, path, m) {
    st = jpAdv(st, 1)   // {
    st = jpSkipWS(st)
    let keys = ""
    if path != "" {
        m = jmSet(m, "__type__\t" + path, "obj")
    }
    if jpPeek(st) == "}" {
        st = jpAdv(st, 1)
        if path != "" {
            m = jmSet(m, path + ".__keys__", keys)
        }
        emit jpRes(st, m)
    }
    while jpI(st) < len(jpText(st)) {
        st = jpSkipWS(st)
        // key (must be string)
        if jpPeek(st) != "\"" { break }
        st = jpAdv(st, 1)
        let txt = jpText(st)
        let ki = jpI(st)
        let kSb = sbNew()
        while ki < len(txt) {
            let c = txt[ki]
            if c == "\"" { break }
            if c == "\\" && ki + 1 < len(txt) {
                kSb = sbAppend(kSb, txt[ki + 1])
                ki += 2
                continue
            }
            kSb = sbAppend(kSb, c)
            ki += 1
        }
        let keyName = sbToString(kSb)
        st = jpAdv(st, ki - jpI(st) + 1)
        st = jpSkipWS(st)
        if jpPeek(st) == ":" { st = jpAdv(st, 1) }
        st = jpSkipWS(st)
        let childPath = jpJoin(path, keyName)
        let r = jpParseValue(st, childPath, m)
        st = jpStOf(r)
        m = jpMap(r)
        if keys == "" { keys = keyName } else { keys = keys + "," + keyName }
        st = jpSkipWS(st)
        if jpPeek(st) == "," { st = jpAdv(st, 1)  continue }
        if jpPeek(st) == "}" { st = jpAdv(st, 1)  break }
        break
    }
    if path != "" {
        m = jmSet(m, path + ".__keys__", keys)
    }
    emit jpRes(st, m)
}

func jpParseArray(st, path, m) {
    st = jpAdv(st, 1)   // [
    st = jpSkipWS(st)
    let idx = 0
    if path != "" {
        m = jmSet(m, "__type__\t" + path, "arr")
    }
    if jpPeek(st) == "]" {
        st = jpAdv(st, 1)
        if path != "" {
            m = jmSet(m, path + ".__len__", "0")
        }
        emit jpRes(st, m)
    }
    while jpI(st) < len(jpText(st)) {
        st = jpSkipWS(st)
        let childPath = jpJoin(path, idx + "")
        let r = jpParseValue(st, childPath, m)
        st = jpStOf(r)
        m = jpMap(r)
        idx += 1
        st = jpSkipWS(st)
        if jpPeek(st) == "," { st = jpAdv(st, 1)  continue }
        if jpPeek(st) == "]" { st = jpAdv(st, 1)  break }
        break
    }
    if path != "" {
        m = jmSet(m, path + ".__len__", idx + "")
    }
    emit jpRes(st, m)
}
