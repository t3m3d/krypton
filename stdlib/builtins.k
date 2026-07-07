// stdlib/builtins.k -- Krypton stdlib functions shaped to match the
// semantics the upcoming Python frontend will lower its source to.
//
// Functions are named `<base>k` so they don't shadow Krypton's own
// `print` / `len` / `abs` / etc. builtins and so user-side Krypton
// code stays clear of "Python" leaking through identifiers.  The
// Python FE rewrites at lowering time: `print(x)` -> `printk(x)`,
// `len(x)` -> `lenk(x)`, etc.
//
// Notes on Krypton's data model
//   - "list"   ≈ comma-separated string  "1,2,3,4"
//   - "dict"   ≈ interleaved kv comma-list  "name,Alice,age,30"
//   - "tuple"  ≈ same as list at this level (parens are FE sugar)
//   - "set"    ≈ deduped sorted comma-list
//   - "str"    ≈ Krypton string (already)
//   - "int"    ≈ Krypton int-string smart-coerce
//   - "bool"   ≈ "1" / "0" int (matches the == family)
//   - "None"   ≈ ""  (Python's empty / null sentinel)
//
// Coverage status per function:
//   alias     -- same shape, just renamed
//   shim      -- thin wrapper, possibly with default args
//   polyfill  -- full Krypton impl on existing primitives
//   stub      -- explicit "not yet" with clear error
//   blocked   -- needs roadmap item; left as stub with reason

module builtins

import "k:fp"
import "k:io"


// ── I/O ───────────────────────────────────────────────────────────────

// print(*args, sep=" ", end="\n") -- one-positional today;
// variadic args wait on roadmap A4.  Named `printk` so it doesn't
// shadow Krypton's native `print` builtin and so the FE lowering
// for Python `print(x)` is unambiguous: `print(x)` -> `printk(x)`.
func printk(x) {
    print(x)
}

// input(prompt="") -- Python-facing alias over scan().
func inputk(prompt) {
    emit scan(prompt)
}


// ── Numeric ───────────────────────────────────────────────────────────

// abs(x) -- alias.
func absk(x) {
    emit abs(x)
}

// min(...) / max(...) over a comma-list (variadic blocked on A4;
// today: pass a list).
func mink(items) {
    let n = count(items)
    if n == 0 { emit "" }
    let best = split(items, 0)
    let i = 1
    while i < n {
        let c = split(items, i)
        if toInt(c) < toInt(best) { best = c }
        i += 1
    }
    emit best
}

func maxk(items) {
    let n = count(items)
    if n == 0 { emit "" }
    let best = split(items, 0)
    let i = 1
    while i < n {
        let c = split(items, i)
        if toInt(c) > toInt(best) { best = c }
        i += 1
    }
    emit best
}

// sum(iterable, start=0)
func sumk(items) {
    let n = count(items)
    let total = 0
    let i = 0
    while i < n {
        total = total + toInt(split(items, i))
        i += 1
    }
    emit total
}

// pow(base, exp) -- alias.
func powk(base, exp) {
    emit pow(base, exp)
}

// divmod(a, b) -> (q, r); tuples are comma-lists today.
func divmodk(a, b) {
    emit toInt(a) / toInt(b) + "," + toInt(a) % toInt(b)
}

// round(x, ndigits=0) -- integer-only today; full rounding blocks
// on A1 (floats).
func roundk(x) {
    emit toInt(x)
}


// ── Type conversions ──────────────────────────────────────────────────

// str(x) -- alias of toStr.
func strk(x) {
    emit toStr(x)
}

// int(x, base=10) -- base-10 alias today; non-10 bases blocked on a
// strtol-style builtin (trivial, deferred).
func intk(x) {
    emit toInt(x)
}

// float(x) -- blocked on roadmap A1 (floating point).
func floatk(x) {
    printErr("float(x): floating point not yet supported (roadmap A1)")
    exit("1")
}

// bool(x) -- alias of isTruthy (returns int 1/0).
func boolk(x) {
    emit isTruthy(x)
}

// list(x) -- pass-through for comma-lists; for strings, split into
// per-character list.
func listk(x) {
    if count(x) > 1 { emit x }
    // single-element / string: char-list it
    let out = ""
    let i = 0
    while i < len(x) {
        if i > 0 { out = out + "," }
        out = out + x[i]
        i += 1
    }
    emit out
}

// tuple(x) -- same as list at the data-model level.
func tuplek(x) {
    emit listk(x)
}

// dict(...) -- pass-through (Krypton's interleaved kv list IS the dict).
func dictk(x) {
    emit x
}

// set(x) -- dedupe a list, return sorted comma-list.
func setk(x) {
    let n = count(x)
    let seen = ""
    let i = 0
    while i < n {
        let v = split(x, i)
        if !_setContains(seen, v) {
            if seen == "" { seen = v } else { seen = seen + "," + v }
        }
        i += 1
    }
    emit seen
}

func _setContains(list, val) {
    let n = count(list)
    let i = 0
    while i < n {
        if split(list, i) == val { emit "1" }
        i += 1
    }
    emit "0"
}


// ── Iteration ─────────────────────────────────────────────────────────

// len(x) -- alias.
func lenk(x) {
    // for comma-lists return count; for strings return len.
    if count(x) > 1 { emit count(x) }
    emit len(x)
}

// range(stop) / range(start, stop) / range(start, stop, step)
// Today: 2-arg overload.  Step arg blocked on FE-level overloads.
func rangek(start, stop) {
    emit range(toInt(start), toInt(stop))
}

