// Tutorial 24: String Interpolation
// Backtick strings with {expr} placeholders

just run {
    let name = "Krypton"
    let version = "0.7.2"

    // Basic interpolation
    kp(`Hello from {name}!`)
    kp(`Version: {version}`)

    // Multiple expressions
    let x = "10"
    let y = "20"
    kp(`Point: ({x}, {y})`)

    // In function
    func greet(person, lang) {
        emit `Hello {person}, welcome to {lang}!`
    }
    kp(greet("Brian", "Krypton"))

    // In loops
    let items = "apple,banana,cherry"
    let i = 0
    for item in items {
        kp(`  {i}: {item}`)
        i += 1
    }

    // Combined with other expressions
    let count = "42"
    kp(`Found {count} results`)
}
