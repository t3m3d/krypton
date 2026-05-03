// Print a multiplication table up to N×N.

func pad(s, w) {
    let out = "" + s
    while len(out) < w {
        out = " " + out
    }
    emit out
}

just run {
    let n = 10

    // header row
    let header = "     "
    let i = 1
    while i <= n {
        header = header + pad("" + i, 5)
        i += 1
    }
    kp(header)

    // body
    let r = 1
    while r <= n {
        let row = pad("" + r, 4) + "|"
        let c = 1
        while c <= n {
            row = row + pad("" + (r * c), 5)
            c += 1
        }
        kp(row)
        r += 1
    }
}
