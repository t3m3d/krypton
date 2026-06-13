// stdlib/randomk.k -- Python `random` module surface.
//
// Sits beside the existing stdlib/random.k (Krypton-native LCG
// helpers); the FE lowers `import random` to `import "k:randomk"` so
// the user-side names match what Python users expect without colliding
// with the existing module.
//
// Names use the `*k` suffix convention.
//
// FE lowering:
//   random.random()              -> randomk()        (today: int 0..999; floats are A1)
//   random.randint(a, b)         -> randIntRangek(a, b)
//   random.randrange(stop)       -> randrangek("0", stop)
//   random.randrange(a, b)       -> randrangek(a, b)
//   random.choice(seq)           -> choicek(seq)
//   random.shuffle(xs)           -> shufflek(xs)     (returns shuffled; Python mutates)
//   random.sample(xs, k)         -> samplek(xs, k)
//   random.seed(s)               -> seedk(s)
//   random.uniform(a, b)         -> uniformk         (stub, A1)
//   random.gauss(mu, sigma)      -> gaussk           (stub, A1)

module randomk


// Internal LCG state.  Module-level mutable globals are buggy
// (feedback_module_mutable_globals); guiState is the documented
// workaround.
let _RND_STATE_KEY = "__randomk_state"


func _rndGet() {
    let s = guiStateGet(_RND_STATE_KEY)
    if s == "" {
        let initial = toInt(GetTickCount64())
        guiStateSet(_RND_STATE_KEY, toStr(initial))
        emit initial
    }
    emit toInt(s)
}

func _rndSet(v) {
    guiStateSet(_RND_STATE_KEY, toStr(v))
    emit ""
}

// LCG: x_{n+1} = (a*x + c) mod m  (Numerical Recipes constants)
func _rndNext() {
    let s = _rndGet()
    let next = (s * 1664525 + 1013904223) % 4294967296
    _rndSet(next)
    emit next
}


// random.seed(s)
func seedk(s) {
    _rndSet(toInt(s))
    emit ""
}

// random.randint(a, b) -- inclusive both ends.
func randIntRangek(a, b) {
    let lo = toInt(a)
    let hi = toInt(b)
    if lo > hi { emit lo }
    let span = hi - lo + 1
    let r = _rndNext()
    emit lo + (r % span)
}

// random.randrange(start, stop) -- half-open [start, stop).
func randrangek(start, stop) {
    let lo = toInt(start)
    let hi = toInt(stop)
    if lo >= hi { emit lo }
    let span = hi - lo
    let r = _rndNext()
    emit lo + (r % span)
}

// random.choice(seq)
func choicek(seq) {
    let n = count(seq)
    if n == 0 { emit "" }
    let r = _rndNext()
    emit split(seq, r % n)
}

// random.shuffle(xs) -- returns shuffled list (Python's shuffle
// mutates).  Fisher-Yates.
func shufflek(xs) {
    let n = count(xs)
    if n <= 1 { emit xs }
    let arr = xs
    let i = n - 1
    while i > 0 {
        let j = _rndNext() % (i + 1)
        let vi = split(arr, i)
        let vj = split(arr, j)
        arr = _shufSet(arr, i, vj)
        arr = _shufSet(arr, j, vi)
        i -= 1
    }
    emit arr
}

// random.sample(xs, k) -- k distinct elements via reservoir.
func samplek(xs, k) {
    let n = count(xs)
    let kk = toInt(k)
    if kk > n { kk = n }
    if kk == 0 { emit "" }
    let out = ""
    let i = 0
    while i < kk {
        if out == "" { out = split(xs, i) } else { out = out + "," + split(xs, i) }
        i += 1
    }
    while i < n {
        let j = _rndNext() % (i + 1)
        if j < kk {
            out = _shufSet(out, j, split(xs, i))
        }
        i += 1
    }
    emit out
}

// random.random() -- 0.0 <= x < 1.0.  Floats blocked on A1.  Today
// returns int 0..999 as the closest proxy; FE can multiply by 0.001
// once floats land to recover canonical semantics.
func randomk() {
    emit _rndNext() % 1000
}

func uniformk(a, b) {
    printErr("random.uniform: floating point not yet supported (roadmap A1).  Use random.randint for integer-range pick.")
    exit("1")
}

func gaussk(mu, sigma) {
    printErr("random.gauss: floating point not yet supported (roadmap A1)")
    exit("1")
}


// Helper: replace item at idx in a comma-list.
func _shufSet(list, idx, val) {
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
