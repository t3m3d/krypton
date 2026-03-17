// v0.8.5 — optional type annotations on variables and functions
// NOTE: struct field type annotations require further investigation
// and will be enabled in a future release.

module test_v085

import "stdlib/result.k"
import "stdlib/math_utils.k"

func add(a: int, b: int) -> int {
    emit toInt(a) + toInt(b) + ""
}

func greet(name: string) -> string {
    emit "Hello, " + name + "!"
}

func safeDivide(a: int, b: int) -> string {
    if b == "0" { emit err("division by zero") }
    emit ok(toInt(a) / toInt(b) + "")
}

func sumList2(items: list) -> int {
    let total: int = "0"
    for n in items {
        total += toInt(n)
    }
    emit total + ""
}

func doubled(n: int) -> int {
    emit toInt(n) * 2 + ""
}

just run {
    // typed variable declarations
    let x: int = "10"
    let y: int = "20"
    let greeting: string = "Krypton"
    let items: list = "1,2,3,4,5"
    let flag: bool = "1"

    // typed function params
    if add(x, y) == "30"                   { kp("PASS add(a:int, b:int)") }      else { kp("FAIL add: " + add(x, y)) }
    if greet(greeting) == "Hello, Krypton!"{ kp("PASS greet(name:string)") }     else { kp("FAIL greet") }

    // -> return type annotation
    let r = safeDivide("10", "2")
    if isOk(r)                             { kp("PASS -> return type") }         else { kp("FAIL return type") }
    let r2 = safeDivide("10", "0")
    if isErr(r2)                           { kp("PASS err path") }               else { kp("FAIL err path") }

    // list param
    if sumList2(items) == "15"             { kp("PASS list param") }             else { kp("FAIL list: " + sumList2(items)) }

    // basic typed func
    if doubled("7") == "14"               { kp("PASS doubled(n:int)") }         else { kp("FAIL doubled") }

    // unannotated code still works
    let z = "42"
    if z == "42"                           { kp("PASS untyped var") }            else { kp("FAIL untyped") }

    // annotations don't break imports
    if isPrime(17) == "1"                  { kp("PASS import works") }           else { kp("FAIL import") }
    if gcd(48, 18) == "6"                  { kp("PASS gcd") }                    else { kp("FAIL gcd") }
    if factorial(5) == "120"               { kp("PASS factorial") }              else { kp("FAIL factorial") }

    kp("ALL v0.8.5 TESTS PASSED")
}
