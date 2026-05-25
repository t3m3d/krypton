// stdlib/settings.k — persistent app settings + tool path resolution.
//
// Replaces the Python `settings.py` pattern: a JSON file under
// %APPDATA%\<appName>\settings.json with load / save / get / set
// helpers and a `findTool` for resolving exe locations.
//
// Designed so a real-world IDE / tool config can live entirely in
// Krypton — no Python helper. Compatible on-disk format with
// Python's `json.dumps(d, indent=2)`, so existing Python-side
// configs are picked up unchanged.
//
// Public API:
//   settingsDir(appName)               → %APPDATA%\<appName>
//   settingsPath(appName, fileName)    → full path to a config file
//   settingsLoad(appName)              → raw JSON text from settings.json
//                                          ("{}" if missing/invalid)
//   settingsSave(appName, jsonText)    → mkdirs + writes settings.json
//                                          atomically via tmp-rename
//   settingsGet(jsonText, key, def)    → string lookup with default
//   settingsGetInt(jsonText, key, def) → integer-as-string with default
//   findTool(explicit, exeName, hintsCsv) → first existing path or ""
//
// Hints CSV is a comma-separated list of directories to search.
// findTool also walks PATH after the hints.

module settings

import "head:fileio"
import "head:windows"

// ── env / path helpers ───────────────────────────────────────────

func _settings_env(name) {
    // PATH can be very long on Windows (32k+); size accordingly. If even
    // 32k is too small, GetEnvironmentVariableA returns the required size,
    // and bufStr would read into uninitialized space — we'd rather return
    // nothing than corrupt the caller.
    let cap = 32768
    let buf = bufNew(cap)
    let n = GetEnvironmentVariableA(name, buf, cap + "")
    if n == "0" { emit "" }
    if toInt(n) >= cap { emit "" }
    emit bufStr(buf)
}

func _settings_tempdir() {
    let buf = bufNew(1024)
    let n = GetTempPathA("1024", buf)
    if n == "0" { emit "" }
    emit bufStr(buf)
}

func _settings_join(a, b) {
    if len(a) == 0 { emit b }
    if len(b) == 0 { emit a }
    let last = a[len(a) - 1]
    if last == "\\" { emit a + b }
    if last == "/"  { emit a + b }
    emit a + "\\" + b
}

func _settings_exists(path) {
    let a = GetFileAttributesA(path)
    if a == "4294967295" { emit "0" }
    if a == "-1" { emit "0" }
    emit "1"
}

func _settings_mkdir(path) {
    if _settings_exists(path) == "1" { emit "1" }
    emit CreateDirectoryA(path, toHandle("0"))
}

// ── directory + file path computation ────────────────────────────

func settingsDir(appName) {
    let appdata = _settings_env("APPDATA")
    if len(appdata) == 0 {
        // Fallback to %TEMP%
        emit _settings_join(_settings_tempdir(), appName)
    }
    emit _settings_join(appdata, appName)
}

func settingsPath(appName, fileName) {
    emit _settings_join(settingsDir(appName), fileName)
}

// ── load / save ─────────────────────────────────────────────────

// Returns raw JSON text; "{}" if missing or empty. Caller can pass
// through json_parse for structured access.
func settingsLoad(appName) {
    let p = settingsPath(appName, "settings.json")
    if _settings_exists(p) == "0" { emit "{}" }
    let txt = readFile(p)
    if len(txt) == 0 { emit "{}" }
    emit txt
}

// Persist JSON text. Creates %APPDATA%\<appName> if needed.
// Returns "1" on success, "0" on failure.
func settingsSave(appName, jsonText) {
    let dir = settingsDir(appName)
    _settings_mkdir(dir)
    let p = _settings_join(dir, "settings.json")
    writeFile(p, jsonText)
    if _settings_exists(p) == "1" { emit "1" }
    emit "0"
}

// ── shallow get with default ─────────────────────────────────────
// These avoid pulling in jpParse machinery for simple cases.
// They do a "good-enough" scan for `"key":` and grab the following
// string literal or numeric literal. Sufficient for flat config files.

func _settings_findKey(jsonText, key) {
    let needle = "\"" + key + "\""
    emit indexOf(jsonText, needle)
}

func settingsGet(jsonText, key, defaultVal) {
    let pos = _settings_findKey(jsonText, key)
    if pos < 0 { emit defaultVal }
    // walk past the key, colon, whitespace
    let i = pos + len(key) + 2   // skip "key"
    while i < len(jsonText) && jsonText[i] != ":" { i += 1 }
    if i >= len(jsonText) { emit defaultVal }
    i += 1
    while i < len(jsonText) && (jsonText[i] == " " || jsonText[i] == "\t" || jsonText[i] == "\n") { i += 1 }
    if i >= len(jsonText) { emit defaultVal }
    let c = jsonText[i]
    if c == "\"" {
        // string literal — read until closing quote, honoring \"
        let sb = sbNew()
        i += 1
        while i < len(jsonText) {
            let ch = jsonText[i]
            if ch == "\\" && i + 1 < len(jsonText) {
                let esc = jsonText[i + 1]
                if esc == "n" { sb = sbAppend(sb, fromCharCode("10")) }
                else { sb = sbAppend(sb, esc) }
                i += 2
            } else {
                if ch == "\"" { emit sbToString(sb) }
                sb = sbAppend(sb, ch)
                i += 1
            }
        }
        emit sbToString(sb)
    }
    // numeric / true / false / null — read until , } whitespace
    let sb2 = sbNew()
    while i < len(jsonText) {
        let ch2 = jsonText[i]
        if ch2 == "," || ch2 == "}" || ch2 == " " || ch2 == "\n" || ch2 == "\t" || ch2 == "]" { emit sbToString(sb2) }
        sb2 = sbAppend(sb2, ch2)
        i += 1
    }
    emit sbToString(sb2)
}

func settingsGetInt(jsonText, key, defaultInt) {
    let v = settingsGet(jsonText, key, defaultInt + "")
    if len(v) == 0 { emit defaultInt }
    emit toInt(v)
}

// ── tool resolution ──────────────────────────────────────────────
// findTool(explicit_path, exe_name, hints_csv)
//   - if explicit_path is given and exists, return its absolute form
//   - try each directory in hints_csv joined with exe_name
//   - finally walk %PATH%, semicolon-separated on Windows
// Returns "" if nothing found.

func findTool(explicitPath, exeName, hintsCsv) {
    if len(explicitPath) > 0 {
        if _settings_exists(explicitPath) == "1" { emit explicitPath }
    }
    let n = length(hintsCsv)
    let i = 0
    while i < n {
        let dir = split(hintsCsv, i + "")
        let cand = _settings_join(dir, exeName)
        if _settings_exists(cand) == "1" { emit cand }
        i += 1
    }
    let path = _settings_env("PATH")
    if len(path) > 0 {
        // Walk PATH manually; built-in `split` only handles comma.
        let pi = 0
        let start = 0
        while pi < len(path) {
            if path[pi] == ";" {
                let dir2 = substring(path, start, pi)
                if len(dir2) > 0 {
                    let cand2 = _settings_join(dir2, exeName)
                    if _settings_exists(cand2) == "1" { emit cand2 }
                }
                start = pi + 1
            }
            pi += 1
        }
        // Last segment (no trailing ;)
        if start < len(path) {
            let dirL = substring(path, start, len(path))
            let candL = _settings_join(dirL, exeName)
            if _settings_exists(candL) == "1" { emit candL }
        }
    }
    emit ""
}
