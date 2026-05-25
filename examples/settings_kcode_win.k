// examples/settings_kcode_win.k — Krypton port of kcode-win/settings.py.
//
// Drop-in replacement for the persistent-settings + tool-resolution
// half of the IDE's Python helpers. The 100-line settings.py becomes
// roughly 50 lines of Krypton, with the same on-disk JSON format so
// existing %APPDATA%\kcode-win\settings.json files load unchanged.
//
// Compile & run:
//   kcc -r examples/settings_kcode_win.k
//
// Or import and call individual functions from another Krypton tool.

import "k:settings"

let APP_NAME = "kcode-win"

let TOOL_HINTS = "C:\\Users\\brian\\Documents\\GitHub\\krypton,C:\\Program Files\\Krypton,C:\\Program Files (x86)\\Krypton"

// Load the current settings file; returns "{}" if missing.
func loadSettings() {
    emit settingsLoad(APP_NAME)
}

// Persist a JSON string back to disk.
func saveSettings(jsonText) {
    emit settingsSave(APP_NAME, jsonText)
}

// Resolve kcc.exe — explicit path in settings wins, then dev/install dirs,
// finally PATH walk. Returns "" if not found.
func resolveKcc() {
    let s = loadSettings()
    let explicit = settingsGet(s, "kcc_path", "")
    emit findTool(explicit, "kcc.exe", TOOL_HINTS)
}

func resolveKls() {
    let s = loadSettings()
    let explicit = settingsGet(s, "kls_path", "")
    emit findTool(explicit, "kls.exe", TOOL_HINTS)
}

func resolveKbackend() {
    let s = loadSettings()
    let explicit = settingsGet(s, "kbackend_path", "")
    emit findTool(explicit, "kbackend.exe", TOOL_HINTS)
}

just run {
    let s = loadSettings()
    kp("config file: " + settingsDir(APP_NAME))
    kp("")
    kp("kcc       = " + resolveKcc())
    kp("kls       = " + resolveKls())
    kp("kbackend  = " + resolveKbackend())
    kp("")
    kp("font      = " + settingsGet(s, "font_family", "Consolas"))
    kp("font size = " + settingsGet(s, "font_size", "11"))
    kp("theme     = " + settingsGet(s, "theme", "system"))
}
