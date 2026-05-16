// Diamond pattern generator
// Creates a diamond shape from asterisks

func printSpaces(n) {
    let sb = sbNew()
    let i = 0
    while i < n {
        sb = sbAppend(sb, " ")
        i += 1
    }
    emit sbToString(sb)
}

func printStars(n) {
    let sb = sbNew()
    let i = 0
    while i < n {
        sb = sbAppend(sb, "*")
        i += 1
    }
    emit sbToString(sb)
}

func diamond(size) {
    // Top half (including middle)
    let i = 1
    while i <= size {
        let spaces = printSpaces(size - i)
        let stars = printStars(2 * i - 1)
        kp(spaces + stars)
        i += 1
    }
    // Bottom half
    i = size - 1
    while i >= 1 {
        let spaces = printSpaces(size - i)
        let stars = printStars(2 * i - 1)
        kp(spaces + stars)
        i -= 1
    }
}

func hollowDiamond(size) {
    // Top point
    kp(printSpaces(size - 1) + "*")

    // Top half
    let i = 2
    while i < size {
        let spaces = printSpaces(size - i)
        let inner = printSpaces(2 * i - 3)
        kp(spaces + "*" + inner + "*")
        i += 1
    }

    // Middle
    if size > 1 {
        kp("*" + printSpaces(2 * size - 3) + "*")
    }

    // Bottom half
    i = size - 1
    while i >= 2 {
        let spaces = printSpaces(size - i)
        let inner = printSpaces(2 * i - 3)
        kp(spaces + "*" + inner + "*")
        i -= 1
    }

    // Bottom point
    kp(printSpaces(size - 1) + "*")
}

just run {
    kp("Diamond Pattern (size 5):")
    diamond(5)
    kp("")
    kp("Hollow Diamond (size 6):")
    hollowDiamond(6)
    emit "ok"
}
