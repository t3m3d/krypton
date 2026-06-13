// stdlib/itertools.k -- Python `itertools` module surface on existing
// Krypton primitives.  Names use the `*k` suffix convention.
//
// Lists are comma-separated strings; the iterator protocol is
// blocked on B5 (goroutines), so these functions are eager and
// materialize their result instead of yielding lazily.  When B5
// lands, swap the eager bodies for goroutine-backed generators
// without changing the surface.
//
// FE lowering:
//   itertools.chain(a, b)        -> chaink(a, b)
//   itertools.count(start)       -> countitk(start)        (finite, see below)
//   itertools.cycle(xs)          -> cyclek(xs, n)
//   itertools.repeat(x, n)       -> repeatk(x, n)
//   itertools.accumulate(xs)     -> accumulatek(xs)
//   itertools.takewhile(p, xs)   -> takewhilek(p, xs)
//   itertools.dropwhile(p, xs)   -> dropwhilek(p, xs)
//   itertools.filterfalse(p, xs) -> filterfalsek(p, xs)
//   itertools.compress(xs, sel)  -> compressk(xs, sel)
//   itertools.pairwise(xs)       -> pairwisek(xs)
//   itertools.combinations(xs,r) -> combinationsk(xs, r)
//   itertools.permutations(xs,r) -> permutationsk(xs, r)
//   itertools.product(a, b)      -> productk(a, b)
//   itertools.groupby(xs)        -> groupbyk(xs)

module itertools


// Concatenate two lists.  Python: itertools.chain.  Variadic chain
// (>2 args) blocked on A4; until then chain calls compose.
func chaink(a, b) {
    if a == "" { emit b }
    if b == "" { emit a }
    emit a + "," + b
}

// chain_from_iterable -- flatten a comma-list-of-comma-lists.  Caller
// represents inner lists with `;` separators to avoid the obvious
// confusion: "a;b,c;d" -> ["a;b", "c;d"] before flatten -> "a,b,c,d"
// after.  Real impl would need real nested types (Tier B).
func chainFromIterablek(xs) {
    emit replace(xs, ";", ",")
}

// count(start, step) -- finite-N counter to stay sane on eager build.
// Default n = 100; tune via the third arg.  Real Python.itertools.count
// is infinite; goroutine-backed gen once B5 lands.
func countitk(start, step, n) {
    let s = toInt(start)
    let st = toInt(step)
    let limit = toInt(n)
    if limit <= 0 { limit = 100 }
    let out = sbNew()
    let i = 0
    let first = "1"
    while i < limit {
        if first == "0" { out = sbAppend(out, ",") }
        out = sbAppend(out, "" + (s + st * i))
        first = "0"
        i += 1
    }
    emit sbToString(out)
}

// cycle(xs, n) -- xs repeated to total n items (Python's cycle is
// infinite; we cap to be eager-compatible).
func cyclek(xs, n) {
    let total = toInt(n)
    let m = count(xs)
    if m == 0 || total == 0 { emit "" }
    let out = sbNew()
    let i = 0
    let first = "1"
    while i < total {
        if first == "0" { out = sbAppend(out, ",") }
        out = sbAppend(out, split(xs, i % m))
        first = "0"
        i += 1
    }
    emit sbToString(out)
}

// repeat(x, n) -- n copies of x.
func repeatk(x, n) {
    let times = toInt(n)
    if times <= 0 { emit "" }
    let out = sbNew()
    let first = "1"
    let i = 0
    while i < times {
        if first == "0" { out = sbAppend(out, ",") }
        out = sbAppend(out, x)
        first = "0"
        i += 1
    }
    emit sbToString(out)
}

// accumulate(xs) -- running sums.  Numeric-only today.
func accumulatek(xs) {
    let n = count(xs)
    if n == 0 { emit "" }
    let acc = toInt(split(xs, 0))
    let out = sbNew()
    out = sbAppend(out, "" + acc)
    let i = 1
    while i < n {
        acc = acc + toInt(split(xs, i))
        out = sbAppend(out, ",")
        out = sbAppend(out, "" + acc)
        i += 1
    }
    emit sbToString(out)
}

