// Matrix operations using flat arrays

func matGet(mat, cols, row, col) {
    emit toInt(split(mat, row * cols + col))
}

func matSet(mat, cols, row, col, val, totalSize) {
    let sb = sbNew()
    let idx = row * cols + col
    let i = 0
    while i < totalSize {
        if i > 0 { sb = sbAppend(sb, ",") }
        if i == idx {
            sb = sbAppend(sb, "" + val)
        } else {
            sb = sbAppend(sb, split(mat, i))
        }
        i = i + 1
    }
    emit sbToString(sb)
}

func matMul(a, aRows, aCols, b, bCols) {
    // Result: aRows x bCols
    let size = aRows * bCols
    // Initialize result with zeros
    let result = ""
    let i = 0
    while i < size {
        if i > 0 { result = result + "," }
        result = result + "0"
        i = i + 1
    }

    i = 0
    while i < aRows {
        let j = 0
        while j < bCols {
            let sum = 0
            let k = 0
            while k < aCols {
                sum = sum + matGet(a, aCols, i, k) * matGet(b, bCols, k, j)
                k = k + 1
            }
            result = matSet(result, bCols, i, j, sum, size)
            j = j + 1
        }
        i = i + 1
    }
    emit result
}

func printMat(mat, rows, cols) {
    let i = 0
    while i < rows {
        let sb = sbNew()
        sb = sbAppend(sb, "  [")
        let j = 0
        while j < cols {
            if j > 0 { sb = sbAppend(sb, ", ") }
            sb = sbAppend(sb, "" + matGet(mat, cols, i, j))
            j = j + 1
        }
        sb = sbAppend(sb, "]")
        print(sbToString(sb))
        i = i + 1
    }
}

just run {
    // 2x3 matrix
    let a = "1,2,3,4,5,6"
    // 3x2 matrix
    let b = "7,8,9,10,11,12"

    print("Matrix A (2x3):")
    printMat(a, 2, 3)
    print("Matrix B (3x2):")
    printMat(b, 3, 2)

    let result = matMul(a, 2, 3, b, 2)
    print("A x B (2x2):")
    printMat(result, 2, 2)
}
