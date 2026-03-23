// ============================================================
// Krypton v1.0.0 — Comprehensive Test Suite
// ============================================================

module test_v100

import "stdlib/result.k"
import "stdlib/math_utils.k"
import "stdlib/float_utils.k"
import "stdlib/option.k"

// ── Functions with type annotations ──────────────────────────
func add(a: int, b: int) -> int {
    emit toInt(a) + toInt(b) + ""
}

func greet(name: string) -> string {
    emit `Hello, {name}!`
}

func doubled(n: int) -> int {
    emit toInt(n) * 2 + ""
}

func sumList2(items: list) -> int {
    let total: int = "0"
    for n in items {
        total += toInt(n)
    }
    emit total + ""
}

// ── Struct (without jxt - known working) ─────────────────────
struct Vec2 {
    let x
    let y
}

func vecAdd(a, b) {
    let result = Vec2 { x: fadd(a.x, b.x), y: fadd(a.y, b.y) }
    emit result
}

func vecLen(v) {
    emit fsqrt(fadd(fmul(v.x, v.x), fmul(v.y, v.y)))
}

// ── Exception handling ────────────────────────────────────────
func safeSqrt(n) {
    if flt(n, "0") {
        throw "cannot sqrt negative"
    }
    emit fsqrt(n)
}

// ── Recursive function ────────────────────────────────────────
func fib(n) {
    if n <= 1 { emit n }
    emit toInt(fib(n - 1)) + toInt(fib(n - 2)) + ""
}

