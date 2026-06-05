// Testing framework for Krypton
// Provides structured test execution

module test_framework


// Run a single test case
func runTest(name, expected, actual) {
    if expected == actual {
        kp("[PASS] " + name)
        emit 1
    } else {
        kp("[FAIL] " + name)
        kp("       Expected: " + expected)
        kp("       Actual:   " + actual)
        emit 0
    }
}

// Print test suite header
func suiteHeader(suiteName) {
    kp("")
    kp("================================")
    kp("  Test Suite: " + suiteName)
    kp("================================")
}

// Print test suite footer with summary
func suiteFooter(suiteName, passed, total) {
    kp("--------------------------------")
    kp("  " + suiteName + ": " + passed + "/" + total + " passed")
    if passed == total {
        kp("  Status: ALL PASSED")
    } else {
        kp("  Status: FAILURES DETECTED")
    }
    kp("================================")
    kp("")
}

// Print a test separator
func separator() {
    kp("--------------------------------")
}

// Assert not equal
func assertNotEqual(name, a, b) {
    if a != b {
        kp("[PASS] " + name)
        emit 1
    } else {
        kp("[FAIL] " + name)
        kp("       Values should differ: " + a)
        emit 0
    }
}

// Assert numeric range
func assertInRange(name, val, lo, hi) {
    let v = toInt(val)
    if v >= lo {
        if v <= hi {
            kp("[PASS] " + name)
            emit 1
        }
    }
    kp("[FAIL] " + name)
    kp("       " + val + " not in range [" + lo + ", " + hi + "]")
    emit 0
}

// Print final report across all suites
func finalReport(totalPassed, totalFailed) {
    kp("")
    kp("########################################")
    kp("#         FINAL TEST REPORT            #")
    kp("########################################")
    kp("# Total Passed: " + totalPassed)
    kp("# Total Failed: " + totalFailed)
    kp("# Grand Total:  " + (totalPassed + totalFailed))
    if totalFailed == 0 {
        kp("# Result: SUCCESS")
    } else {
        kp("# Result: FAILURE")
    }
    kp("########################################")
}

// ── More assertion helpers ───────────────────────────────────────────

func assertContains(name, haystack, needle) {
    if indexOf(haystack, needle) >= 0 {
        kp("[PASS] " + name)
        emit 1
    }
    kp("[FAIL] " + name)
    kp("       haystack: " + haystack)
    kp("       needle:   " + needle)
    emit 0
}

func assertGreater(name, a, b) {
    if toInt(a) > toInt(b) {
        kp("[PASS] " + name)
        emit 1
    }
    kp("[FAIL] " + name)
    kp("       " + a + " not > " + b)
    emit 0
}

func assertLess(name, a, b) {
    if toInt(a) < toInt(b) {
        kp("[PASS] " + name)
        emit 1
    }
    kp("[FAIL] " + name)
    kp("       " + a + " not < " + b)
    emit 0
}

func assertTruthy(name, val) {
    if isTruthy(val) {
        kp("[PASS] " + name)
        emit 1
    }
    kp("[FAIL] " + name + " — expected truthy, got: " + val)
    emit 0
}

func assertFalsy(name, val) {
    if isTruthy(val) {
        kp("[FAIL] " + name + " — expected falsy, got: " + val)
        emit 0
    }
    kp("[PASS] " + name)
    emit 1
}

// Skip a test (logged, not counted as fail).
func skipTest(name, reason) {
    kp("[SKIP] " + name + " — " + reason)
    emit 1
}

// Mark a test pending (visible in output).
func todoTest(name) {
    kp("[TODO] " + name)
    emit 1
}
