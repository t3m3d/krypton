// Test: for-in loop over comma-separated lists

just run {
    // Basic iteration
    let out = ""
    for item in "a,b,c" {
        out = out + item
    }
    if out == "abc" { kp("PASS basic for-in") } else { kp("FAIL basic for-in: " + out) }

    // Nested for-in
    let result = ""
    for r in "1,2" {
        for c in "a,b" {
            result = result + r + c + " "
        }
    }
    if result == "1a 1b 2a 2b " { kp("PASS nested for-in") } else { kp("FAIL nested for-in: " + result) }

    // For-in with counter
    let count = 0
    for x in "p,q,r,s" {
        count += 1
    }
    if count == 4 { kp("PASS for-in count") } else { kp("FAIL for-in count: " + count) }

    // For-in with range
    let sum = 0
    for n in range(1, 6) {
        sum += toInt(n)
    }
    if sum == 15 { kp("PASS for-in range") } else { kp("FAIL for-in range: " + sum) }

    // Triple nesting
    let trips = 0
    for a in "1,2" {
        for b in "1,2" {
            for c in "1,2" {
                trips += 1
            }
        }
    }
    if trips == 8 { kp("PASS triple nested") } else { kp("FAIL triple nested: " + trips) }

    kp("for-in tests done")
}