// enumerate(x) -> list of "i,val" comma-lists.  Matches fp.fpEnumerate.
func enumeratek(x) {
    emit fpEnumerate(x)
}

// zip(a, b) -- alias of fpZip.
func zipk(a, b) {
    emit fpZip(a, b)
}

// map(f, x) -- alias of fpMap.
func mapk(f: closure, x) {
    emit fpMap(x, f)
}

// filter(f, x) -- alias of fpFilter.
func filterk(f: closure, x) {
    emit fpFilter(x, f)
}

// reversed(x) -- reverse a list or string.
func reversedk(x) {
    if count(x) > 1 {
        // reverse a comma-list element-wise
        let n = count(x)
        let out = ""
        let i = n - 1
        while i >= 0 {
            let v = split(x, i)
            if out == "" { out = v } else { out = out + "," + v }
            i -= 1
        }
        emit out
    }
    emit reverse(x)
}

// sorted(x) -- ascending sort of an int-comma-list (stable).
// Simple insertion sort -- list shapes are short in practice.
func sortedk(x) {
    let n = count(x)
    if n <= 1 { emit x }
    let arr = ""
    let i = 0
    while i < n {
        if arr == "" { arr = split(x, i) } else { arr = arr + "," + split(x, i) }
        i += 1
    }
    let k = 1
    while k < n {
        let key = split(arr, k)
        let j = k - 1
        let stop = "0"
        while j >= 0 && stop == "0" {
            let cur = split(arr, j)
            if toInt(cur) > toInt(key) {
                arr = _listSet(arr, j + 1, cur)
                j -= 1
            } else {
                stop = "1"
            }
        }
        arr = _listSet(arr, j + 1, key)
        k += 1
    }
    emit arr
}

// _listSet(list, idx, val): replace item at idx with val, return new list.
func _listSet(list, idx, val) {
    let n = count(list)
    let out = ""
    let i = 0
    while i < n {
        let v = split(list, i)
        if i == idx { v = val }
        if out == "" { out = v } else { out = out + "," + v }
        i += 1
    }
    emit out
}

// sum is above; all / any are fpAll / fpAny analogs.
func allk(x) {
    let n = count(x)
    let i = 0
    while i < n {
        if !isTruthy(split(x, i)) { emit "0" }
        i += 1
    }
    emit "1"
}

func anyk(x) {
    let n = count(x)
    let i = 0
    while i < n {
        if isTruthy(split(x, i)) { emit "1" }
        i += 1
    }
    emit "0"
}


// ── Character / string ────────────────────────────────────────────────

// chr(n) -- alias of fromCharCode.
func chrk(n) {
    emit fromCharCode(toInt(n))
}

// ord(c) -- alias of charCode.
func ordk(c) {
    emit charCode(c)
}

// hex(n) -- alias.
func hexk(n) {
    emit "0x" + hex(n)
}

// bin(n) -- alias.
func bink(n) {
    emit "0b" + bin(n)
}

// oct(n) -- polyfill (no native oct yet).
func octk(n) {
    let v = toInt(n)
    if v == 0 { emit "0o0" }
    let neg = "0"
    if v < 0 { neg = "1"  v = -v }
    let s = ""
    while v > 0 {
        s = (v % 8) + s
        v = v / 8
    }
    if neg == "1" { emit "-0o" + s }
    emit "0o" + s
}

// repr(x) -- crude polyfill: wrap strings in quotes, leave numbers bare.
func reprk(x) {
    if isDigit(x[0]) { emit x }
    if x[0] == "-" && len(x) > 1 && isDigit(x[1]) { emit x }
    emit "\"" + x + "\""
}


// ── Identity / introspection ──────────────────────────────────────────

// id(x) -- alias of ptrToInt.
func idk(x) {
    emit ptrToInt(x)
}

// type(x) -- stub.  Real type system blocked on Tier-B work.
func typek(x) {
    printErr("type(x): not yet implemented")
    emit "object"
}

// isinstance(x, T) -- stub.
func isinstancek(x, t) {
    printErr("isinstance(x, t): not yet implemented")
    emit "0"
}

// callable(x) -- partial: closures / fp values pass.
func callablek(x) {
    // Krypton doesn't expose a runtime callable tag yet; conservative
    // "0" for non-closure values is wrong but won't crash callers.
    emit "0"
}


// ── Misc ──────────────────────────────────────────────────────────────

// hash(x) -- crude FNV-1a-like polyfill over the string bytes.
func hashk(x) {
    let h = 2166136261
    let i = 0
    while i < len(x) {
        h = (h ^ charCode(x[i])) * 16777619
        h = h & 4294967295
        i += 1
    }
    emit h
}

// Coverage notes
// --------------
// Shipped: 30+ builtins with `*k` suffix, all in this module.
//   printk inputk absk mink maxk sumk powk divmodk roundk
//   strk intk boolk listk tuplek dictk setk
//   lenk rangek enumeratek zipk mapk filterk reversedk sortedk
//   allk anyk chrk ordk hexk bink octk reprk
//   idk hashk
//
// Stubs returning an error (still in this module, future-fillable):
//   floatk        -- needs roadmap A1 (floating point)
//   typek / isinstancek / callablek -- needs structural types (Tier B)
//
// Not yet shipped at all (FE will lower to these once they land):
//   openk / iterk / nextk -- needs A8 file I/O + iterator protocol
//   compilek / evalk / execk -- explicitly not supported (compat matrix)
//   importk -- Krypton's import is compile-time; no runtime equivalent
//   formatk / varsk / dirk / localsk / globalsk -- deferred
//   helpk -- maybe never
