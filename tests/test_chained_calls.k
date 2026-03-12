// Test chained function calls

func check(name, expected, actual) {
    if expected == actual {
        kp("[PASS] " + name)
    } else {
        kp("[FAIL] " + name + " expected=" + expected + " actual=" + actual)
    }
}

func add(a, b) { emit a + b }
func double(n) { emit n * 2 }
func square(n) { emit n * n }
func negate(n) { emit 0 - n }
func stringify(n) { emit "val=" + n }

just run {
    kp("Chained Call Tests")
    kp("==================")

    // Simple chains
    check("add-double", "10", "" + double(add(2, 3)))
    check("double-add", "14", "" + add(double(3), double(4)))
    check("square-add", "25", "" + square(add(2, 3)))
    check("add-square", "13", "" + add(square(2), square(3)))

    // Deep chains
    check("triple chain", "100", "" + square(double(add(1, 4))))
    check("four deep", "200", "" + double(square(double(add(1, 4)))))

    // Mixed string and number
    check("stringify chain", "val=10", stringify(double(5)))
    check("stringify add", "val=7", stringify(add(3, 4)))

    // Use result in loop
    let sum = 0
    let i = 0
    while i < 5 {
        sum = add(sum, double(i))
        i = i + 1
    }
    check("loop chain", "20", "" + sum)

    emit "ok"
}
