// CSV parsing and generation for Krypton
// Simple CSV with comma delimiters

module csv


// Parse a CSV line into a comma-separated list
func parseLine(line) {
    emit line
}

// Get a field from a CSV line by index.
// Renamed from getField to fieldAt so it doesn't collide with the
// native struct builtin getField(env, name), which the dispatcher resolves
// first and which interprets `line` as an env head pointer (crash).
func fieldAt(line, idx) {
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
        i += 1
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
        i += 1
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
        i += 1
    }
    emit sbToString(sb)
}

// ── RFC-4180 escape / write ──────────────────────────────────────────

// Escape a single CSV field. Quotes the field iff it contains comma,
// quote, newline, or carriage-return. Embedded quotes are doubled.
//
//   csvEscapeField("hi,mom")     → "\"hi,mom\""
//   csvEscapeField("she \"said\"") → "\"she \"\"said\"\"\""
//   csvEscapeField("plain")      → "plain"
func csvEscapeField(s) {
    let DQ = fromCharCode(34)
    let needsQuote = 0
    let i = 0
    while i < len(s) {
        let c = s[i]
        if c == "," || c == DQ || c == "\n" || c == "\r" { needsQuote = 1 }
        i = i + 1
    }
    if needsQuote == 0 { emit s }
    let out = sbNew()
    out = sbAppend(out, DQ)
    let j = 0
    while j < len(s) {
        let c = s[j]
        if c == DQ { out = sbAppend(out, DQ)  out = sbAppend(out, DQ) }
        else       { out = sbAppend(out, c) }
        j = j + 1
    }
    out = sbAppend(out, DQ)
    emit sbToString(out)
}

// Build a CSV line from a comma-CSV of unescaped values. Each value
// is escaped via csvEscapeField. (This shadows the comma-CSV input
// shape by joining with literal commas + properly quoting any field
// that contains one.)
//
//   csvLine("brian,hi,mom") → "brian,hi,mom"
//   csvLine("brian,\"hi,there\",ok") parsing tricky — pass values
//     separately via split if they contain commas, or use this helper
//     only for already-clean fields.
func csvLine(valuesCsv) {
    let n = count(valuesCsv)
    let out = sbNew()
    let i = 0
    while i < n {
        if i > 0 { out = sbAppend(out, ",") }
        out = sbAppend(out, csvEscapeField(split(valuesCsv, i)))
        i = i + 1
    }
    emit sbToString(out)
}

// Build a CSV document from a list of rows (each row is itself a CSV
// of fields joined by ";" inside the outer CSV — Krypton's only
// nested-list shape). Rows separated by "\r\n" per RFC 4180.
//
//   writeCSV("name;age,brian;42,alice;7")
//     → "name,age\r\nbrian,42\r\nalice,7\r\n"
func writeCSV(rowsCsv) {
    let n = count(rowsCsv)
    let out = sbNew()
    let i = 0
    while i < n {
        let row = replace(split(rowsCsv, i), ";", ",")
        out = sbAppend(out, csvLine(row))
        out = sbAppend(out, "\r\n")
        i = i + 1
    }
    emit sbToString(out)
}
