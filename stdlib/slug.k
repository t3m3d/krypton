// stdlib/slug.k — URL/filename slug helpers in PURE KRYPTON. No C.
//
//   slugify("Hello, World!  v2")  -> "hello-world-v2"
//   slugify("  Krypton Lang  ")   -> "krypton-lang"
//   kebab / snake / screaming variants too.
//
// Keeps [a-z0-9], lowercases, collapses every run of other chars to one
// separator, trims leading/trailing separators. ASCII only (non-ASCII bytes
// are treated as separators).

module slug

// toLower/toUpper builtins are no-ops on the native backend, so do ASCII
// case conversion by hand.
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
func _uc(s) {
    let out = ""
    let i = 0
    while i < len(s) {
        let v = toInt(charCode(s[i]))
        if v >= 97 && v <= 122 { out = out + fromCharCode(v - 32) }
        else { out = out + s[i] }
        i += 1
    }
    emit out
}

func _isLowerAlnum(c) {
    let v = toInt(charCode(c))
    if v >= 48 && v <= 57 { emit 1 }   // 0-9
    if v >= 97 && v <= 122 { emit 1 }  // a-z
    emit 0
}

// generic slugger: lowercases, keeps alnum, joins runs of junk with `sep`.
func _slug(s, sep) {
    let low = _lc(s)
    let out = ""
    let i = 0
    let n = len(low)
    let pendingSep = 0
    while i < n {
        let c = low[i]
        if _isLowerAlnum(c) == 1 {
            if pendingSep == 1 {
                if len(out) > 0 { out = out + sep }
                pendingSep = 0
            }
            out = out + c
        } else {
            pendingSep = 1
        }
        i += 1
    }
    emit out
}

// slugify(s): lowercase, hyphen-separated ("Hello World" -> "hello-world").
func slugify(s) { emit _slug(s, "-") }

// kebab(s): alias for slugify (hyphen-separated lowercase).
func kebab(s) { emit _slug(s, "-") }

// snake(s): lowercase, underscore-separated ("Hello World" -> "hello_world").
func snake(s) { emit _slug(s, "_") }

// screamingSnake(s): "HELLO_WORLD".
func screamingSnake(s) { emit _uc(_slug(s, "_")) }

// dotted(s): "hello.world".
func dotted(s) { emit _slug(s, ".") }
