// stdlib/dict.k -- Krypton dict functions shaped to match the
// semantics the upcoming Python frontend will lower method-call
// syntax to.  Dicts are interleaved kv comma-lists:
//
//   "name,Alice,age,30,city,NYC"
//
// That dict has 3 entries (count(d)/2 = 3).  Even indices (0, 2, 4)
// are keys; odd indices (1, 3, 5) are values.  Krypton's existing
// `hasfield(d, key)` and the `getField` / `setField` builtins
// already cover the low-level dict ABI; this module wraps them in
// Python-shaped surfaces.
//
// Names use the `*k` suffix convention (matches builtins.k +
// string.k + list.k) so they don't shadow Krypton's own
// builtins.  FE lowering examples:
//
//   d.keys()             -> dictkeysk(d)
//   d.values()           -> dictvaluesk(d)
//   d.items()            -> dictitemsk(d)
//   d.get(k, default)    -> dictgetk(d, k, default)
//   d[k]                 -> dictgetk(d, k, "")
//   d[k] = v             -> dictsetk(d, k, v)
//   del d[k]             -> dictdelk(d, k)
//   k in d               -> indictk(k, d)

module dict


// ── Construction ──────────────────────────────────────────────────────

func emptydictk() {
    emit ""
}

// dictfromkeysk(keys, value) -- build a dict from a key list, all
// values set to `value`.  Python: dict.fromkeys(keys, value).
func dictfromkeysk(keys, value) {
    let n = count(keys)
    if n == 0 { emit "" }
    let out = sbNew()
    let i = 0
    while i < n {
        if i > 0 { out = sbAppend(out, ",") }
        out = sbAppend(out, split(keys, i))
        out = sbAppend(out, ",")
        out = sbAppend(out, value)
        i += 1
    }
    emit sbToString(out)
}


// ── Read ──────────────────────────────────────────────────────────────

// dictlenk(d) -- number of key/value PAIRS.  count(d) gives total
// fields; dict entries are half that.
func dictlenk(d) {
    emit count(d) / 2
}

// dictkeysk(d) -- return the keys as a comma-list.
func dictkeysk(d) {
    let n = count(d)
    if n == 0 { emit "" }
    let out = sbNew()
    let i = 0
    let first = "1"
    while i < n {
        if first == "0" { out = sbAppend(out, ",") }
        out = sbAppend(out, split(d, i))
        first = "0"
        i = i + 2
    }
    emit sbToString(out)
}

// dictvaluesk(d) -- return the values as a comma-list.
func dictvaluesk(d) {
    let n = count(d)
    if n == 0 { emit "" }
    let out = sbNew()
    let i = 1
    let first = "1"
    while i < n {
        if first == "0" { out = sbAppend(out, ",") }
        out = sbAppend(out, split(d, i))
        first = "0"
        i = i + 2
    }
    emit sbToString(out)
}

// dictitemsk(d) -- return as interleaved key,value list.  Already
// the storage shape; pass-through.  Distinct from the dict itself
// only conceptually (this signals "iterate as items").
func dictitemsk(d) {
    emit d
}

// dictgetk(d, key, default) -- value associated with key, or default
// if key is absent.
func dictgetk(d, key, default) {
    let n = count(d)
    let i = 0
    while i < n {
        if split(d, i) == key { emit split(d, i + 1) }
        i = i + 2
    }
    emit default
}

// indictk(key, d) -- Python `key in d` membership.  Returns int 1/0.
func indictk(key, d) {
    let n = count(d)
    let i = 0
    while i < n {
        if split(d, i) == key { emit 1 }
        i = i + 2
    }
    emit 0
}


// ── Write ─────────────────────────────────────────────────────────────

// dictsetk(d, key, value) -- set or replace.  Returns new dict.
func dictsetk(d, key, value) {
    let n = count(d)
    let out = sbNew()
    let i = 0
    let first = "1"
    let replaced = "0"
    while i < n {
        let k = split(d, i)
        let v = split(d, i + 1)
        if first == "0" { out = sbAppend(out, ",") }
        if k == key {
            out = sbAppend(out, k)
            out = sbAppend(out, ",")
            out = sbAppend(out, value)
            replaced = "1"
        } else {
            out = sbAppend(out, k)
            out = sbAppend(out, ",")
            out = sbAppend(out, v)
        }
        first = "0"
        i = i + 2
    }
    if replaced == "0" {
        if first == "0" { out = sbAppend(out, ",") }
        out = sbAppend(out, key)
        out = sbAppend(out, ",")
        out = sbAppend(out, value)
    }
    emit sbToString(out)
}

