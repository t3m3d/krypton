import "head:windows"

func osver() {
    let regPath = "SOFTWARE\Microsoft\Windows NT\CurrentVersion"
    let build   = trim(regHklmStr(regPath, "CurrentBuildNumber"))
    let ed      = trim(regHklmStr(regPath, "EditionID"))
    if build == "" { emit "Windows" }
    let b = toInt(build)
    let v = "Windows"
    if b >= 26100 { v = "Windows 11" }
    else if b >= 22000 { v = "Windows 11" }
    else if b >= 19041 { v = "Windows 10" }
    else { v = "Windows (legacy)" }
    if ed == "Professional"            { ed = "Pro" }
    if ed == "Core"                    { ed = "Home" }
    if ed == "ProfessionalWorkstation" { ed = "Pro Workstation" }
    if ed == "IoTEnterprise"           { ed = "IoT Enterprise" }
    if ed == "ProfessionalN"           { ed = "Pro N" }
    if ed == "CoreN"                   { ed = "Home N" }
    if ed == "CoreSingleLanguage"      { ed = "Home SL" }
    if ed != "" { emit v + " " + ed + " (build " + build + ")" }
    emit v + " (build " + build + ")"
}

func uptime() {
    // 2.0: GetTickCount64 returns itoa'd string — no handleInt wrap needed.
    let ms   = GetTickCount64()
    let tsec = div64(ms, "1000")
    let mins = toInt(tsec) / 60
    let hrs  = mins / 60
    let days = hrs / 24
    let h    = hrs - (days * 24)
    let m    = mins - (hrs * 60)
    if days > 0 { emit days + " days, " + h + " hrs, " + m + " min" }
    else if hrs > 0 { emit h + " hrs, " + m + " min" }
    else { emit m + " min" }
}

func kfresolution() {
    let w = GetSystemMetrics("0")
    let h = GetSystemMetrics("1")
    if w == "0" { emit "unknown" }
    emit w + "x" + h
}

func kfterminal() {
    let wt = environ("WT_SESSION")
    if wt != "" { emit "Windows Terminal" }
    let ce = environ("ConEmuPID")
    if ce != "" { emit "ConEmu" }
    let al = environ("ALACRITTY_LOG")
    if al != "" { emit "Alacritty" }
    let tp = environ("TERM_PROGRAM")
    if tp != "" { emit tp }
    emit ""
}

func kftheme() {
    let regPath = "Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    let light  = regHkcuDword(regPath, "AppsUseLightTheme")
    let accent = toInt(regHkcuDword(regPath, "AccentColor"))
    let mode   = "Dark"
    if light != "0" { mode = "Light" }
    let r = accent - (accent / 256) * 256
    let g = accent / 256 - (accent / 65536) * 256
    let b = accent / 65536 - (accent / 16777216) * 256
    let hr = hex(r)
    let hg = hex(g)
    let hb = hex(b)
    if len(hr) < 2 { hr = "0" + hr }
    if len(hg) < 2 { hg = "0" + hg }
    if len(hb) < 2 { hb = "0" + hb }
    emit mode + " (#" + toUpper(hr) + toUpper(hg) + toUpper(hb) + ")"
}

func kfbattery() {
    let sps = structNew("SYSTEM_POWER_STATUS")
    GetSystemPowerStatus(sps)
    let pct = toInt(structGet(sps, "SYSTEM_POWER_STATUS", "BatteryLifePercent"))
    let ac  = structGet(sps, "SYSTEM_POWER_STATUS", "ACLineStatus")
    if pct == 255 { emit "" }
    let status = "discharging"
    if ac == "1" { status = "charging" }
    emit pct + "% (" + status + ")"
}

func sysuser() {
    let buf = bufNew("256")
    let sz  = bufNew("4")
    bufSetDword(sz, "256")
    GetUserNameA(buf, sz)
    emit bufStr(buf)
}

func syshost() {
    let buf = bufNew("256")
    let sz  = bufNew("4")
    bufSetDword(sz, "256")
    GetComputerNameA(buf, sz)
    emit bufStr(buf)
}

func sysarch() {
    let si   = structNew("SYSTEM_INFO")
    GetNativeSystemInfo(si)
    let arch = structGet(si, "SYSTEM_INFO", "wProcessorArchitecture")
    if arch == "9"  { emit "x86_64" }
    if arch == "5"  { emit "ARM" }
    if arch == "12" { emit "ARM64" }
    if arch == "6"  { emit "IA64" }
    emit "x86"
}
