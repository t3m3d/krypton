// float_utils.k — floating-point arithmetic for Krypton
// Floats are stored as strings: "3.14", "2.0", "-0.5"
// Use fadd/fsub/fmul/fdiv for arithmetic, fformat for display

module float_utils

// Parse a float string (identity - already a string)
func toFloat(s) {
    emit s + ""
}

// Add two floats
func floatAdd(a, b) {
    emit fadd(a, b)
}

// Subtract two floats
func floatSub(a, b) {
    emit fsub(a, b)
}

// Multiply two floats
func floatMul(a, b) {
    emit fmul(a, b)
}

// Divide two floats
func floatDiv(a, b) {
    emit fdiv(a, b)
}

// Square root of a float
func floatSqrt(a) {
    emit fsqrt(a)
}

// Floor of a float
func floatFloor(a) {
    emit ffloor(a)
}

// Ceiling of a float
func floatCeil(a) {
    emit fceil(a)
}

// Round a float
func floatRound(a) {
    emit fround(a)
}

// Format float with N decimal places: fformat("3.14159", "2") -> "3.14"
func floatFormat(a, decimals) {
    emit fformat(a, decimals)
}

// Check if a < b (float comparison)
func floatLt(a, b) {
    emit flt(a, b)
}

// Check if a > b
func floatGt(a, b) {
    emit fgt(a, b)
}

// Check if a == b
func floatEq(a, b) {
    emit feq(a, b)
}

// PI constant
func pi() {
    emit "3.14159265358979"
}

// Absolute value of a float
func floatAbs(a) {
    if flt(a, "0") {
        emit fsub("0", a)
    }
    emit a
}
