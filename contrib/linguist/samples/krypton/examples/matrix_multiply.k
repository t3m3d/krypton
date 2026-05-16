// Matrix operations (2D arrays using nested comma-separated strings)
// Matrices stored as newline-delimited rows, each row comma-separated

func matrixGet(matrix, row, col) {
    let line = getLine(matrix, row)
    emit toInt(split(line, col))
}

func matrixMultiply(a, b, aRows, aCols, bCols) {
    let sb = sbNew()
    let i = 0
    while i < aRows {
        let j = 0
        while j < bCols {
            let sum = 0
            let k = 0
            while k < aCols {
                sum = sum + matrixGet(a, i, k) * matrixGet(b, k, j)
                k += 1
            }
            if j > 0 {
                sb = sbAppend(sb, ",")
            }
            sb = sbAppend(sb, "" + sum)
            j += 1
        }
        sb = sbAppend(sb, "\n")
        i += 1
    }
    emit sbToString(sb)
}

func printMatrix(label, matrix, rows) {
    kp(label + ":")
    let i = 0
    while i < rows {
        let line = getLine(matrix, i)
        let cols = count(line)
        let sb = sbNew()
        sb = sbAppend(sb, "  [")
        let j = 0
        while j < cols {
            let val = split(line, j)
            while len(val) < 5 {
                val = " " + val
            }
            sb = sbAppend(sb, val)
            j += 1
        }
        sb = sbAppend(sb, " ]")
        kp(sbToString(sb))
        i += 1
    }
}

just run {
    kp("Matrix Multiplication")
    kp("=====================")
    kp("")

    // Define 2x3 matrix A
    let a = "1,2,3\n4,5,6\n"
    // Define 3x2 matrix B
    let b = "7,8\n9,10\n11,12\n"

    printMatrix("Matrix A (2x3)", a, 2)
    kp("")
    printMatrix("Matrix B (3x2)", b, 3)
    kp("")

    let result = matrixMultiply(a, b, 2, 3, 2)
    printMatrix("A x B (2x2)", result, 2)
    kp("")

    // Identity matrix test
    let identity = "1,0\n0,1\n"
    let c = "5,6\n7,8\n"
    printMatrix("Matrix C", c, 2)
    kp("")
    let identResult = matrixMultiply(c, identity, 2, 2, 2)
    printMatrix("C x I (should equal C)", identResult, 2)
    emit "ok"
}
