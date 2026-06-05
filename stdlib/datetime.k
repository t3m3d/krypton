// Minimal date/time helpers. Closes the Python `datetime` /
// `time.time()` gap for the common cases (now-as-epoch, ISO 8601
// formatting, day arithmetic). Not a tz library — UTC only.
//
// IMPORTANT: cmd.exe's `date` is INTERACTIVE (prompts for input);
// don't shell out to bare `date` from a Win32 process. We use
// PowerShell on Windows (always present in Win10+) and POSIX `date`
// when invoked from a true POSIX shell.
module datetime

// True if s starts with a digit — used to reject cmd.exe's
// "The system cannot accept the date entered." prompts.
func _dt_isDigitStr(s) {
    if len(s) == 0 { emit "0" }
    if s[0] >= "0" && s[0] <= "9" { emit "1" }
    emit "0"
}

// Current UNIX epoch seconds as a string. "" on failure.
func dtNowEpoch() {
    let p = trim(exec("powershell -NoProfile -Command \"[int64][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()\""))
    if _dt_isDigitStr(p) == "1" { emit p }
    // POSIX fallback (Git Bash, macOS, Linux).
    let s = trim(exec("date +%s"))
    if _dt_isDigitStr(s) == "1" { emit s }
    emit ""
}

// Today's date as "YYYY-MM-DD" (UTC). Empty on failure.
func dtToday() {
    let p = trim(exec("powershell -NoProfile -Command \"(Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')\""))
    if _dt_isDigitStr(p) == "1" { emit p }
    let s = trim(exec("date -u +%Y-%m-%d"))
    if _dt_isDigitStr(s) == "1" { emit s }
    emit ""
}

// ISO 8601 timestamp for now (UTC): "YYYY-MM-DDTHH:MM:SSZ".
func dtNowIso() {
    let p = trim(exec("powershell -NoProfile -Command \"(Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')\""))
    if _dt_isDigitStr(p) == "1" { emit p }
    let s = trim(exec("date -u +%Y-%m-%dT%H:%M:%SZ"))
    if _dt_isDigitStr(s) == "1" { emit s }
    emit ""
}

// HTTP-date header format per RFC 7231:
//   "Sun, 06 Nov 1994 08:49:37 GMT"
// Useful when emitting Last-Modified / Date / Expires from k:server.
func dtHttpDate() {
    let p = trim(exec("powershell -NoProfile -Command \"(Get-Date).ToUniversalTime().ToString('R')\""))
    // R format starts with day-name letter (Mon/Tue/...), not a digit.
    if len(p) > 0 && p[0] >= "A" && p[0] <= "Z" { emit p }
    let s = trim(exec("date -u +\"%a, %d %b %Y %H:%M:%S GMT\""))
    if len(s) > 0 && s[0] >= "A" && s[0] <= "Z" { emit s }
    emit ""
}

// Pure arithmetic — no syscall. Handles negative deltas.
//   dtAddSeconds("1700000000", "3600") → "1700003600"
func dtAddSeconds(epoch, deltaSec) {
    if len(epoch) == 0 { emit "" }
    emit (toInt(epoch) + toInt(deltaSec)) + ""
}

func dtAddMinutes(epoch, deltaMin) { emit dtAddSeconds(epoch, (toInt(deltaMin) * 60) + "") }
func dtAddHours(epoch, deltaHr)    { emit dtAddSeconds(epoch, (toInt(deltaHr) * 3600) + "") }
func dtAddDays(epoch, deltaDays)   { emit dtAddSeconds(epoch, (toInt(deltaDays) * 86400) + "") }

// Time delta between two epochs (b - a), in seconds.
func dtDiffSeconds(a, b) {
    emit (toInt(b) - toInt(a)) + ""
}

// ── Pure epoch math: extract components without shelling out ──────────
//
// All functions below take or return Krypton int strings ("1700000000").
// Epoch is UNIX time (seconds since 1970-01-01 00:00:00 UTC).
// No timezone — UTC throughout.

