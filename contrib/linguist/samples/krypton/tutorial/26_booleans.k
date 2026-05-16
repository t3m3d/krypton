// 26 — Booleans
//
// Krypton has `true` and `false` as keywords. They evaluate to the
// strings "true" and "false" respectively (Krypton's value model is
// uniformly string-based; there's no distinct boolean runtime type).
//
// Run with:  kcc.sh --native tutorial/26_booleans.k -o /tmp/_t && /tmp/_t

just run {
    // ── Literals ────────────────────────────────────────────────────
    kp(true)        // "true"
    kp(false)       // "false"

    let flag = true
    kp("flag = " + flag)   // flag = true


    // ── Truthiness ──────────────────────────────────────────────────
    // The following are FALSY:
    //   true:                                        nope, true is truthy
    //   false      ("false")                         FALSY
    //   the empty string ""                          FALSY
    //   the digit-zero string "0"                    FALSY
    //   the integer 0                                FALSY
    //
    // Everything else is truthy — including non-numeric non-empty
    // strings like "anything", "no", "false " (note trailing space), etc.

    if true   { kp("true is truthy")  }
    if !false { kp("false is falsy")  }
    if "0"    { kp("not reached") } else { kp("'0' is falsy")     }
    if "no"   { kp("'no' is truthy") }      // surprising? "no" is non-empty


    // ── Comparison and logical ops return ints ──────────────────────
    // For backward compat with builtins like hasField/isDigit (which
    // return "1"/"0"), comparison and logical ops still return "1" or
    // "0" small ints, NOT "true"/"false" strings. So:
    kp("5 > 3 = " + (5 > 3))           // 5 > 3 = 1
    kp("5 < 3 = " + (5 < 3))           // 5 < 3 = 0
    kp("!true  = " + (!true))          // !true  = 0
    kp("!false = " + (!false))         // !false = 1


    // ── Mixing the two forms ────────────────────────────────────────
    // Watch out: literal `true` is the string "true", but `5 > 3` is
    // the int 1. They're both truthy, but `true == (5 > 3)` is FALSE
    // because "true" and "1" are different strings.

    if true == (5 > 3) {
        kp("never reached")
    } else {
        kp("'true' != 1 (different value forms)")
    }

    // For "do these mean the same boolean?" use truthy comparison:
    if isTruthy(true) == isTruthy(5 > 3) {
        kp("both truthy: matches as booleans")
    }


    // ── stdlib/booleans.k normalises both forms ─────────────────────
    // The booleans stdlib gives you bool() to coerce to "true"/"false"
    // strings consistently:
    //
    //   import "stdlib/booleans.k"
    //   bool(5 > 3)  -> "true"
    //   bool(true)   -> "true"
    //   bool("hi")   -> "true"
    //   boolEq(true, 1)  -> "true"   (truthy-equality)
    //
    // (Until native module imports are wired, inline the helpers — see
    // tests/test_booleans.k for the pattern.)

    emit "ok"
}
