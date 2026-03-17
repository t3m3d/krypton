// Pair/tuple utilities for Krypton
// Pairs are encoded as "value,position" strings

module pair


// Create a new pair
func pairNew(val, pos) {
    emit "" + val + "," + pos
}

// Get value from pair
func pairFirst(p) {
    emit pairVal(p)
}

// Get position from pair
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
