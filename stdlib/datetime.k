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
