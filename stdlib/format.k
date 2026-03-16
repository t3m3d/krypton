// Formatting utilities for Krypton
// String and number formatting functions

go format {

    // Format a number with leading zeros
    func zeroPad(n, width) {
        let s = "" + n
        while len(s) < width {
            s = "0" + s
        }
        emit s
    }

    // Format a number with thousand separators
    func formatNumber(n) {
        let s = "" + n
        let sLen = len(s)
        if sLen <= 3 {
            emit s
        }
        let sb = sbNew()
        let i = 0
        while i < sLen {
            let remaining = sLen - i
            if remaining % 3 == 0 {
                if i > 0 {
                    sb = sbAppend(sb, ",")
                }
            }
            sb = sbAppend(sb, s[i])
            i += 1
        }
        emit sbToString(sb)
    }

    // Center a string within a given width
    func center(s, width, fillChar) {
        let sLen = len(s)
        if sLen >= width {
            emit s
        }
        let totalPad = width - sLen
        let leftPad = totalPad / 2
        let rightPad = totalPad - leftPad
        let sb = sbNew()
        let i = 0
        while i < leftPad {
            sb = sbAppend(sb, fillChar)
            i += 1
        }
        sb = sbAppend(sb, s)
        i = 0
        while i < rightPad {
            sb = sbAppend(sb, fillChar)
            i += 1
        }
        emit sbToString(sb)
    }

    // Create a horizontal rule
    func horizontalRule(ch, width) {
        let sb = sbNew()
        let i = 0
        while i < width {
            sb = sbAppend(sb, ch)
            i += 1
        }
        emit sbToString(sb)
    }

    // Format a key-value pair with alignment
    func formatKV(key, value, width) {
        let padded = key
        while len(padded) < width {
            padded = padded + " "
        }
        emit padded + ": " + value
    }

    // Format a percentage
    func formatPercent(num, total) {
        if total == 0 {
            emit "0%"
        }
        let pct = (num * 100) / total
        emit "" + pct + "%"
    }

    // Create a simple progress bar
    func progressBar(current, total, width) {
        let filled = (current * width) / total
        let empty = width - filled
        let sb = sbNew()
        sb = sbAppend(sb, "[")
        let i = 0
        while i < filled {
            sb = sbAppend(sb, "#")
            i += 1
        }
        i = 0
        while i < empty {
            sb = sbAppend(sb, "-")
            i += 1
        }
        sb = sbAppend(sb, "] ")
        sb = sbAppend(sb, "" + ((current * 100) / total))
        sb = sbAppend(sb, "%")
        emit sbToString(sb)
    }

    // Format a table row with column widths
    func tableRow(col1, col2, col3, w1, w2, w3) {
        let sb = sbNew()
        let c1 = col1
        while len(c1) < w1 {
            c1 = c1 + " "
        }
        let c2 = col2
        while len(c2) < w2 {
            c2 = c2 + " "
        }
        let c3 = col3
        while len(c3) < w3 {
            c3 = c3 + " "
        }
        sb = sbAppend(sb, "| ")
        sb = sbAppend(sb, c1)
        sb = sbAppend(sb, " | ")
        sb = sbAppend(sb, c2)
        sb = sbAppend(sb, " | ")
        sb = sbAppend(sb, c3)
        sb = sbAppend(sb, " |")
        emit sbToString(sb)
    }

    // Format bytes as human readable
    func formatBytes(bytes) {
        if bytes < 1024 {
            emit "" + bytes + " B"
        }
        let kb = bytes / 1024
        if kb < 1024 {
            emit "" + kb + " KB"
        }
        let mb = kb / 1024
        emit "" + mb + " MB"
    }
}
