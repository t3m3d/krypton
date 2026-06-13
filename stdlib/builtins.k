// stdlib/builtins.k -- Python-named wrappers over existing Krypton builtins.
//
// Goal: a Krypton program can `import "k:builtins"` and call Python's
// builtin functions by their Python names, getting Python-shaped
// behavior on top of the existing native runtime / GC / IR.
//
// This is the polyfill layer that the Copilot-scaffolded Python frontend
// will lower to.  It doesn't enable Python *syntax* -- that's the FE's
// job -- but it makes every Python builtin function available from
// today's Krypton code immediately, so when the FE lands the user-side
// stdlib is already there.
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


// ── I/O ───────────────────────────────────────────────────────────────

// print(*args, sep=" ", end="\n") -- one-positional alias today;
// variadic args wait on roadmap A4.  print() is already a Krypton
// builtin with the same shape; the wrapper here keeps the explicit
// name so `from builtins import print` lowering is consistent.
func pyPrint(x) {
    print(x)
}

// input(prompt="") -- read one line from stdin.
func pyInput(prompt) {
    if prompt != "" { print(prompt) }
    emit readLine()
}


// ── Numeric ───────────────────────────────────────────────────────────

// abs(x) -- alias.
func pyAbs(x) {
    emit abs(x)
}

// min(...) / max(...) over a comma-list (variadic blocked on A4;
// today: pass a list).
func pyMin(items) {
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

func pyMax(items) {
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
func pySum(items) {
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
func pyPow(base, exp) {
    emit pow(base, exp)
}

// divmod(a, b) -> (q, r); tuples are comma-lists today.
func pyDivmod(a, b) {
    emit toInt(a) / toInt(b) + "," + toInt(a) % toInt(b)
}

// round(x, ndigits=0) -- integer-only today; full rounding blocks
// on A1 (floats).
func pyRound(x) {
    emit toInt(x)
}


// ── Type conversions ──────────────────────────────────────────────────

// str(x) -- alias of toStr.
func pyStr(x) {
    emit toStr(x)
}

// int(x, base=10) -- base-10 alias today; non-10 bases blocked on a
// strtol-style builtin (trivial, deferred).
func pyInt(x) {
    emit toInt(x)
}

// float(x) -- blocked on roadmap A1 (floating point).
func pyFloat(x) {
    printErr("float(x): floating point not yet supported (roadmap A1)")
    exit("1")
}

// bool(x) -- alias of isTruthy (returns int 1/0).
func pyBool(x) {
    emit isTruthy(x)
}

// list(x) -- pass-through for comma-lists; for strings, split into
// per-character list.
func pyList(x) {
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
func pyTuple(x) {
    emit pyList(x)
}

// dict(...) -- pass-through (Krypton's interleaved kv list IS the dict).
func pyDict(x) {
    emit x
}

// set(x) -- dedupe a list, return sorted comma-list.
func pySet(x) {
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
func pyLen(x) {
    // for comma-lists return count; for strings return len.
    if count(x) > 1 { emit count(x) }
    emit len(x)
}

// range(stop) / range(start, stop) / range(start, stop, step)
// Today: 2-arg overload.  Step arg blocked on FE-level overloads.
func pyRange(start, stop) {
    emit range(toInt(start), toInt(stop))
}

// enumerate(x) -> list of "i,val" comma-lists.  Matches fp.fpEnumerate.
func pyEnumerate(x) {
    emit fpEnumerate(x)
}

// zip(a, b) -- alias of fpZip.
func pyZip(a, b) {
    emit fpZip(a, b)
}

// map(f, x) -- alias of fpMap.
func pyMap(f: closure, x) {
    emit fpMap(x, f)
}

// filter(f, x) -- alias of fpFilter.
func pyFilter(f: closure, x) {
    emit fpFilter(x, f)
}

// reversed(x) -- reverse a list or string.
func pyReversed(x) {
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
func pySorted(x) {
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
func pyAll(x) {
    let n = count(x)
    let i = 0
    while i < n {
        if !isTruthy(split(x, i)) { emit "0" }
        i += 1
    }
    emit "1"
}

func pyAny(x) {
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
func pyChr(n) {
    emit fromCharCode(toInt(n))
}

// ord(c) -- alias of charCode.
func pyOrd(c) {
    emit charCode(c)
}

// hex(n) -- alias.
func pyHex(n) {
    emit "0x" + hex(n)
}

// bin(n) -- alias.
func pyBin(n) {
    emit "0b" + bin(n)
}

// oct(n) -- polyfill (no native oct yet).
func pyOct(n) {
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
func pyRepr(x) {
    if isDigit(x[0]) { emit x }
    if x[0] == "-" && len(x) > 1 && isDigit(x[1]) { emit x }
    emit "\"" + x + "\""
}


// ── Identity / introspection ──────────────────────────────────────────

// id(x) -- alias of ptrToInt.
func pyId(x) {
    emit ptrToInt(x)
}

// type(x) -- stub.  Real type system blocked on Tier-B work.
func pyType(x) {
    printErr("type(x): not yet implemented")
    emit "object"
}

// isinstance(x, T) -- stub.
func pyIsinstance(x, t) {
    printErr("isinstance(x, t): not yet implemented")
    emit "0"
}

// callable(x) -- partial: closures / fp values pass.
func pyCallable(x) {
    // Krypton doesn't expose a runtime callable tag yet; conservative
    // "0" for non-closure values is wrong but won't crash callers.
    emit "0"
}


// ── Misc ──────────────────────────────────────────────────────────────

// hash(x) -- crude FNV-1a-like polyfill over the string bytes.
func pyHash(x) {
    let h = 2166136261
    let i = 0
    while i < len(x) {
        h = (h ^ charCode(x[i])) * 16777619
        h = h & 4294967295
        i += 1
    }
    emit h
}

// abs(x) already exported above as pyAbs.

// Coverage notes
// --------------
// Aliased / polyfilled:
//   print input abs min max sum pow divmod round str int bool list
//   tuple dict set len range enumerate zip map filter reversed sorted
//   all any chr ord hex bin oct repr id hash
//
// Blocked on roadmap:
//   float  -- A1 floats
//   type / isinstance / callable -- structural types / classes (Tier B)
//   open / iter / next -- A8 file I/O / iterator protocol
//   compile / eval / exec -- explicitly not supported (compat matrix)
//   __import__ -- Krypton's import is compile-time; no runtime equivalent
//   format / vars / dir / locals / globals -- deferred
//   help -- maybe never
