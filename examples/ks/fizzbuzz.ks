#!/usr/bin/env kr
// fizzbuzz.ks — KryptScript in the Swift-like top-level style (no `just run`
// wrapper). kr auto-wraps the body.
//
//   kr examples/ks/fizzbuzz.ks         -> 1..15
//   kr examples/ks/fizzbuzz.ks 20      -> 1..20
//   ./examples/ks/fizzbuzz.ks 20       -> same, after `chmod +x`
let n = 15
if argCount() > 0 { n = toInt(arg(0)) }

let i = 1
while i <= n {
    if i % 15 == 0 {
        kp("FizzBuzz")
    } else if i % 3 == 0 {
        kp("Fizz")
    } else if i % 5 == 0 {
        kp("Buzz")
    } else {
        kp(toStr(i))
    }
    i = i + 1
}
