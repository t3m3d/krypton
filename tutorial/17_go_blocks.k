// Tutorial 17: Modules with go
// Using 'go' blocks for named entry points / modules

// 'go' defines a named block, like a module or named main
go math_demo {
    func square(n) { emit n * n }
    func cube(n) { emit n * n * n }

    print("=== Math Demo ===")
    let i = 1
    while i <= 5 {
        print("" + i + ": square=" + square(i) + " cube=" + cube(i))
        i = i + 1
    }
}
