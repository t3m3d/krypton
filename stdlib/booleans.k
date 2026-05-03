// Boolean utilities for Krypton.
//
// Krypton's value model is string-based — `true` is the string "true",
// `false` is "false". The runtime treats "", "0", and "false" as falsy;
// everything else is truthy. Comparison ops (==, !=, <, etc.) and
// builtins like hasField / isDigit return "1" or "0", not "true"/"false",
// for backward compatibility.
//
// This module bridges those two representations:
//   bool(v)        — coerce any value to "true" or "false"
//   kpBool(v)      — kp(bool(v))
//   boolToInt(v)   — coerce to "1" or "0"
//   boolEq(a, b)   — truthy-equality regardless of "1" vs "true" form
//   boolAnd/Or/Xor/Not — explicit boolean ops returning "true"/"false"

module booleans


// Coerce any value to the string "true" or "false".
//   bool(true)    -> "true"
//   bool(1)       -> "true"
//   bool("hi")    -> "true"
//   bool(0)       -> "false"
//   bool("0")     -> "false"
//   bool("false") -> "false"
//   bool("")      -> "false"
func bool(v) {
    if isTruthy(v) {
        emit "true"
    }
    emit "false"
}

// Convenience: print a value in true/false form.
func kpBool(v) {
    kp(bool(v))
}

// Coerce to the "1" / "0" form (matches what comparison ops return).
func boolToInt(v) {
    if isTruthy(v) {
        emit 1
    }
    emit 0
}

// Truthy-equality: returns true iff a and b have the same boolean value.
// Use this to compare a boolean variable against a literal regardless of
// which representation either side uses.
//   boolEq(true, 1)        -> true
//   boolEq(false, "0")     -> true
//   boolEq("true", true)   -> true
//   boolEq(true, "no")     -> true (any non-empty string is truthy)
func boolEq(a, b) {
    if isTruthy(a) {
        if isTruthy(b) { emit "true" }
        emit "false"
    }
    if isTruthy(b) { emit "false" }
    emit "true"
}

// Explicit boolean ops, returning "true" / "false" strings.
// Use these when you want the result to match the literal form.

func boolNot(v) {
    if isTruthy(v) { emit "false" }
    emit "true"
}

func boolAnd(a, b) {
    if isTruthy(a) {
        if isTruthy(b) { emit "true" }
    }
    emit "false"
}

func boolOr(a, b) {
    if isTruthy(a) { emit "true" }
    if isTruthy(b) { emit "true" }
    emit "false"
}

func boolXor(a, b) {
    if isTruthy(a) {
        if isTruthy(b) { emit "false" }
        emit "true"
    }
    if isTruthy(b) { emit "true" }
    emit "false"
}
