// stdlib/functools.k -- Python `functools` module surface.
//
// Most of functools depends on Tier-B features (classes for
// total_ordering, decorators for wraps / cache / lru_cache, variadic
// for partial).  The pieces that work today are shipped; the rest
// are clear-error stubs.
//
// FE lowering:
//   functools.reduce(f, xs, init)  -> reducek(f, xs, init)
//   functools.cmp_to_key(cmp)      -> cmpToKeyk(cmp)
//   functools.partial(f, a)        -> stub (blocked: A4 variadic)
//   functools.cache(f)             -> stub (blocked: decorators + state)

module functools

import "k:fp"


// reduce(f, xs, init) -- left fold over a comma-list.  Alias of fpReduce
// to give Python users the name they expect.
func reducek(f: closure, xs, init) {
    emit fpReduce(xs, init, f)
}

// cmp_to_key(cmp) -- given a comparator returning -1/0/1, return a
// key function suitable for sort.  Without lambdas-in-closures we
// can't quite return a closure here; we instead emit a callable that
// pairs the value with its comparator-result-with-itself, which gives
// the sort the right ordering.
//
// Practical caller pattern (until closures-of-closures land):
//   let cmp = func(a, b) { emit toInt(a) - toInt(b) }
//   let sortedXs = sortedk(xs)   // already a comparator-stable sort
//
// This stub is here so the FE lowering resolves; once closure
// returns are wired through the FE the body becomes real.
func cmpToKeyk(cmp: closure) {
    printErr("functools.cmp_to_key: blocked on closure-returning-closure (FE work).  Use sortedk for now.")
    emit ""
}

// partial(f, ...args) -- variadic, blocked on A4.
func partialk(f: closure, a) {
    printErr("functools.partial: blocked on A4 (variadic).  Wrap manually in a lambda for now.")
    emit ""
}

// cache(f) / lru_cache(f) -- need decorators + per-function state,
// both Tier B.  Return the original function so callers don't break.
func cachek(f: closure) {
    emit ptrToInt(f)
}

func lruCachek(f: closure) {
    emit ptrToInt(f)
}

// reduce-style higher-order helpers that are useful enough to expose:

// max_by(xs, key) -- argmax under the given key function.
func maxByk(xs, key: closure) {
    let n = count(xs)
    if n == 0 { emit "" }
    let best = split(xs, 0)
    let bestKey = key(best)
    let i = 1
    while i < n {
        let v = split(xs, i)
        let k = key(v)
        if toInt(k) > toInt(bestKey) {
            best = v
            bestKey = k
        }
        i += 1
    }
    emit best
}

// min_by(xs, key) -- argmin under the given key function.
func minByk(xs, key: closure) {
    let n = count(xs)
    if n == 0 { emit "" }
    let best = split(xs, 0)
    let bestKey = key(best)
    let i = 1
    while i < n {
        let v = split(xs, i)
        let k = key(v)
        if toInt(k) < toInt(bestKey) {
            best = v
            bestKey = k
        }
        i += 1
    }
    emit best
}