// Get the Nth comma-separated field from a CSV string (0-indexed).
func _dt_nth(csv, idx) {
    let want = toInt(idx)
    let n = len(csv)
    let cur = 0
    let start = 0
    let i = 0
    while i <= n {
        if i == n || csv[i] == "," {
            if cur == want { emit substring(csv, start, i) }
            cur = cur + 1
            start = i + 1
        }
        i = i + 1
    }
    emit ""
}

func dtIsLeap(year) {
    let y = toInt(year)
    if y % 4 != 0 { emit "0" }
    if y % 100 != 0 { emit "1" }
    if y % 400 != 0 { emit "0" }
    emit "1"
}

func dtDaysInMonth(year, month) {
    let m = toInt(month)
    if m == 1 || m == 3 || m == 5 || m == 7 || m == 8 || m == 10 || m == 12 { emit "31" }
    if m == 4 || m == 6 || m == 9 || m == 11 { emit "30" }
    if dtIsLeap(year) == "1" { emit "29" }
    emit "28"
}

// Total days in the given year (365 or 366).
func dtDaysInYear(year) {
    if dtIsLeap(year) == "1" { emit "366" }
    emit "365"
}

// Internal: epoch → CSV "year,month,day,hour,minute,second,weekday".
// weekday is 0=Mon..6=Sun (ISO 8601).
func _dt_split(epoch) {
    let e = toInt(epoch)
    if e < 0 { emit "" }

    let secOfDay = e % 86400
    let dayNum = (e - secOfDay) / 86400        // days since 1970-01-01
    let hour = secOfDay / 3600
    let rem = secOfDay - (hour * 3600)
    let minute = rem / 60
    let second = rem - (minute * 60)

    // 1970-01-01 was a Thursday. ISO Mon=0 → Thu=3.
    let weekday = (dayNum + 3) % 7

    // Walk forward year-by-year until dayNum lives within `year`.
    let year = 1970
    let dy = dtDaysInYear(year + "")
    while dayNum >= toInt(dy) {
        dayNum = dayNum - toInt(dy)
        year = year + 1
        dy = dtDaysInYear(year + "")
    }

    // Walk month-by-month.
    let month = 1
    let dm = dtDaysInMonth(year + "", month + "")
    while dayNum >= toInt(dm) {
        dayNum = dayNum - toInt(dm)
        month = month + 1
        dm = dtDaysInMonth(year + "", month + "")
    }

    let day = dayNum + 1   // day-of-month is 1-indexed

    emit year + "," + month + "," + day + "," + hour + "," + minute + "," + second + "," + weekday
}

// Component extractors. Return "" on bad input.
func dtYear(epoch) {
    let s = _dt_split(epoch)
    if len(s) == 0 { emit "" }
    emit _dt_nth(s, "0")
}
func dtMonth(epoch) {
    let s = _dt_split(epoch)
    if len(s) == 0 { emit "" }
    emit _dt_nth(s, "1")
}
func dtDay(epoch) {
    let s = _dt_split(epoch)
    if len(s) == 0 { emit "" }
    emit _dt_nth(s, "2")
}
func dtHour(epoch) {
    let s = _dt_split(epoch)
    if len(s) == 0 { emit "" }
    emit _dt_nth(s, "3")
}
func dtMinute(epoch) {
    let s = _dt_split(epoch)
    if len(s) == 0 { emit "" }
    emit _dt_nth(s, "4")
}
func dtSecond(epoch) {
    let s = _dt_split(epoch)
    if len(s) == 0 { emit "" }
    emit _dt_nth(s, "5")
}

// Weekday: 0=Mon, 6=Sun (ISO 8601). "" on bad input.
func dtWeekday(epoch) {
    let s = _dt_split(epoch)
    if len(s) == 0 { emit "" }
    emit _dt_nth(s, "6")
}

// Short weekday name: "Mon".."Sun".
func dtWeekdayName(epoch) {
    let w = dtWeekday(epoch)
    if len(w) == 0 { emit "" }
    let names = "Mon,Tue,Wed,Thu,Fri,Sat,Sun"
    emit _dt_nth(names, w)
}

