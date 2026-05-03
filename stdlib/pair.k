// Pair/tuple utilities for Krypton
// Pairs are encoded as "value,position" strings.
//
// Used pervasively by the compiler to return (result, advance-cursor) pairs
// from parser helpers; exported here for user code that wants the same idiom.

module pair


func _pair_findLastComma(s) {
    let i = len(s) - 1
    while i >= 0 {
        if s[i] == "," { emit i }
        i = i - 1
    }
    emit -1
}

// Get value from pair (everything before the last comma)
func pairVal(p) {
    let c = _pair_findLastComma(p)
    if c < 0 { emit p }
    emit substring(p, 0, c)
}

// Get position from pair (integer after the last comma)
func pairPos(p) {
    let c = _pair_findLastComma(p)
    emit toInt(substring(p, c + 1, len(p)))
}

// Create a new pair
func pairNew(val, pos) {
    emit "" + val + "," + pos
}

// Get value from pair (alias for pairVal)
func pairFirst(p) {
    emit pairVal(p)
}

// Get position from pair (alias for pairPos)
func pairSecond(p) {
    emit pairPos(p)
}

// Create a triple (three values)
func tripleNew(a, b, c) {
    emit "" + a + "," + b + "," + c
}

// Get first of triple
func tripleFirst(t) {
    emit split(t, 0)
}

// Get second of triple
func tripleSecond(t) {
    emit split(t, 1)
}

// Get third of triple
func tripleThird(t) {
    emit split(t, 2)
}

// Map a pair's value (apply function conceptually)
func pairMapVal(p, newVal) {
    emit "" + newVal + "," + pairPos(p)
}

// Map a pair's position
func pairMapPos(p, newPos) {
    emit pairVal(p) + "," + newPos
}

// Swap pair elements
func pairSwap(p) {
    emit "" + pairPos(p) + "," + pairVal(p)
}

// Convert pair to display string
func pairToString(p) {
    emit "(" + pairVal(p) + ", " + pairPos(p) + ")"
}

// Check if two pairs are equal
func pairEqual(a, b) {
    if pairVal(a) == pairVal(b) {
        if pairPos(a) == pairPos(b) {
            emit 1
        }
    }
    emit 0
}
