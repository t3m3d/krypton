// Assertion and testing helpers for Krypton

module assert


// Assert two values are equal
func assertEqual(actual, expected, msg) {
    if actual != expected {
        kp("FAIL: " + msg)
        kp("  expected: " + expected)
        kp("  actual:   " + actual)
        emit 0
    }
    kp("PASS: " + msg)
    emit 1
}

// Assert a value is truthy
func assertTrue(val, msg) {
    if val {
        kp("PASS: " + msg)
        emit 1
    }
    kp("FAIL: " + msg)
    kp("  expected truthy, got: " + val)
    emit 0
}

// Assert a value is falsy
func assertFalse(val, msg) {
    if val {
        kp("FAIL: " + msg)
        kp("  expected falsy, got: " + val)
        emit 0
    }
    kp("PASS: " + msg)
    emit 1
}

// Assert value is greater than expected
func assertGreater(actual, expected, msg) {
    if toInt(actual) > toInt(expected) {
        kp("PASS: " + msg)
        emit 1
    }
    kp("FAIL: " + msg)
    kp("  expected " + actual + " > " + expected)
    emit 0
}

// Assert value is less than expected
func assertLess(actual, expected, msg) {
    if toInt(actual) < toInt(expected) {
        kp("PASS: " + msg)
        emit 1
    }
    kp("FAIL: " + msg)
    kp("  expected " + actual + " < " + expected)
    emit 0
}

// Assert string starts with prefix
func assertStartsWith(s, prefix, msg) {
    if startsWith(s, prefix) {
        kp("PASS: " + msg)
        emit 1
    }
    kp("FAIL: " + msg)
    kp("  expected '" + s + "' to start with '" + prefix + "'")
    emit 0
}

// Assert string length equals expected
func assertLength(s, expected, msg) {
    if len(s) == expected {
        kp("PASS: " + msg)
        emit 1
    }
    kp("FAIL: " + msg)
    kp("  expected length " + expected + ", got " + len(s))
    emit 0
}

// Run a test suite and report results
func reportResults(passed, failed) {
    kp("")
    kp("========================")
    kp("Test Results")
    kp("========================")
    kp("Passed: " + passed)
    kp("Failed: " + failed)
    kp("Total:  " + (passed + failed))
    if failed == 0 {
        kp("ALL TESTS PASSED")
    } else {
        kp("SOME TESTS FAILED")
    }
    kp("========================")
}

// ── Inequality / containment / emptiness ─────────────────────────────

func assertNotEqual(actual, expected, msg) {
    if actual == expected {
        kp("FAIL: " + msg)
        kp("  expected NOT: " + expected)
        kp("  got:          " + actual)
        emit 0
    }
    kp("PASS: " + msg)
    emit 1
}

func assertContains(s, sub, msg) {
    if indexOf(s, sub) < 0 {
        kp("FAIL: " + msg)
        kp("  haystack: " + s)
        kp("  needle:   " + sub)
        emit 0
    }
    kp("PASS: " + msg)
    emit 1
}

func assertEndsWith(s, suffix, msg) {
    if endsWith(s, suffix) == "0" {
        kp("FAIL: " + msg)
        kp("  string:   " + s)
        kp("  expected suffix: " + suffix)
        emit 0
    }
    kp("PASS: " + msg)
    emit 1
}

func assertEmpty(s, msg) {
    if len(s) != 0 {
        kp("FAIL: " + msg)
        kp("  expected empty, got: " + s)
        emit 0
    }
    kp("PASS: " + msg)
    emit 1
}

func assertNotEmpty(s, msg) {
    if len(s) == 0 {
        kp("FAIL: " + msg)
        kp("  expected non-empty")
        emit 0
    }
    kp("PASS: " + msg)
    emit 1
}

// ── Numeric ranges ───────────────────────────────────────────────────

func assertInRange(n, lo, hi, msg) {
    let v = toInt(n)
    if v < lo || v > hi {
        kp("FAIL: " + msg)
        kp("  value: " + n)
        kp("  range: [" + lo + ", " + hi + "]")
        emit 0
    }
    kp("PASS: " + msg)
    emit 1
}

func assertGreaterEqual(actual, expected, msg) {
    if toInt(actual) < toInt(expected) {
        kp("FAIL: " + msg)
        kp("  actual:   " + actual)
        kp("  expected >= " + expected)
        emit 0
    }
    kp("PASS: " + msg)
    emit 1
}

func assertLessEqual(actual, expected, msg) {
    if toInt(actual) > toInt(expected) {
        kp("FAIL: " + msg)
        kp("  actual:   " + actual)
        kp("  expected <= " + expected)
        emit 0
    }
    kp("PASS: " + msg)
    emit 1
}