// dictdelk(d, key) -- remove `key` if present; return new dict.
func dictdelk(d, key) {
    let n = count(d)
    let out = sbNew()
    let i = 0
    let first = "1"
    while i < n {
        let k = split(d, i)
        let v = split(d, i + 1)
        if k != key {
            if first == "0" { out = sbAppend(out, ",") }
            out = sbAppend(out, k)
            out = sbAppend(out, ",")
            out = sbAppend(out, v)
            first = "0"
        }
        i = i + 2
    }
    emit sbToString(out)
}

// dictsetdefaultk(d, key, default) -- if key present, return its
// value; else set to default and return default.  FE emits this as
// a pair: `v = dictsetdefaultk(d, k, def); d = dictsetdefaultupd(d, k, def)`.
// Returns ONLY the value; companion `dictsetdefaultupd` updates the
// dict.  Matches Python semantics where setdefault mutates AND returns.
func dictsetdefaultk(d, key, default) {
    emit dictgetk(d, key, default)
}

func dictsetdefaultupd(d, key, default) {
    if indictk(key, d) == 1 { emit d }
    emit dictsetk(d, key, default)
}

// dictupdatek(d, other) -- merge `other` into `d`; values in `other`
// win on key collision.  Returns new dict.
func dictupdatek(d, other) {
    let result = d
    let n = count(other)
    let i = 0
    while i < n {
        result = dictsetk(result, split(other, i), split(other, i + 1))
        i = i + 2
    }
    emit result
}

// dictpopk(d, key, default) -- return value if present, else default.
// Companion: dictdelk(d, key) updates the dict.  See popk in list.k
// for the same FE-paired-statements pattern.
func dictpopk(d, key, default) {
    emit dictgetk(d, key, default)
}

// dictpopitemk(d) -- return the LAST key,value pair as a 2-element
// list "k,v".  Empty dict returns "".  Companion: dictpopitemupd
// returns the dict without that entry.
func dictpopitemk(d) {
    let n = count(d)
    if n == 0 { emit "" }
    let lastK = split(d, n - 2)
    let lastV = split(d, n - 1)
    emit lastK + "," + lastV
}

func dictpopitemupd(d) {
    let n = count(d)
    if n == 0 { emit "" }
    let out = sbNew()
    let i = 0
    while i < n - 2 {
        if i > 0 { out = sbAppend(out, ",") }
        out = sbAppend(out, split(d, i))
        i += 1
    }
    emit sbToString(out)
}

// dictclearedk(d) -- empty dict.
func dictclearedk(d) {
    emit ""
}

// dictcopyk(d) -- Krypton strings are immutable; copy is identity.
func dictcopyk(d) {
    emit d
}

// Coverage notes
// --------------
// Shipped (16 funcs):
//   emptydictk dictfromkeysk dictlenk
//   dictkeysk dictvaluesk dictitemsk dictgetk indictk
//   dictsetk dictdelk
//   dictsetdefaultk dictsetdefaultupd
//   dictupdatek
//   dictpopk dictpopitemk dictpopitemupd
//   dictclearedk dictcopyk
//
// FE relies on these names for these lowerings:
//   d.keys()             -> dictkeysk(d)
//   d.values()           -> dictvaluesk(d)
//   d.items()            -> dictitemsk(d)
//   d.get(k, default)    -> dictgetk(d, k, default)
//   d.get(k)             -> dictgetk(d, k, "")
//   d[k]                 -> dictgetk(d, k, "")
//   d[k] = v             -> dictsetk(d, k, v)
//   del d[k]             -> dictdelk(d, k)
//   d.setdefault(k, def) -> dictsetdefaultk(d, k, def) +
//                           dictsetdefaultupd companion
//   d.update(other)      -> dictupdatek(d, other)
//   d.pop(k, default)    -> dictpopk(d, k, default) + dictdelk companion
//   d.popitem()          -> dictpopitemk(d) + dictpopitemupd companion
//   d.clear()            -> dictclearedk(d)
//   d.copy()             -> dictcopyk(d)
//   k in d               -> indictk(k, d)
//   len(d)               -> dictlenk(d)        (overrides lenk for dicts)
//   dict.fromkeys(ks, v) -> dictfromkeysk(ks, v)
//
// Not yet covered (deferred):
//   dict comprehensions  -- FE-level, not stdlib
//   class-level dict     -- needs structural types (Tier B)
//   d | other            -- merge operator (3.9+); maps to dictupdatek
//   d |= other           -- in-place; same lowering as | for our shape
