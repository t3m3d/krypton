// Test: String interpolation with backtick strings

just run {
    let name = "Krypton"
    let n = "42"

    // Basic interpolation
    let s1 = `Hello {name}`
    if s1 == "Hello Krypton" { kp("PASS basic interp") } else { kp("FAIL basic interp: " + s1) }

    // Multiple expressions
    let x = "3"
    let y = "4"
    let s2 = `({x}, {y})`
    if s2 == "(3, 4)" { kp("PASS multi interp") } else { kp("FAIL multi interp: " + s2) }

    // Interpolation with surrounding text
    let s3 = `value is {n} items`
    if s3 == "value is 42 items" { kp("PASS surrounding text") } else { kp("FAIL surrounding text: " + s3) }

    // Interpolation at start
    let s4 = `{name} is great`
    if s4 == "Krypton is great" { kp("PASS interp at start") } else { kp("FAIL interp at start: " + s4) }

    // Interpolation at end
    let s5 = `Hello {name}`
    if s5 == "Hello Krypton" { kp("PASS interp at end") } else { kp("FAIL interp at end: " + s5) }

    kp("interpolation tests done")
}
