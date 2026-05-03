// Extract field N from each row of a pipe-separated, semicolon-delimited dataset.

func column(row, idx) {
    let cur = ""
    let i = 0
    let n = len(row)
    let count = 0
    while i < n {
        let ch = row[i]
        if ch == ";" {
            if count == idx { emit cur }
            cur = ""
            count += 1
        } else {
            cur = cur + ch
        }
        i += 1
    }
    if count == idx { emit cur }
    emit ""
}

func processRow(row) {
    kp("  name=" + column(row, 0) + "  age=" + column(row, 1) + "  role=" + column(row, 2))
}

just run {
    let data = "Alice;30;Engineer|Bob;25;Designer|Carol;35;Manager|Dave;28;Architect"
    let n = len(data)
    let i = 0
    let cur = ""
    kp("Parsed rows:")
    while i < n {
        let ch = data[i]
        if ch == "|" {
            processRow(cur)
            cur = ""
        } else {
            cur = cur + ch
        }
        i += 1
    }
    if len(cur) > 0 { processRow(cur) }
}