just run {
    let pass = 0
    let fail = 0

    // ── Basic arithmetic ──────────────────────────────────────
    if add("10", "20") == "30" { pass += 1  kp("PASS add") } else { fail += 1  kp("FAIL add") }
    if doubled("21") == "42"   { pass += 1  kp("PASS doubled") } else { fail += 1  kp("FAIL doubled") }

    // ── String interpolation ──────────────────────────────────
    let name = "Krypton"
    if greet(name) == "Hello, Krypton!" { pass += 1  kp("PASS interpolation") } else { fail += 1  kp("FAIL interp") }

    // ── Lists ─────────────────────────────────────────────────
    let nums = [1, 2, 3, 4, 5]
    if sumList2(nums) == "15" { pass += 1  kp("PASS list") } else { fail += 1  kp("FAIL list") }
    if split(nums, 2) == "3"  { pass += 1  kp("PASS list index") } else { fail += 1  kp("FAIL list idx") }

    // ── Control flow ──────────────────────────────────────────
    let x = "0"
    let i = 0
    while i < 5 {
        x = toInt(x) + i + ""
        i += 1
    }
    if x == "10" { pass += 1  kp("PASS while loop") } else { fail += 1  kp("FAIL while: " + x) }

    let total = "0"
    for n in "1,2,3,4,5" {
        total = toInt(total) + toInt(n) + ""
    }
    if total == "15" { pass += 1  kp("PASS for-in") } else { fail += 1  kp("FAIL for-in: " + total) }

    // ── Match ─────────────────────────────────────────────────
    let color = "blue"
    let temp = match color {
        "red"  { emit "warm" }
        "blue" { emit "cool" }
        else   { emit "other" }
    }
    if temp == "cool" { pass += 1  kp("PASS match") } else { fail += 1  kp("FAIL match") }

    // ── Try/catch ─────────────────────────────────────────────
    let caught = ""
    try {
        throw "test error"
    } catch e {
        caught = e
    }
    if caught == "test error" { pass += 1  kp("PASS try/catch") } else { fail += 1  kp("FAIL try/catch") }

    // ── Structs ───────────────────────────────────────────────
    let v1 = Vec2 { x: "3.0", y: "4.0" }
    let v2 = Vec2 { x: "1.0", y: "0.0" }
    if v1.x == "3.0" { pass += 1  kp("PASS struct field") } else { fail += 1  kp("FAIL struct") }
    let vl = vecLen(v1)
    if vl == "5" { pass += 1  kp("PASS struct method") } else { fail += 1  kp("FAIL vecLen: " + vl) }
    let v3 = vecAdd(v1, v2)
    if v3.x == "4" { pass += 1  kp("PASS struct return") } else { fail += 1  kp("FAIL vecAdd: " + v3.x) }

    // ── Floats ────────────────────────────────────────────────
    if fadd("1.5", "2.5") == "4"    { pass += 1  kp("PASS fadd") } else { fail += 1  kp("FAIL fadd") }
    if fmul("3.0", "4.0") == "12"   { pass += 1  kp("PASS fmul") } else { fail += 1  kp("FAIL fmul") }
    if fdiv("10.0", "4.0") == "2.5" { pass += 1  kp("PASS fdiv") } else { fail += 1  kp("FAIL fdiv") }
    if fsqrt("25.0") == "5"         { pass += 1  kp("PASS fsqrt") } else { fail += 1  kp("FAIL fsqrt") }
    if fformat("3.14159", "2") == "3.14" { pass += 1  kp("PASS fformat") } else { fail += 1  kp("FAIL fformat") }
    let fl = 3.14
    if startsWith(fl + "", "3") { pass += 1  kp("PASS float literal") } else { fail += 1  kp("FAIL float literal") }

    // ── Result module ─────────────────────────────────────────
    let r1 = ok("success")
    let r2 = err("failed")
    if isOk(r1) && unwrap(r1) == "success" { pass += 1  kp("PASS result ok") } else { fail += 1  kp("FAIL result ok") }
    if isErr(r2) && unwrapErr(r2) == "failed" { pass += 1  kp("PASS result err") } else { fail += 1  kp("FAIL result err") }

    // ── Math utils ────────────────────────────────────────────
    if gcd(48, 18) == "6"   { pass += 1  kp("PASS gcd") } else { fail += 1  kp("FAIL gcd") }
    if isPrime(17) == "1"   { pass += 1  kp("PASS isPrime") } else { fail += 1  kp("FAIL isPrime") }
    if factorial(5) == "120" { pass += 1  kp("PASS factorial") } else { fail += 1  kp("FAIL factorial") }
    if fibonacci(10) == "55" { pass += 1  kp("PASS fibonacci") } else { fail += 1  kp("FAIL fibonacci") }

    // ── Option module ─────────────────────────────────────────
    let s = optSome("world")
    let n = optNone()
    if isSome(s) && optUnwrap(s) == "world" { pass += 1  kp("PASS optSome") } else { fail += 1  kp("FAIL optSome") }
    if isNone(n) { pass += 1  kp("PASS optNone") } else { fail += 1  kp("FAIL optNone") }

    // ── Recursion ─────────────────────────────────────────────
    if fib(10) == "55" { pass += 1  kp("PASS fib recursive") } else { fail += 1  kp("FAIL fib: " + fib(10)) }

    // ── Exception from function ───────────────────────────────
    let sqrtResult = ""
    try {
        sqrtResult = safeSqrt("-1")
    } catch e {
        sqrtResult = "caught: " + e
    }
    if startsWith(sqrtResult, "caught") { pass += 1  kp("PASS throw from func") } else { fail += 1  kp("FAIL throw") }

    // ── Ternary ───────────────────────────────────────────────
    let label = "42" == "42" ? "yes" : "no"
    if label == "yes" { pass += 1  kp("PASS ternary") } else { fail += 1  kp("FAIL ternary") }

    // ── String builtins ───────────────────────────────────────
    if len("hello") == "5"              { pass += 1  kp("PASS len") } else { fail += 1  kp("FAIL len") }
    if contains("hello", "ell") == "1"  { pass += 1  kp("PASS contains") } else { fail += 1  kp("FAIL contains") }
    if replace("hello", "l", "r") == "herro" { pass += 1  kp("PASS replace") } else { fail += 1  kp("FAIL replace") }
    if toUpper("hello") == "HELLO"      { pass += 1  kp("PASS toUpper") } else { fail += 1  kp("FAIL toUpper") }
    if trim("  hi  ") == "hi"           { pass += 1  kp("PASS trim") } else { fail += 1  kp("FAIL trim") }

    // ── Summary ───────────────────────────────────────────────
    kp("")
    kp("============================================================")
    kp("Krypton v1.0.0 Test Results")
    kp("PASSED: " + pass)
    kp("FAILED: " + fail)
    if fail == "0" {
        kp("ALL TESTS PASSED — Krypton v1.0.0 ready!")
    } else {
        kp("SOME TESTS FAILED")
    }
    kp("============================================================")
}