// Short month name from 1-based month: "Jan".."Dec".
func dtMonthName(epoch) {
    let m = dtMonth(epoch)
    if len(m) == 0 { emit "" }
    let names = "Jan,Feb,Mar,Apr,May,Jun,Jul,Aug,Sep,Oct,Nov,Dec"
    emit _dt_nth(names, (toInt(m) - 1) + "")
}

// Pad a number with leading zeros — built via sbAppend because
// Krypton's `"0" + s` is auto-coerced to int addition (known kr_plus
// bug), so it would silently truncate "05" back to "5".
func _dt_pad2(n) {
    let s = n + ""
    if len(s) >= 2 { emit s }
    let b = sbNew()
    b = sbAppend(b, "0")
    b = sbAppend(b, s)
    emit sbToString(b)
}
func _dt_pad4(n) {
    let s = n + ""
    while len(s) < 4 {
        let b = sbNew()
        b = sbAppend(b, "0")
        b = sbAppend(b, s)
        s = sbToString(b)
    }
    emit s
}

// Format an epoch as ISO 8601: "YYYY-MM-DDTHH:MM:SSZ". Pure math, no shell.
func dtIsoFromEpoch(epoch) {
    let s = _dt_split(epoch)
    if len(s) == 0 { emit "" }
    let y = _dt_pad4(_dt_nth(s, "0"))
    let mo = _dt_pad2(_dt_nth(s, "1"))
    let d = _dt_pad2(_dt_nth(s, "2"))
    let h = _dt_pad2(_dt_nth(s, "3"))
    let mi = _dt_pad2(_dt_nth(s, "4"))
    let se = _dt_pad2(_dt_nth(s, "5"))
    emit y + "-" + mo + "-" + d + "T" + h + ":" + mi + ":" + se + "Z"
}

// "YYYY-MM-DD" from an epoch — handy for log filenames + bucket keys.
func dtDateFromEpoch(epoch) {
    let s = _dt_split(epoch)
    if len(s) == 0 { emit "" }
    let y = _dt_pad4(_dt_nth(s, "0"))
    let mo = _dt_pad2(_dt_nth(s, "1"))
    let d = _dt_pad2(_dt_nth(s, "2"))
    emit y + "-" + mo + "-" + d
}

// Build an epoch from year/month/day/hour/minute/second (UTC).
//   dtFromYMDHMS("2026", "6", "4", "22", "30", "0") → "1780014600"
func dtFromYMDHMS(year, month, day, hour, minute, second) {
    let y = toInt(year)
    let m = toInt(month)
    let d = toInt(day)
    if y < 1970 || m < 1 || m > 12 || d < 1 { emit "" }

    // Days from 1970-01-01 to the 1st of (y, m).
    let days = 0
    let yi = 1970
    while yi < y {
        days = days + toInt(dtDaysInYear(yi + ""))
        yi = yi + 1
    }
    let mi = 1
    while mi < m {
        days = days + toInt(dtDaysInMonth(y + "", mi + ""))
        mi = mi + 1
    }
    days = days + (d - 1)

    let secs = (days * 86400) + (toInt(hour) * 3600) + (toInt(minute) * 60) + toInt(second)
    emit secs + ""
}

// Parse "YYYY-MM-DDTHH:MM:SSZ" or "YYYY-MM-DD HH:MM:SS" → epoch.
// Returns "" on malformed input. Z / no-Z both accepted (UTC assumed).
func dtParseIso(s) {
    if len(s) < 19 { emit "" }
    let y = substring(s, 0, 4)
    let mo = substring(s, 5, 7)
    let d = substring(s, 8, 10)
    let h = substring(s, 11, 13)
    let mi = substring(s, 14, 16)
    let se = substring(s, 17, 19)
    emit dtFromYMDHMS(y, mo, d, h, mi, se)
}

// Whole days between two epoch values (b - a).
func dtDiffDays(a, b) {
    let d = toInt(b) - toInt(a)
    emit (d / 86400) + ""
}

// Epoch for start of the UTC day that `epoch` falls in.
func dtStartOfDay(epoch) {
    let e = toInt(epoch)
    emit (e - (e % 86400)) + ""
}
