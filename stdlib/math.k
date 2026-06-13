// stdlib/math.k -- Python `math` module surface.
//
// Most of math.* needs floats (roadmap A1).  This module ships the
// integer-only members today + clear-error stubs for everything that
// blocks on A1.  When floats land, swap the stubs for real impls.
//
// FE lowering:
//   math.pi              -> mathpik()
//   math.e               -> mathek()
//   math.sqrt(x)         -> mathsqrtk(x)        (blocked: A1)
//   math.sin(x)          -> mathsink(x)         (blocked: A1)
//   math.floor(x)        -> mathfloork(x)
//   math.ceil(x)         -> mathceilk(x)
//   math.factorial(n)    -> mathfactorialk(n)
//   math.gcd(a, b)       -> mathgcdk(a, b)
//   math.lcm(a, b)       -> mathlcmk(a, b)

module math


// ── Constants ─────────────────────────────────────────────────────────
// Today these return their best Krypton-integer-string approximation
// since floats aren't there yet.  When A1 lands, they become real f64
// constants 3.14159265358979 / 2.71828182845905 / etc.

func mathpik() {
    // 3.14159... rounded to integer-string is "3".  Documented gotcha.
    emit "3"
}

func mathek() {
    emit "2"
}

func mathinfk() {
    emit sysmaxsizek_fallback()
}

func mathnank() {
    emit "0"  // Krypton has no NaN today; substitute zero with warning.
}

func mathtauk() {
    emit "6"  // 2π rounded
}


// ── Integer-only ──────────────────────────────────────────────────────

func mathfactorialk(n) {
    let v = toInt(n)
    if v < 0 {
        printErr("math.factorial: negative")
        exit("1")
    }
    let acc = 1
    let i = 2
    while i <= v {
        acc = acc * i
        i += 1
    }
    emit acc
}

func mathgcdk(a, b) {
    let x = toInt(a)
    let y = toInt(b)
    if x < 0 { x = -x }
    if y < 0 { y = -y }
    while y != 0 {
        let t = y
        y = x % y
        x = t
    }
    emit x
}

func mathlcmk(a, b) {
    let ai = toInt(a)
    let bi = toInt(b)
    if ai == 0 || bi == 0 { emit 0 }
    let g = toInt(mathgcdk(a, b))
    emit (ai / g) * bi
}

// math.floor(x) / math.ceil(x) on integer-strings = identity.
// Once floats land, these need to actually trunc/round.
func mathfloork(x) {
    emit toInt(x)
}

func mathceilk(x) {
    emit toInt(x)
}

func mathtrunck(x) {
    emit toInt(x)
}

func mathabsk(x) {
    emit abs(x)
}

func mathpowik(base, exp) {
    // Integer power (positive exp).  Real math.pow needs FP.
    let b = toInt(base)
    let e = toInt(exp)
    if e < 0 {
        printErr("math.pow: negative exponent needs floats (A1)")
        exit("1")
    }
    let acc = 1
    let i = 0
    while i < e {
        acc = acc * b
        i += 1
    }
    emit acc
}

// math.isqrt(n) -- integer square root via Newton.
func mathisqrtk(n) {
    let v = toInt(n)
    if v < 0 {
        printErr("math.isqrt: negative")
        exit("1")
    }
    if v < 2 { emit v }
    let x = v
    let y = (x + 1) / 2
    while y < x {
        x = y
        y = (x + v / x) / 2
    }
    emit x
}


// ── Float-only (stubs that error clearly) ─────────────────────────────

func mathsqrtk(x) {
    printErr("math.sqrt(x): floating point not yet supported (roadmap A1).  Use math.isqrt(n) for integer square root.")
    exit("1")
}

func mathsink(x) {
    printErr("math.sin(x): floating point not yet supported (roadmap A1)")
    exit("1")
}

func mathcosk(x) {
    printErr("math.cos(x): floating point not yet supported (roadmap A1)")
    exit("1")
}

func mathtank(x) {
    printErr("math.tan(x): floating point not yet supported (roadmap A1)")
    exit("1")
}

func mathasink(x) {
    printErr("math.asin(x): floating point not yet supported (roadmap A1)")
    exit("1")
}

func mathacosk(x) {
    printErr("math.acos(x): floating point not yet supported (roadmap A1)")
    exit("1")
}

func mathatank(x) {
    printErr("math.atan(x): floating point not yet supported (roadmap A1)")
    exit("1")
}

func mathatan2k(y, x) {
    printErr("math.atan2(y, x): floating point not yet supported (roadmap A1)")
    exit("1")
}

func mathlogk(x) {
    printErr("math.log(x): floating point not yet supported (roadmap A1)")
    exit("1")
}

func mathlog2k(x) {
    printErr("math.log2(x): floating point not yet supported (roadmap A1)")
    exit("1")
}

func mathlog10k(x) {
    printErr("math.log10(x): floating point not yet supported (roadmap A1)")
    exit("1")
}

func mathexpk(x) {
    printErr("math.exp(x): floating point not yet supported (roadmap A1)")
    exit("1")
}

func mathpowk(base, exp) {
    printErr("math.pow(base, exp): real floats need A1.  Use math.powi(b, e) for integer power.")
    exit("1")
}


// helper: sysmaxsize fallback (the sys module isn't imported into this
// file to avoid the cyclic-import gotcha during early FE bring-up).
func sysmaxsizek_fallback() {
    emit 2147483647
}