// takewhile(pred, xs) -- prefix where pred holds.
func takewhilek(pred: closure, xs) {
    let n = count(xs)
    let out = sbNew()
    let i = 0
    let first = "1"
    while i < n {
        let v = split(xs, i)
        if !isTruthy(pred(v)) { break }
        if first == "0" { out = sbAppend(out, ",") }
        out = sbAppend(out, v)
        first = "0"
        i += 1
    }
    emit sbToString(out)
}

// dropwhile(pred, xs) -- suffix after pred first fails.
func dropwhilek(pred: closure, xs) {
    let n = count(xs)
    let i = 0
    let dropping = "1"
    let out = sbNew()
    let first = "1"
    while i < n {
        let v = split(xs, i)
        if dropping == "1" {
            if !isTruthy(pred(v)) { dropping = "0" }
        }
        if dropping == "0" {
            if first == "0" { out = sbAppend(out, ",") }
            out = sbAppend(out, v)
            first = "0"
        }
        i += 1
    }
    emit sbToString(out)
}

// filterfalse(pred, xs) -- items where pred is falsy.
func filterfalsek(pred: closure, xs) {
    let n = count(xs)
    let out = sbNew()
    let i = 0
    let first = "1"
    while i < n {
        let v = split(xs, i)
        if !isTruthy(pred(v)) {
            if first == "0" { out = sbAppend(out, ",") }
            out = sbAppend(out, v)
            first = "0"
        }
        i += 1
    }
    emit sbToString(out)
}

// compress(xs, selectors) -- keep xs[i] where selectors[i] is truthy.
func compressk(xs, selectors) {
    let n = count(xs)
    let m = count(selectors)
    if m < n { n = m }
    let out = sbNew()
    let i = 0
    let first = "1"
    while i < n {
        if isTruthy(split(selectors, i)) {
            if first == "0" { out = sbAppend(out, ",") }
            out = sbAppend(out, split(xs, i))
            first = "0"
        }
        i += 1
    }
    emit sbToString(out)
}

// pairwise(xs) -- sliding pairs.  "1,2,3,4" -> "1;2,2;3,3;4"
// (inner pairs use ; to keep the comma-list shape).
func pairwisek(xs) {
    let n = count(xs)
    if n < 2 { emit "" }
    let out = sbNew()
    let i = 0
    let first = "1"
    while i < n - 1 {
        if first == "0" { out = sbAppend(out, ",") }
        out = sbAppend(out, split(xs, i))
        out = sbAppend(out, ";")
        out = sbAppend(out, split(xs, i + 1))
        first = "0"
        i += 1
    }
    emit sbToString(out)
}

// combinations(xs, r) -- r-element combinations.  Each combination
// uses `;` internal separator; the outer list uses `,`.
func combinationsk(xs, r) {
    let n = count(xs)
    let rv = toInt(r)
    if rv > n || rv < 0 { emit "" }
    let out = sbNew()
    let indices = ""
    let i = 0
    while i < rv { if i > 0 { indices = indices + "," }  indices = indices + i  i += 1 }
    let first = "1"
    let done = "0"
    while done == "0" {
        if first == "0" { out = sbAppend(out, ",") }
        let combo = sbNew()
        let comboFirst = "1"
        let k = 0
        while k < rv {
            if comboFirst == "0" { combo = sbAppend(combo, ";") }
            combo = sbAppend(combo, split(xs, toInt(split(indices, k))))
            comboFirst = "0"
            k += 1
        }
        out = sbAppend(out, sbToString(combo))
        first = "0"
        // bump indices: rightmost that can grow
        let j = rv - 1
        let advanced = "0"
        while j >= 0 && advanced == "0" {
            let v = toInt(split(indices, j))
            if v + (rv - j) < n {
                indices = _listSetIt(indices, j, "" + (v + 1))
                let k2 = j + 1
                while k2 < rv {
                    indices = _listSetIt(indices, k2, "" + (toInt(split(indices, k2 - 1)) + 1))
                    k2 += 1
                }
                advanced = "1"
            }
            j -= 1
        }
        if advanced == "0" { done = "1" }
    }
    emit sbToString(out)
}

