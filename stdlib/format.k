// Formatting utilities for Krypton
// String and number formatting functions

module format


// Format a number with leading zeros.
//
// Krypton bug: `"0" + s` auto-coerces to integer addition (so "0" + "5"
// returns 5, not "05"). Build via sbAppend to keep the leading zero.
// Without this, the original implementation looped forever on any
// single-digit input because the string never lengthened.
func zeroPad(n, width) {
    let s = "" + n
    while len(s) < width {
        let b = sbNew()
        b = sbAppend(b, "0")
        b = sbAppend(b, s)
        s = sbToString(b)
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
    if mb < 1024 {
        emit "" + mb + " MB"
    }
    let gb = mb / 1024
    if gb < 1024 {
        emit "" + gb + " GB"
    }
    let tb = gb / 1024
    emit "" + tb + " TB"
}

// ── Template formatting (sprintf-like) ───────────────────────────────

// Substitute "{}" placeholders left-to-right with comma-separated args.
// To get a literal "{}" in the output, use "{{}}".
//
//   fmt("hello {}, you have {} new", "brian,3") → "hello brian, you have 3 new"
func fmt(template, args) {
    let out = sbNew()
    let i = 0
    let argIdx = 0
    while i < len(template) {
        // Literal "{{}}" → emit "{}", skip placeholder consumption.
        if i + 3 < len(template) && template[i] == "{" && template[i + 1] == "{" && template[i + 2] == "}" && template[i + 3] == "}" {
            out = sbAppend(out, "{}")
            i = i + 4
        } else if i + 1 < len(template) && template[i] == "{" && template[i + 1] == "}" {
            if argIdx < count(args) {
                out = sbAppend(out, split(args, argIdx))
                argIdx = argIdx + 1
            }
            i = i + 2
        } else {
            out = sbAppend(out, template[i])
            i = i + 1
        }
    }
    emit sbToString(out)
}

// ── Plural / ordinal ─────────────────────────────────────────────────

// pluralize("file", 1) → "file"; pluralize("file", 3) → "files".
// Two-arg form uses the "+s" rule. Use pluralizeN for irregulars.
func pluralize(word, count) {
    if toInt(count) == 1 { emit word }
    let b = sbNew()
    b = sbAppend(b, word)
    b = sbAppend(b, "s")
    emit sbToString(b)
}

// pluralizeN("mouse", "mice", 3) → "mice".
func pluralizeN(singular, plural, count) {
    if toInt(count) == 1 { emit singular }
    emit plural
}

// "1st", "2nd", "3rd", "11th", "21st", ...
func ordinal(n) {
    let v = toInt(n)
    let mod100 = v % 100
    let mod10 = v % 10
    let suf = "th"
    if mod100 < 11 || mod100 > 13 {
        if mod10 == 1 { suf = "st" }
        else if mod10 == 2 { suf = "nd" }
        else if mod10 == 3 { suf = "rd" }
    }
    let b = sbNew()
    b = sbAppend(b, v + "")
    b = sbAppend(b, suf)
    emit sbToString(b)
}

// ── Duration formatting ──────────────────────────────────────────────

// Format a duration in seconds as a compact "H:MM:SS" or "MM:SS".
func formatDuration(seconds) {
    let s = toInt(seconds)
    if s < 0 { s = 0 - s }
    let hours = s / 3600
    let mins = (s % 3600) / 60
    let secs = s % 60
    let b = sbNew()
    if hours > 0 {
        b = sbAppend(b, hours + "")
        b = sbAppend(b, ":")
        b = sbAppend(b, zeroPad(mins + "", 2))
    } else {
        b = sbAppend(b, mins + "")
    }
    b = sbAppend(b, ":")
    b = sbAppend(b, zeroPad(secs + "", 2))
    emit sbToString(b)
}

// Long-form duration: "1h 23m 45s", "45s", "5m 0s".
func formatDurationLong(seconds) {
    let s = toInt(seconds)
    if s < 0 { s = 0 - s }
    if s < 60 { emit s + "s" }
    let hours = s / 3600
    let mins = (s % 3600) / 60
    let secs = s % 60
    let b = sbNew()
    if hours > 0 {
        b = sbAppend(b, hours + "h ")
    }
    if hours > 0 || mins > 0 {
        b = sbAppend(b, mins + "m ")
    }
    b = sbAppend(b, secs + "s")
    emit sbToString(b)
}

// ── Hex / binary helpers ─────────────────────────────────────────────

// Format an int as a hex string with at least `width` digits, lowercase,
// no "0x" prefix. Use Krypton's `hex` builtin for raw conversion.
func formatHex(n, width) {
    let h = hex(toInt(n))
    while len(h) < width {
        let b = sbNew()
        b = sbAppend(b, "0")
        b = sbAppend(b, h)
        h = sbToString(b)
    }
    emit h
}
