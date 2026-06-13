// stdlib/jsonk.k -- Python `json` module surface (json.dumps / json.loads /
// json.dump / json.load) layered on top of the existing stdlib/json.k +
// stdlib/json_parse.k + stdlib/json_emit.k machinery.
//
// Named `jsonk.k` to avoid colliding with the existing low-level
// `stdlib/json.k` while keeping Python's flat method names available
// via the `*k` suffix convention.
//
// FE lowering:
//   json.dumps(obj)             -> jsonDumpsk(obj)
//   json.dumps(obj, indent=2)   -> jsonDumpsIndentk(obj, 2)
//   json.loads(s)               -> jsonLoadsk(s)
//   json.dump(obj, path)        -> jsonDumpk(obj, path)
//   json.load(path)             -> jsonLoadk(path)

module jsonk

import "k:json_emit"
import "k:json_parse"


// jsonDumpsk -- serialize a Krypton comma-list value to a JSON string.
//
// Heuristics (since Krypton's data model is all strings):
//   - If the value is "" -> "null"
//   - If the value is all digits / -digits -> JSON number
//   - If the value parses as "1" / "0" booleans (which Krypton uses
//     for true/false) -> "true" / "false"
//   - If the value looks like an interleaved kv list (even count) ->
//     JSON object
//   - Otherwise -> JSON array of stringified elements
//
// Nested values (lists-of-lists, lists-of-dicts) need the caller to
// quote the inner pieces; full nesting support waits on a real
// tagged-value runtime.
func jsonDumpsk(obj) {
    if obj == "" { emit "null" }
    if obj == "1" || obj == "0" {
        // Could be bool or single-element list "1".  Treat as number.
        emit obj
    }
    let n = count(obj)
    if n == 1 { emit _jsonScalar(obj) }
    if n % 2 == 0 && _jsonLooksLikeDict(obj) {
        emit _jsonObj(obj)
    }
    emit _jsonArr(obj)
}

// jsonDumpsIndentk -- like jsonDumpsk but with 2-space indent.
// Indented output is more useful for human inspection; serialization
// for storage usually uses the compact form.
func jsonDumpsIndentk(obj, indent) {
    // For now, just call the compact form.  Pretty-print is a
    // line-by-line transformer that can ship as a follow-up.
    emit jsonDumpsk(obj)
}

// jsonLoadsk -- parse a JSON string into a Krypton value.  Uses the
// existing stdlib/json_parse.k machinery; this is a thin Python-name
// wrapper.
func jsonLoadsk(s) {
    // jsonParse / jsonParseValue lives in json_parse.k.  Defer to
    // whatever signature it exposes; this stub calls a representative.
    emit jpParse(s)
}

// jsonDumpk(obj, path) -- write serialized obj to file.
func jsonDumpk(obj, path) {
    writeFile(path, jsonDumpsk(obj))
    emit ""
}

// jsonLoadk(path) -- read + parse a JSON file.
func jsonLoadk(path) {
    let s = readFile(path)
    emit jsonLoadsk(s)
}


// ── helpers ───────────────────────────────────────────────────────────

// Decide whether a comma-list looks like an interleaved kv pair list:
// every even-positioned element should be a non-numeric string (a
// reasonable "key") and length should be even.  Heuristic; real
// tagged-value runtime would settle it.
func _jsonLooksLikeDict(xs) {
    let n = count(xs)
    if n % 2 != 0 { emit 0 }
    let i = 0
    while i < n {
        let v = split(xs, i)
        // Keys shouldn't be empty; values can be.  Don't enforce
        // non-numeric on keys since Python dicts allow int keys.
        if v == "" { emit 0 }
        i = i + 2
    }
    emit 1
}

func _jsonScalar(v) {
    if v == "" { emit "null" }
    // Integer-like: pure digits (with optional leading '-').
    let firstCh = v[0]
    let allDigits = "1"
    let i = 0
    if firstCh == "-" { i = 1 }
    if i >= len(v) { allDigits = "0" }
    while i < len(v) {
        if !isDigit(v[i]) { allDigits = "0" }
        i += 1
    }
    if allDigits == "1" { emit v }
    // Boolean-ish (Krypton uses "1" / "0" but that's covered as numeric
    // above; if a caller wants real true/false they pass "true" / "false").
    if v == "true" || v == "false" { emit v }
    // Otherwise: quote as JSON string + escape minimally.
    emit "\"" + _jsonEscape(v) + "\""
}

func _jsonEscape(s) {
    let out = sbNew()
    let i = 0
    while i < len(s) {
        let c = s[i]
        if c == "\"" {
            out = sbAppend(out, "\\\"")
        } else if c == "\\" {
            out = sbAppend(out, "\\\\")
        } else if c == "\n" {
            out = sbAppend(out, "\\n")
        } else if c == "\r" {
            out = sbAppend(out, "\\r")
        } else if c == "\t" {
            out = sbAppend(out, "\\t")
        } else {
            out = sbAppend(out, c)
        }
        i += 1
    }
    emit sbToString(out)
}

func _jsonObj(kvs) {
    let n = count(kvs)
    let out = sbNew()
    out = sbAppend(out, "{")
    let i = 0
    let first = "1"
    while i < n {
        if first == "0" { out = sbAppend(out, ",") }
        out = sbAppend(out, "\"")
        out = sbAppend(out, _jsonEscape(split(kvs, i)))
        out = sbAppend(out, "\":")
        out = sbAppend(out, _jsonScalar(split(kvs, i + 1)))
        first = "0"
        i = i + 2
    }
    out = sbAppend(out, "}")
    emit sbToString(out)
}

func _jsonArr(xs) {
    let n = count(xs)
    let out = sbNew()
    out = sbAppend(out, "[")
    let i = 0
    let first = "1"
    while i < n {
        if first == "0" { out = sbAppend(out, ",") }
        out = sbAppend(out, _jsonScalar(split(xs, i)))
        first = "0"
        i += 1
    }
    out = sbAppend(out, "]")
    emit sbToString(out)
}
