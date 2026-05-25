// Round-trip + tool-resolution test for stdlib/settings.k — the
// Krypton equivalent of Python's kcode-win/settings.py.
import "k:settings"

just run {
    let app = "kr_settings_test"

    // Round-trip a config file
    let cfg = "{\"font\": \"Consolas\", \"size\": 11, \"theme\": \"dark\"}"
    if settingsSave(app, cfg) != "1" { kp("FAIL save"); exit("1") }
    let back = settingsLoad(app)
    if len(back) == 0 { kp("FAIL load"); exit("1") }

    // String key
    if settingsGet(back, "font", "?") != "Consolas" { kp("FAIL get font"); exit("1") }
    if settingsGet(back, "theme", "?") != "dark"     { kp("FAIL get theme"); exit("1") }

    // Numeric key (returned as string)
    if settingsGet(back, "size", "0") != "11"        { kp("FAIL get size"); exit("1") }
    if settingsGetInt(back, "size", 0) != 11         { kp("FAIL getInt"); exit("1") }

    // Missing key returns default
    if settingsGet(back, "missing", "DEF") != "DEF"  { kp("FAIL default"); exit("1") }

    // Tool resolution — find git on PATH (assume it's there in dev env)
    let git = findTool("", "git.exe", "")
    if len(git) == 0 { kp("WARN: git.exe not on PATH (skipping PATH-walk check)") }

    // Tool resolution — explicit hint dir
    let kcc = findTool("", "kcc.exe", "C:\\krypton")
    if len(kcc) == 0 { kp("FAIL findTool kcc hint"); exit("1") }

    // Settings dir derivation
    let dir = settingsDir(app)
    if len(dir) == 0 { kp("FAIL settingsDir"); exit("1") }

    kp("ok")
}
