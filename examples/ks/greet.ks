#!/usr/bin/env kr
// greet.ks — KryptScript in the Swift-like top-level style: no `just run`
// wrapper. kr auto-wraps the body, and imports + funcs work right here at
// the top of the file.
//
//   kr examples/ks/greet.ks            -> greets the world
//   kr examples/ks/greet.ks Ada        -> greets Ada
//   ./examples/ks/greet.ks Ada         -> same, after `chmod +x`
import "k:ansi"

func greeting(who) { emit "Hello, " + who + "!" }

let who = "world"
if argCount() > 0 { who = arg(0) }

kp(bold(cyan(greeting(who))))
kp(gray("— written top-to-bottom, no boilerplate"))