// permutations(xs, r) -- Heap's algorithm would be sleeker; for r ≤ n
// we use the lex-order swap iteration.  Result format same as
// combinations: inner ; sep, outer , sep.
func permutationsk(xs, r) {
    let n = count(xs)
    let rv = toInt(r)
    if rv > n || rv < 0 { emit "" }
    if rv == 0 { emit "" }
    let out = sbNew()
    let first = "1"
    // Build initial index array [0, 1, ..., n-1]
    let indices = ""
    let i = 0
    while i < n {
        if i > 0 { indices = indices + "," }
        indices = indices + i
        i += 1
    }
    let cycles = ""
    let c = n
    let j = 0
    while j < rv {
        if j > 0 { cycles = cycles + "," }
        cycles = cycles + c
        c -= 1
        j += 1
    }
    // Emit first permutation.
    let done = "0"
    while done == "0" {
        if first == "0" { out = sbAppend(out, ",") }
        let perm = sbNew()
        let pfirst = "1"
        let k = 0
        while k < rv {
            if pfirst == "0" { perm = sbAppend(perm, ";") }
            perm = sbAppend(perm, split(xs, toInt(split(indices, k))))
            pfirst = "0"
            k += 1
        }
        out = sbAppend(out, sbToString(perm))
        first = "0"
        // Advance: standard cycle-based permutation generation
        let advanced = "0"
        let idx = rv - 1
        while idx >= 0 && advanced == "0" {
            let cval = toInt(split(cycles, idx)) - 1
            if cval == 0 {
                let v = toInt(split(indices, idx))
                let m2 = idx + 1
                while m2 < n {
                    let prev = toInt(split(indices, m2))
                    indices = _listSetIt(indices, m2 - 1, "" + prev)
                    m2 += 1
                }
                indices = _listSetIt(indices, n - 1, "" + v)
                cycles = _listSetIt(cycles, idx, "" + (n - idx))
            } else {
                cycles = _listSetIt(cycles, idx, "" + cval)
                let swapIdx = n - cval
                let a = toInt(split(indices, idx))
                let b = toInt(split(indices, swapIdx))
                indices = _listSetIt(indices, idx, "" + b)
                indices = _listSetIt(indices, swapIdx, "" + a)
                advanced = "1"
            }
            idx -= 1
        }
        if advanced == "0" { done = "1" }
    }
    emit sbToString(out)
}

// product(a, b) -- cartesian product of two comma-lists.
// Inner pairs use `;` separator.
func productk(a, b) {
    let na = count(a)
    let nb = count(b)
    if na == 0 || nb == 0 { emit "" }
    let out = sbNew()
    let i = 0
    let first = "1"
    while i < na {
        let aa = split(a, i)
        let j = 0
        while j < nb {
            if first == "0" { out = sbAppend(out, ",") }
            out = sbAppend(out, aa)
            out = sbAppend(out, ";")
            out = sbAppend(out, split(b, j))
            first = "0"
            j += 1
        }
        i += 1
    }
    emit sbToString(out)
}

// groupby(xs) -- adjacent-equal grouping.  Returns "key:count" pairs.
func groupbyk(xs) {
    let n = count(xs)
    if n == 0 { emit "" }
    let out = sbNew()
    let prev = split(xs, 0)
    let c = 1
    let i = 1
    let first = "1"
    while i < n {
        let v = split(xs, i)
        if v == prev {
            c += 1
        } else {
            if first == "0" { out = sbAppend(out, ",") }
            out = sbAppend(out, prev)
            out = sbAppend(out, ":")
            out = sbAppend(out, "" + c)
            first = "0"
            prev = v
            c = 1
        }
        i += 1
    }
    if first == "0" { out = sbAppend(out, ",") }
    out = sbAppend(out, prev)
    out = sbAppend(out, ":")
    out = sbAppend(out, "" + c)
    emit sbToString(out)
}


// Helper: replace item at idx with val in a comma-list.  Local to this
// module so combinationsk / permutationsk can mutate index arrays
// without depending on list.k.
func _listSetIt(list, idx, val) {
    let n = count(list)
    let out = sbNew()
    let i = 0
    let first = "1"
    while i < n {
        let v = split(list, i)
        if i == idx { v = val }
        if first == "0" { out = sbAppend(out, ",") }
        out = sbAppend(out, v)
        first = "0"
        i += 1
    }
    emit sbToString(out)
}
