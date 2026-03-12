// CSV parsing and generation for Krypton
// Simple CSV with comma delimiters

go csv {

    // Parse a CSV line into a comma-separated list
    func parseLine(line) {
        emit line
    }

    // Get a field from a CSV line by index
    func getField(line, idx) {
        emit split(line, idx)
    }

    // Count fields in a CSV line
    func fieldCount(line) {
        emit count(line)
    }

    // Create a CSV line from individual values
    func makeLine(a, b, c) {
        emit a + "," + b + "," + c
    }

    // Parse entire CSV text into rows (newline-delimited, fields comma-separated)
    func parseCSV(text) {
        // Each row is a line, fields are comma-separated
        emit text
    }

    // Get a cell value from CSV: row index and column index
    func getCell(text, row, col) {
        let line = getLine(text, row)
        emit split(line, col)
    }

    // Count rows in CSV
    func rowCount(text) {
        emit lineCount(text)
    }

    // Extract a column as comma-separated list
    func getColumn(text, colIdx) {
        let result = ""
        let rows = lineCount(text)
        let i = 0
        while i < rows {
            let line = getLine(text, i)
            if len(line) > 0 {
                let val = split(line, colIdx)
                if result == "" {
                    result = val
                } else {
                    result = result + "," + val
                }
            }
            i = i + 1
        }
        emit result
    }

    // Add a row to CSV text
    func addRow(text, row) {
        if len(text) == 0 {
            emit row
        }
        emit text + "\n" + row
    }

    // Format CSV as aligned table
    func formatTable(text) {
        let sb = sbNew()
        let rows = lineCount(text)
        // Find max column widths (assume 3 columns max)
        let w0 = 0
        let w1 = 0
        let w2 = 0
        let i = 0
        while i < rows {
            let line = getLine(text, i)
            if len(line) > 0 {
                let f0 = split(line, 0)
                if len(f0) > w0 {
                    w0 = len(f0)
                }
                if count(line) > 1 {
                    let f1 = split(line, 1)
                    if len(f1) > w1 {
                        w1 = len(f1)
                    }
                }
                if count(line) > 2 {
                    let f2 = split(line, 2)
                    if len(f2) > w2 {
                        w2 = len(f2)
                    }
                }
            }
            i = i + 1
        }
        // Format each row
        i = 0
        while i < rows {
            let line = getLine(text, i)
            if len(line) > 0 {
                let f0 = split(line, 0)
                while len(f0) < w0 {
                    f0 = f0 + " "
                }
                sb = sbAppend(sb, f0)
                if count(line) > 1 {
                    let f1 = split(line, 1)
                    while len(f1) < w1 {
                        f1 = f1 + " "
                    }
                    sb = sbAppend(sb, " | " + f1)
                }
                if count(line) > 2 {
                    let f2 = split(line, 2)
                    sb = sbAppend(sb, " | " + f2)
                }
                sb = sbAppend(sb, "\n")
            }
            i = i + 1
        }
        emit sbToString(sb)
    }
}
