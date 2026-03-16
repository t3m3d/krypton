// Triangle pattern generator
// Various triangle shapes using characters

func rightTriangle(n) {
    kp("Right Triangle:")
    let i = 1
    while i <= n {
        let sb = sbNew()
        let j = 0
        while j < i {
            sb = sbAppend(sb, "*")
            j += 1
        }
        kp(sbToString(sb))
        i += 1
    }
}

func invertedTriangle(n) {
    kp("Inverted Triangle:")
    let i = n
    while i >= 1 {
        let sb = sbNew()
        let j = 0
        while j < i {
            sb = sbAppend(sb, "*")
            j += 1
        }
        kp(sbToString(sb))
        i -= 1
    }
}

func centeredTriangle(n) {
    kp("Centered Triangle:")
    let i = 1
    while i <= n {
        let sb = sbNew()
        let spaces = n - i
        let j = 0
        while j < spaces {
            sb = sbAppend(sb, " ")
            j += 1
        }
        j = 0
        while j < 2 * i - 1 {
            sb = sbAppend(sb, "*")
            j += 1
        }
        kp(sbToString(sb))
        i += 1
    }
}

func numberTriangle(n) {
    kp("Number Triangle:")
    let i = 1
    while i <= n {
        let sb = sbNew()
        let j = 1
        while j <= i {
            sb = sbAppend(sb, "" + j)
            j += 1
        }
        kp(sbToString(sb))
        i += 1
    }
}

func pascalTriangle(n) {
    kp("Pascal's Triangle:")
    let row = "1"
    let i = 0
    while i < n {
        // Print current row with spacing
        let sb = sbNew()
        let spaces = n - i - 1
        let j = 0
        while j < spaces {
            sb = sbAppend(sb, " ")
            j += 1
        }
        let rSize = count(row)
        j = 0
        while j < rSize {
            if j > 0 {
                sb = sbAppend(sb, " ")
            }
            sb = sbAppend(sb, split(row, j))
            j += 1
        }
        kp(sbToString(sb))

        // Compute next row
        let newRow = "1"
        j = 0
        while j < rSize - 1 {
            let sum = toInt(split(row, j)) + toInt(split(row, j + 1))
            newRow = newRow + "," + sum
            j += 1
        }
        newRow = newRow + ",1"
        row = newRow
        i += 1
    }
}

just run {
    let size = 6
    rightTriangle(size)
    kp("")
    invertedTriangle(size)
    kp("")
    centeredTriangle(size)
    kp("")
    numberTriangle(size)
    kp("")
    pascalTriangle(7)
    emit "ok"
}
