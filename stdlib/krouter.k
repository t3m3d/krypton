// stdlib/krouter.k — a tiny path router for the Krypton web framework.
//
// Turns the manual `if path == "/x" else if startsWith(path, "/y/") ...`
// chains into pattern matching with named params:
//
//   if routeIs(method, path, "POST", "/todo/:id") {
//       let id = routeParam("/todo/:id", path, "id")
//       ...
//   }
//
// Patterns are slash-segmented. A segment beginning with ":" is a wildcard
// that matches any single non-empty segment and captures it by name. A
// trailing "*" segment matches the rest of the path (catch-all).
//
//   "/"               matches "/"
//   "/todo/:id"       matches "/todo/3"      (id = "3")
//   "/users/:id/edit" matches "/users/42/edit" (id = "42")
//   "/static/*"       matches "/static/a/b/c"

module krouter

// ── segment helpers ──────────────────────────────────────────────────
// Number of non-empty segments in a path ("/a/b" -> 2, "/" -> 0).
func _rtSegCount(path) {
    let n = len(path)
    let c = 0
    let i = 0
    let inSeg = 0
    while i < n {
        if path[i] == "/" { inSeg = 0 }
        else { if inSeg == 0 { c += 1 } inSeg = 1 }
        i += 1
    }
    emit c
}

// The idx-th (0-based) non-empty segment, or "" if out of range.
func _rtSeg(path, idx) {
    let n = len(path)
    let cur = -1
    let i = 0
    let inSeg = 0
    let start = 0
    while i < n {
        if path[i] == "/" {
            if inSeg == 1 { if cur == idx { emit substring(path, start, i) } }
            inSeg = 0
        } else {
            if inSeg == 0 { cur += 1  start = i }
            inSeg = 1
        }
        i += 1
    }
    if inSeg == 1 { if cur == idx { emit substring(path, start, n) } }
    emit ""
}

func _rtIsParam(seg) {
    if len(seg) == 0 { emit 0 }
    if seg[0] == ":" { emit 1 }
    emit 0
}

// ── matching ──────────────────────────────────────────────────────────
// 1 if `path` matches `pattern`, else 0. A "*" final pattern segment is a
// catch-all (matches one or more remaining segments).
func routeMatches(pattern, path) {
    let pc = _rtSegCount(pattern)
    let xc = _rtSegCount(path)

    // catch-all: last pattern segment is "*"
    let last = _rtSeg(pattern, pc - 1)
    let catchAll = 0
    if last == "*" { catchAll = 1 }

    if catchAll == 0 {
        if pc != xc { emit 0 }
    } else {
        // need at least (pc-1) fixed segments, plus 1+ for the star
        if xc < pc { emit 0 }
    }

    let i = 0
    let fixed = pc
    if catchAll == 1 { fixed = pc - 1 }
    while i < fixed {
        let ps = _rtSeg(pattern, i)
        let xs = _rtSeg(path, i)
        if _rtIsParam(ps) == 0 {
            if ps != xs { emit 0 }       // literal segment must match exactly
        }
        // param segment matches any non-empty segment (xs is non-empty by
        // construction of _rtSegCount), so nothing to check.
        i += 1
    }
    emit 1
}

// Method + path match in one call. method "" or "*" matches any method.
func routeIs(reqMethod, reqPath, wantMethod, pattern) {
    if wantMethod != "" {
        if wantMethod != "*" {
            if reqMethod != wantMethod { emit 0 }
        }
    }
    emit routeMatches(pattern, reqPath)
}

// ── param extraction ──────────────────────────────────────────────────
// The captured value for ":name" in `pattern`, taken positionally from
// `path`. Returns "" if the name isn't in the pattern.
func routeParam(pattern, path, name) {
    let want = ":" + name
    let pc = _rtSegCount(pattern)
    let i = 0
    while i < pc {
        if _rtSeg(pattern, i) == want { emit _rtSeg(path, i) }
        i += 1
    }
    emit ""
}

// The catch-all tail: everything matched by a trailing "*", as "a/b/c".
func routeTail(pattern, path) {
    let pc = _rtSegCount(pattern)
    let xc = _rtSegCount(path)
    let out = ""
    let i = pc - 1                      // first segment the "*" covers
    while i < xc {
        if len(out) > 0 { out = out + "/" }
        out = out + _rtSeg(path, i)
        i += 1
    }
    emit out
}
