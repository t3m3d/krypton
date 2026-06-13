// stdlib/list_py.k -- Krypton list functions shaped to match the
// semantics the upcoming Python frontend will lower method-call
// syntax to.  Lists are comma-separated strings.
//
// Names use the `*k` suffix convention (matches builtins.k +
// string_py.k) so they don't shadow Krypton's own builtins and so
// user-side code never sees "Python" leaking through identifiers.
//
// FE lowering examples:
//   xs.append(v)         -> appendk(xs, v)
//   xs.extend(ys)        -> extendk(xs, ys)
//   xs.pop()             -> popk(xs, -1)
//   xs[lo:hi]            -> slicek(xs, lo, hi)
//   x in xs              -> inlistk(x, xs)
//
// Krypton strings are immutable so "mutating" Python methods return
// new lists (or the new + popped element as a pair where needed).

module list_py


// ── Construction / size ───────────────────────────────────────────────

// Empty list literal.  Constant return makes call sites readable.
func emptylistk() {
    emit ""
}

// listlenk(xs) -- alias of Krypton's count() for comma-lists.
func listlenk(xs) {
    emit count(xs)
}


// ── Add / extend ──────────────────────────────────────────────────────

func appendk(xs, x) {
    if xs == "" { emit "" + x }
    emit xs + "," + x
}

func extendk(xs, ys) {
    if xs == "" { emit ys }
    if ys == "" { emit xs }
    emit xs + "," + ys
}

func insertk(xs, i, x) {
    let n = count(xs)
    let idx = toInt(i)
    if idx < 0 { idx = 0 }
    if idx >= n { emit appendk(xs, x) }
    let out = sbNew()
    let k = 0
    let first = "1"
    while k < n {
        if k == idx {
            if first == "0" { out = sbAppend(out, ",") }
            out = sbAppend(out, x)
            first = "0"
        }
        if first == "0" { out = sbAppend(out, ",") }
        out = sbAppend(out, split(xs, k))
        first = "0"
        k += 1
    }
    emit sbToString(out)
}


// ── Remove ────────────────────────────────────────────────────────────

// removek(xs, x) -- remove FIRST occurrence of x; xs unchanged if absent.
func removek(xs, x) {
    let n = count(xs)
    let out = sbNew()
    let removed = "0"
    let i = 0
    let first = "1"
    while i < n {
        let v = split(xs, i)
        if removed == "0" && v == x {
            removed = "1"
        } else {
            if first == "0" { out = sbAppend(out, ",") }
            out = sbAppend(out, v)
            first = "0"
        }
        i += 1
    }
    emit sbToString(out)
}

// withoutk(xs, i) -- remove element AT INDEX i, return new list.
// Negative i counts from the end (Python convention).
func withoutk(xs, i) {
    let n = count(xs)
    let idx = toInt(i)
    if idx < 0 { idx = n + idx }
    if idx < 0 || idx >= n { emit xs }
    let out = sbNew()
    let j = 0
    let first = "1"
    while j < n {
        if j != idx {
            if first == "0" { out = sbAppend(out, ",") }
            out = sbAppend(out, split(xs, j))
            first = "0"
        }
        j += 1
    }
    emit sbToString(out)
}

// popk(xs, i) -- return element at position i.  Negative i = from end.
// Companion to withoutk: a Python `x = xs.pop()` lowers to:
//   x = popk(xs, -1)
//   xs = withoutk(xs, -1)
func popk(xs, i) {
    let n = count(xs)
    let idx = toInt(i)
    if idx < 0 { idx = n + idx }
    if idx < 0 || idx >= n { emit "" }
    emit split(xs, idx)
}

// clearedk(xs) -- return empty list.  Always "".  Symmetric with
// Python's xs.clear() at the value-level (FE lowering: xs = clearedk(xs)).
func clearedk(xs) {
    emit ""
}


// ── Search ────────────────────────────────────────────────────────────

// listIndexk(xs, x) -- first position of x, or -1.  Python's
// list.index raises ValueError on miss; we return -1 to match the
// indexOf convention.
func listIndexk(xs, x) {
    let n = count(xs)
    let i = 0
    while i < n {
        if split(xs, i) == x { emit i }
        i += 1
    }
    emit -1
}

