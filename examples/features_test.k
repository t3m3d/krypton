func add(a, b) {
    emit a + b
}

func greet(name) {
    emit "Hello, " + name
}

go run {
    // Test function calls
    let x = add(3, 4)
    kp(x)

    // Test string ops
    let msg = greet("Krypton")
    kp(msg)

    // Test while loop
    let i = 0
    while i < 5 {
        kp(i)
        i = i + 1
    }

    // Test if/else if/else
    let val = 42
    if val == 42 {
        kp("found it")
    } else if val == 0 {
        kp("zero")
    } else {
        kp("other")
    }

    // Test string indexing
    let s = "abc"
    kp(s[0])
    kp(s[1])
    kp(s[2])

    // Test comparisons
    if 10 > 5 {
        kp("10 > 5")
    }

    // Test split and toInt
    let pair = "hello,world"
    let first = split(pair, 0)
    let second = split(pair, 1)
    kp(first)
    kp(second)

    // Test startsWith
    if startsWith("hello world", "hello") {
        kp("starts with hello")
    }

    // Test len
    kp(len("test"))

    emit "ok"
}
