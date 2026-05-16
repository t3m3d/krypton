// Range generation utilities for Krypton

module range


// Generate a range of numbers as comma-separated list
// range(0, 5) => "0,1,2,3,4"
func rangeList(start, end) {
    let result = ""
    let i = start
    while i < end {
        if result == "" {
            result = "" + i
        } else {
            result = result + "," + i
        }
        i += 1
    }
    emit result
}

// Generate a range with step
// rangeStep(0, 10, 2) => "0,2,4,6,8"
func rangeStep(start, end, step) {
    let result = ""
    let i = start
    while i < end {
        if result == "" {
            result = "" + i
        } else {
            result = result + "," + i
        }
        i = i + step
    }
    emit result
}

// Generate a descending range
// rangeDown(5, 0) => "5,4,3,2,1"
func rangeDown(start, end) {
    let result = ""
    let i = start
    while i > end {
        if result == "" {
            result = "" + i
        } else {
            result = result + "," + i
        }
        i -= 1
    }
    emit result
}

// Generate a range of repeated values
// repeat(3, 5) => "3,3,3,3,3"
func repeatVal(val, n) {
    let result = ""
    let i = 0
    while i < n {
        if result == "" {
            result = "" + val
        } else {
            result = result + "," + val
        }
        i += 1
    }
    emit result
}

// Generate a list of squares: 1, 4, 9, 16, ...
func squares(n) {
    let result = ""
    let i = 1
    while i <= n {
        if result == "" {
            result = "" + (i * i)
        } else {
            result = result + "," + (i * i)
        }
        i += 1
    }
    emit result
}

// Generate first n powers of 2: 1, 2, 4, 8, ...
func powersOf2(n) {
    let result = ""
    let val = 1
    let i = 0
    while i < n {
        if result == "" {
            result = "" + val
        } else {
            result = result + "," + val
        }
        val = val * 2
        i += 1
    }
    emit result
}

// Generate first n triangular numbers: 1, 3, 6, 10, ...
func triangularNums(n) {
    let result = ""
    let sum = 0
    let i = 1
    while i <= n {
        sum += i
        if result == "" {
            result = "" + sum
        } else {
            result = result + "," + sum
        }
        i += 1
    }
    emit result
}
