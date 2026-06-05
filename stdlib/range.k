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

// rangeIncl(start, end) — inclusive of `end`, unlike rangeList which is
// half-open.  rangeIncl(1, 5) → "1,2,3,4,5"
func rangeIncl(start, end) {
    let result = ""
    let i = start
    while i <= end {
        if result == "" { result = "" + i }
        else            { result = result + "," + i }
        i += 1
    }
    emit result
}

// First n even non-negative numbers: 0, 2, 4, ...
func evens(n) {
    let result = ""
    let i = 0
    while i < n {
        let v = i * 2
        if result == "" { result = "" + v }
        else            { result = result + "," + v }
        i += 1
    }
    emit result
}

// First n odd positive numbers: 1, 3, 5, ...
func odds(n) {
    let result = ""
    let i = 0
    while i < n {
        let v = (i * 2) + 1
        if result == "" { result = "" + v }
        else            { result = result + "," + v }
        i += 1
    }
    emit result
}

// First n Fibonacci numbers starting with 0, 1.
func fibs(n) {
    if n <= 0 { emit "" }
    let result = "0"
    if n == 1 { emit result }
    let a = 0
    let b = 1
    let i = 1
    while i < n {
        result = result + "," + b
        let next = a + b
        a = b
        b = next
        i += 1
    }
    emit result
}

// First n primes by simple trial division.
func primes(n) {
    if n <= 0 { emit "" }
    let result = ""
    let candidate = 2
    let found = 0
    while found < n {
        let isPrime = 1
        let d = 2
        while d * d <= candidate {
            if candidate % d == 0 { isPrime = 0  d = candidate }
            d = d + 1
        }
        if isPrime == 1 {
            if result == "" { result = "" + candidate }
            else            { result = result + "," + candidate }
            found = found + 1
        }
        candidate = candidate + 1
    }
    emit result
}
