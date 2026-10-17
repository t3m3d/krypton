// Tutorial 24: String Interpolation
// Backtick strings with {expr} placeholders

just run {
    let name = "Krypton"
    let version = "0.7.2"

    // Basic interpolation
    print(`Hello from {name}!`)
    print(`Version: {version}`)

    // Multiple expressions
    let x = "10"
    let y = "20"
    print(`Point: ({x}, {y})`)

    // In function
    func greet(person, lang) {
        emit `Hello {person}, welcome to {lang}!`
    }
    print(greet("Brian", "Krypton"))

    // In loops
    let items = "apple,banana,cherry"
    let i = 0
    for item in items {
        print(`  {i}: {item}`)
        i += 1
    }

    // Combined with other expressions
    let count = "42"
    print(`Found {count} results`)
}
