// N-Queens problem solver

func abs(n) {
    if n < 0 { emit 0 - n }
    emit n
}

func isSafe(queens, row, col, n) {
    let i = 0
    while i < row {
        let qCol = toInt(split(queens, i))
        if qCol == col { emit 0 }
        if abs(qCol - col) == abs(i - row) { emit 0 }
        i += 1
    }
    emit 1
}

func solveQueens(queens, row, n, maxSolutions) {
    if row == n {
        // Print solution
        let sb = sbNew()
        sb = sbAppend(sb, "  [")
        let i = 0
        while i < n {
            if i > 0 { sb = sbAppend(sb, ", ") }
            sb = sbAppend(sb, split(queens, i))
            i += 1
        }
        sb = sbAppend(sb, "]")
        kp(sbToString(sb))
        emit 1
    }

    let found = 0
    let col = 0
    while col < n {
        if isSafe(queens, row, col, n) {
            let newQueens = queens
            if row > 0 {
                newQueens = queens + "," + col
            } else {
                newQueens = "" + col
            }
            found = found + solveQueens(newQueens, row + 1, n, maxSolutions)
            if found >= maxSolutions { emit found }
        }
        col = col + 1
    }
    emit found
}

just run {
    let n = 6
    kp(n + "-Queens Solutions (first 4):")
    let total = solveQueens("", 0, n, 4)
    kp("Found " + total + " solutions")
}