// listCountk(xs, x) -- count occurrences of x.  Distinct from
// string_py.k's countk (which counts substring occurrences inside a
// string).  The FE picks the right one based on whether the receiver
// type is list or str.
func listCountk(xs, x) {
    let n = count(xs)
    let i = 0
    let c = 0
    while i < n {
        if split(xs, i) == x { c += 1 }
        i += 1
    }
    emit c
}

// inlistk(x, xs) -- Python `x in xs` membership test.  Returns int 1/0.
func inlistk(x, xs) {
    let n = count(xs)
    let i = 0
    while i < n {
        if split(xs, i) == x { emit 1 }
        i += 1
    }
    emit 0
}


// ── Slicing / copy ────────────────────────────────────────────────────

// slicek(xs, lo, hi) -- Python xs[lo:hi].  Negative indices count
// from the end.  Out-of-range gets clamped (Python tolerates this).
func slicek(xs, lo, hi) {
    let n = count(xs)
    let l = toInt(lo)
    let h = toInt(hi)
    if l < 0 { l = n + l }
    if h < 0 { h = n + h }
    if l < 0 { l = 0 }
    if h > n { h = n }
    if l >= h { emit "" }
    let out = sbNew()
    let i = l
    let first = "1"
    while i < h {
        if first == "0" { out = sbAppend(out, ",") }
        out = sbAppend(out, split(xs, i))
        first = "0"
        i += 1
    }
    emit sbToString(out)
}

// copyk(xs) -- Krypton strings are immutable; copy is identity.
// Kept so FE lowering of xs.copy() resolves cleanly.
func copyk(xs) {
    emit xs
}


// ── Reverse / sort (list-flavored) ────────────────────────────────────
// reversedk and sortedk live in builtins.k.  The list-method
// lowerings (xs.reverse() / xs.sort()) route through those, since
// Krypton's functional shape already returns new lists.

// listGetk(xs, i) -- xs[i] index-read with negative-index support.
// FE lowers xs[i] to listGetk(xs, i) where the integer i is the index.
func listGetk(xs, i) {
    let n = count(xs)
    let idx = toInt(i)
    if idx < 0 { idx = n + idx }
    if idx < 0 || idx >= n { emit "" }
    emit split(xs, idx)
}

// listSetk(xs, i, v) -- xs[i] = v, returns new list.  Negative
// indices count from the end.  Out-of-range = original list.
func listSetk(xs, i, v) {
    let n = count(xs)
    let idx = toInt(i)
    if idx < 0 { idx = n + idx }
    if idx < 0 || idx >= n { emit xs }
    let out = sbNew()
    let j = 0
    let first = "1"
    while j < n {
        if first == "0" { out = sbAppend(out, ",") }
        if j == idx { out = sbAppend(out, v) } else { out = sbAppend(out, split(xs, j)) }
        first = "0"
        j += 1
    }
    emit sbToString(out)
}

// Coverage notes
// --------------
// Shipped (15 funcs):
//   emptylistk listlenk
//   appendk extendk insertk
//   removek withoutk popk clearedk
//   listIndexk listCountk inlistk
//   slicek copyk listGetk listSetk
//
// FE relies on these names for these lowerings:
//   xs.append(v)         -> appendk(xs, v)
//   xs.extend(ys)        -> extendk(xs, ys)
//   xs.insert(i, v)      -> insertk(xs, i, v)
//   xs.remove(v)         -> removek(xs, v)
//   xs.pop()             -> popk(xs, -1) + withoutk in companion stmt
//   xs.pop(i)            -> popk(xs, i)  + withoutk in companion stmt
//   xs.clear()           -> clearedk(xs)
//   xs.index(v)          -> listIndexk(xs, v)
//   xs.count(v)          -> listCountk(xs, v)
//   xs.copy()            -> copyk(xs)
//   xs[i]                -> listGetk(xs, i)
//   xs[i] = v            -> listSetk(xs, i, v)
//   xs[lo:hi]            -> slicek(xs, lo, hi)
//   v in xs              -> inlistk(v, xs)
//   xs.reverse()         -> reversedk(xs)         (builtins.k)
//   xs.sort()            -> sortedk(xs)           (builtins.k)
//
// Not yet covered (deferred):
//   xs.sort(key=...)     -- needs FE support for keyword args
//   xs.sort(reverse=...) -- needs keyword args
//   list comprehensions  -- handled at FE level, not stdlib
