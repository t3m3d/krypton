// Assertion and testing helpers for Krypton

go assert {

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
}
