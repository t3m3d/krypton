// Print a multiplication table up to N×N.
// Builds each row as a single string concatenation.

func cell(n) {
    let s = "" + n
    if len(s) == 1 { emit "   " + s }
    if len(s) == 2 { emit "  " + s }
    if len(s) == 3 { emit " " + s }
    emit s
}

just run {
    let n = 10
    let r = 1
    while r <= n {
        let row = "" + r + " |"
        if r < 10 { row = " " + row }
        let c = 1
        while c <= n {
            row = row + cell(r * c)
            c += 1
        }
        kp(row)
        r += 1
    }
}
