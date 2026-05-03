// Test boolean literals and the booleans stdlib helpers.

func check(name, expected, actual) {
    if expected == actual {
        kp("[PASS] " + name)
    } else {
        kp("[FAIL] " + name + " expected=" + expected + " actual=" + actual)
    }
}

// Inline copies of the booleans.k helpers (stdlib auto-import isn't yet
// wired in the native pipeline — see test_pair_ops.k for the same dodge).

func bool(v) {
    if isTruthy(v) { emit "true" }
    emit "false"
}

func boolToInt(v) {
    if isTruthy(v) { emit 1 }
    emit 0
}

func boolEq(a, b) {
    if isTruthy(a) {
        if isTruthy(b) { emit "true" }
        emit "false"
    }
    if isTruthy(b) { emit "false" }
    emit "true"
}

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

just run {
    kp("Boolean Tests")
    kp("=============")

    // Literals stringify to "true" / "false"
    check("true literal",  "true",  "" + true)
    check("false literal", "false", "" + false)

    // Truthiness — empty / "0" / "false" / 0 are all falsy
    check("isTruthy true",       "1", "" + isTruthy(true))
    check("isTruthy false",      "0", "" + isTruthy(false))
    check("isTruthy 1",          "1", "" + isTruthy(1))
    check("isTruthy 0",          "0", "" + isTruthy(0))
    check("isTruthy non-empty",  "1", "" + isTruthy("hello"))
    check("isTruthy empty",      "0", "" + isTruthy(""))
    check("isTruthy \"0\"",      "0", "" + isTruthy("0"))
    check("isTruthy \"false\"",  "0", "" + isTruthy("false"))
    check("isTruthy \"true\"",   "1", "" + isTruthy("true"))

    // `if` follows the same rules
    let yes = "yes"
    if true        { check("if true",        "yes", yes) } else { check("if true",        "yes", "no") }
    if !false      { check("if !false",      "yes", yes) } else { check("if !false",      "yes", "no") }
    if "0"         { check("if \"0\"",       "yes", "no") } else { check("if \"0\"",      "yes", yes) }
    if "false"     { check("if \"false\"",   "yes", "no") } else { check("if \"false\"",  "yes", yes) }
    if ""          { check("if empty",       "yes", "no") } else { check("if empty",      "yes", yes) }
    if "anything"  { check("if non-empty",   "yes", yes) } else { check("if non-empty",   "yes", "no") }

    // bool() coerces
    check("bool(true)",   "true",  bool(true))
    check("bool(1)",      "true",  bool(1))
    check("bool(\"hi\")", "true",  bool("hi"))
    check("bool(false)",  "false", bool(false))
    check("bool(0)",      "false", bool(0))
    check("bool(\"\")",   "false", bool(""))
    check("bool(\"0\")",  "false", bool("0"))

    // boolToInt() coerces to 1/0
    check("boolToInt(true)",  "1", "" + boolToInt(true))
    check("boolToInt(false)", "0", "" + boolToInt(false))
    check("boolToInt(\"hi\")","1", "" + boolToInt("hi"))

    // boolEq normalizes representations
    check("boolEq(true,1)",        "true", boolEq(true, 1))
    check("boolEq(false,0)",       "true", boolEq(false, 0))
    check("boolEq(true,\"true\")", "true", boolEq(true, "true"))
    check("boolEq(true,false)",    "false", boolEq(true, false))
    check("boolEq(\"hi\",1)",      "true", boolEq("hi", 1))

    // Explicit boolean ops
    check("boolNot(true)",   "false", boolNot(true))
    check("boolNot(false)",  "true",  boolNot(false))
    check("boolAnd(t,t)",    "true",  boolAnd(true, true))
    check("boolAnd(t,f)",    "false", boolAnd(true, false))
    check("boolAnd(f,t)",    "false", boolAnd(false, true))
    check("boolOr(t,f)",     "true",  boolOr(true, false))
    check("boolOr(f,f)",     "false", boolOr(false, false))
    check("boolXor(t,t)",    "false", boolXor(true, true))
    check("boolXor(t,f)",    "true",  boolXor(true, false))
    check("boolXor(f,f)",    "false", boolXor(false, false))

    // Comparison ops still return "1"/"0" (unchanged for back-compat)
    check("5>3 returns int",  "1", "" + (5 > 3))
    check("5<3 returns int",  "0", "" + (5 < 3))

    emit "ok"
}
