// A2 switch/case — lowered to existing IR (temp + EQ + JUMPIF/JUMP/LABEL) in the
// FE, so it works on every backend (no codegen change). No implicit fallthrough.
just run {
    let s = "running"
    let r = ""
    switch s {
        case "idle":          r = "I"
        case "running":       r = "R"
        case "done", "error": r = "DE"
        default:              r = "X"
    }
    if r != "R" { kp("[FAIL] string case"); exit("1") }

    let r2 = ""
    switch "error" { case "done", "error": r2 = "M"  default: r2 = "N" }
    if r2 != "M" { kp("[FAIL] multi-value case"); exit("1") }

    let r3 = ""
    switch 2 { case 1: r3 = "one"  case 2: r3 = "two"  default: r3 = "many" }
    if r3 != "two" { kp("[FAIL] int case"); exit("1") }

    let r4 = ""
    switch "zzz" { case "a": r4 = "a"  default: r4 = "def" }
    if r4 != "def" { kp("[FAIL] default"); exit("1") }

    let r5 = "untouched"
    switch "nope" { case "x": r5 = "x" }
    if r5 != "untouched" { kp("[FAIL] no-match no-default"); exit("1") }

    kp("[PASS] switch/case (string, int, multi-value, default, no-match)")
}
