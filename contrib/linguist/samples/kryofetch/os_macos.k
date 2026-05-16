import "utils_macos.k"

func osver() {
    let v     = exec("sw_vers -productVersion 2>/dev/null")
    let build = exec("sw_vers -buildVersion 2>/dev/null")
    if v == "" { emit "macOS" }
    let major = firstpart(v, ".")
    let name  = ""
    if major == "26" { name = "Tahoe" }
    if major == "15" { name = "Sequoia" }
    if major == "14" { name = "Sonoma" }
    if major == "13" { name = "Ventura" }
    if major == "12" { name = "Monterey" }
    if major == "11" { name = "Big Sur" }
    if name == "" { emit "macOS " + v + " (" + build + ")" }
    emit "macOS " + name + " " + v + " (" + build + ")"
}

func uptime() {
    let out = exec("uptime | sed 's/.*up //' | sed 's/, *[0-9]* *user.*//'")
    if out == "" { emit "unknown" }
    emit trim(out)
}

func kfresolution() {
    let res = exec("system_profiler SPDisplaysDataType 2>/dev/null | grep 'Resolution:' | head -1 | sed 's/.*Resolution: //' | sed 's/ @ .*//'")
    if res == "" { emit "unknown" }
    emit trim(res)
}

func kfterminal() {
    let tp = environ("TERM_PROGRAM")
    if tp != "" { emit tp }
    emit ""
}

func kftheme() {
    let style = exec("defaults read -g AppleInterfaceStyle 2>/dev/null")
    if style == "Dark" { emit "Dark" }
    emit "Light"
}

func kfbattraw() {
    let raw = exec("ioreg -r -n AppleSmartBattery 2>/dev/null | awk '/\"DeviceName\"/{gsub(/.*= \"/,\"\");gsub(/\".*/,\"\");chip=$0} /\"CurrentCapacity\" =/{pct=$NF} /\"TimeRemaining\" =/{mins=$NF} /\"IsCharging\" =/{chrg=$NF} /\"FullyCharged\" =/{full=$NF} END{print chip;print pct;print mins;print chrg;print full}'")
    emit raw
}

func kfkernel() {
    let k = exec("uname -sr 2>/dev/null")
    if k == "" { emit "unknown" }
    emit trim(k)
}

func sysmodel() {
    let mid = trim(exec("sysctl -n hw.model 2>/dev/null"))
    // M1
    if mid == "MacBookAir10,1"  { emit "MacBook Air (M1, 2020)" }
    if mid == "MacBookPro17,1"  { emit "MacBook Pro (13-inch, M1, 2020)" }
    if mid == "Macmini9,1"      { emit "Mac mini (M1, 2020)" }
    if mid == "iMac21,1"        { emit "iMac (24-inch, M1, 2021)" }
    if mid == "iMac21,2"        { emit "iMac (24-inch, M1, 2021)" }
    if mid == "MacBookPro18,1"  { emit "MacBook Pro (16-inch, M1 Pro, 2021)" }
    if mid == "MacBookPro18,2"  { emit "MacBook Pro (16-inch, M1 Max, 2021)" }
    if mid == "MacBookPro18,3"  { emit "MacBook Pro (14-inch, M1 Pro, 2021)" }
    if mid == "MacBookPro18,4"  { emit "MacBook Pro (14-inch, M1 Max, 2021)" }
    if mid == "Mac13,1"         { emit "Mac Studio (M1 Max, 2022)" }
    if mid == "Mac13,2"         { emit "Mac Studio (M1 Ultra, 2022)" }
    // M2
    if mid == "Mac14,2"         { emit "MacBook Air (M2, 2022)" }
    if mid == "Mac14,7"         { emit "MacBook Pro (13-inch, M2, 2022)" }
    if mid == "Mac14,3"         { emit "Mac mini (M2, 2023)" }
    if mid == "Mac14,12"        { emit "Mac mini (M2 Pro, 2023)" }
    if mid == "Mac14,5"         { emit "MacBook Pro (14-inch, M2 Max, 2023)" }
    if mid == "Mac14,6"         { emit "MacBook Pro (16-inch, M2 Max, 2023)" }
    if mid == "Mac14,9"         { emit "MacBook Pro (14-inch, M2 Pro, 2023)" }
    if mid == "Mac14,10"        { emit "MacBook Pro (16-inch, M2 Pro, 2023)" }
    if mid == "Mac14,8"         { emit "Mac Pro (M2 Ultra, 2023)" }
    if mid == "Mac14,13"        { emit "Mac Studio (M2 Max, 2023)" }
    if mid == "Mac14,14"        { emit "Mac Studio (M2 Ultra, 2023)" }
    if mid == "Mac14,15"        { emit "MacBook Air (15-inch, M2, 2023)" }
    // M3
    if mid == "Mac15,3"         { emit "MacBook Pro (14-inch, M3, 2023)" }
    if mid == "Mac15,6"         { emit "MacBook Pro (14-inch, M3 Pro, 2023)" }
    if mid == "Mac15,7"         { emit "MacBook Pro (14-inch, M3 Max, 2023)" }
    if mid == "Mac15,9"         { emit "MacBook Pro (14-inch, M3 Pro, 2023)" }
    if mid == "Mac15,8"         { emit "MacBook Pro (16-inch, M3 Pro, 2023)" }
    if mid == "Mac15,10"        { emit "MacBook Pro (16-inch, M3 Pro, 2023)" }
    if mid == "Mac15,11"        { emit "MacBook Pro (16-inch, M3 Max, 2023)" }
    if mid == "Mac15,4"         { emit "iMac (24-inch, M3, 2023)" }
    if mid == "Mac15,5"         { emit "iMac (24-inch, M3, 2023)" }
    if mid == "Mac15,12"        { emit "MacBook Air (15-inch, M3, 2024)" }
    if mid == "Mac15,13"        { emit "MacBook Air (13-inch, M3, 2024)" }
    // M4
    if mid == "Mac16,1"         { emit "MacBook Pro (14-inch, M4, 2024)" }
    if mid == "Mac16,5"         { emit "MacBook Pro (16-inch, M4 Pro, 2024)" }
    if mid == "Mac16,6"         { emit "MacBook Pro (14-inch, M4 Pro, 2024)" }
    if mid == "Mac16,7"         { emit "MacBook Pro (14-inch, M4 Max, 2024)" }
    if mid == "Mac16,8"         { emit "MacBook Pro (16-inch, M4 Max, 2024)" }
    if mid == "Mac16,10"        { emit "iMac (24-inch, M4, 2024)" }
    if mid == "Mac16,11"        { emit "Mac mini (M4, 2024)" }
    if mid == "Mac16,15"        { emit "Mac mini (M4 Pro, 2024)" }
    if mid == "Mac16,12"        { emit "MacBook Air (13-inch, M4, 2025)" }
    if mid == "Mac16,13"        { emit "MacBook Air (15-inch, M4, 2025)" }
    if mid == "Mac16,14"        { emit "Mac Studio (M4 Max, 2025)" }
    if mid == "Mac16,16"        { emit "Mac Studio (M4 Ultra, 2025)" }
    // fallback to machine name
    let name = exec("system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Model Name/{print $2}'")
    if name != "" { emit trim(name) }
    emit "unknown"
}

func kftermfont() {
    let tp = environ("TERM_PROGRAM")
    if tp == "iTerm.app" {
        let f = trim(exec("defaults read com.googlecode.iterm2 \"Normal Font\" 2>/dev/null | awk '{n=split($0,a,\" \");sz=a[n];nm=\"\";for(i=1;i<n;i++){nm=nm a[i]\" \"};gsub(/-Regular|-Bold|-Light|-Medium|-Thin|-ExtraLight|-SemiBold/,\"\",nm);gsub(/^ | $/,\"\",nm);print nm \" (\" sz \"pt)\"}'"))
        if f != "" { emit f }
    }
    emit ""
}

func kfdisplayinfo() {
    let raw = exec("system_profiler SPDisplaysDataType -json 2>/dev/null | python3 -c \"import sys,json;d=json.load(sys.stdin);[print(a.get('_name','')+'|'+a.get('_spdisplays_pixels','').replace(' x ','x')+'|'+(a.get('_spdisplays_resolution','').split('@')[1].strip().rstrip('Hz').split('.')[0]+'Hz' if '@' in a.get('_spdisplays_resolution','') else '')+'|'+('Built-in' if 'internal' in a.get('spdisplays_connection_type','') else 'External')+'|'+('2x' if 'Retina' in a.get('spdisplays_pixelresolution','') else '1x')) for arr in d.get('SPDisplaysDataType',[]) for a in arr.get('spdisplays_ndrvs',[])]\" 2>/dev/null | head -1")
    if raw == "" { emit "" }
    emit trim(raw)
}

func kfwmver() {
    let v = trim(exec("defaults read /System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/Resources/version.plist CFBundleShortVersionString 2>/dev/null"))
    if v == "" { emit "Quartz Compositor" }
    emit "Quartz Compositor " + v
}

func kfaccent() {
    let ac = trim(exec("defaults read -g AppleAccentColor 2>/dev/null"))
    let name = "Multicolor"
    if ac == "-1" { name = "Graphite" }
    if ac == "0"  { name = "Red" }
    if ac == "1"  { name = "Orange" }
    if ac == "2"  { name = "Yellow" }
    if ac == "3"  { name = "Green" }
    if ac == "4"  { name = "Blue" }
    if ac == "5"  { name = "Purple" }
    if ac == "6"  { name = "Pink" }
    let style = trim(exec("defaults read -g AppleInterfaceStyle 2>/dev/null"))
    if style == "" { style = "Light" }
    emit name + " (" + style + ")"
}

func kfthemename() {
    let v = exec("sw_vers -productVersion 2>/dev/null")
    let major = firstpart(v, ".")
    if toInt(major) >= 26 { emit "Liquid Glass" }
    emit "Aqua"
}

func kflocalip() {
    let ip = exec("ifconfig en0 2>/dev/null | awk 'BEGIN{b[\"0\"]=0;b[\"1\"]=1;b[\"2\"]=1;b[\"3\"]=2;b[\"4\"]=1;b[\"5\"]=2;b[\"6\"]=2;b[\"7\"]=3;b[\"8\"]=1;b[\"9\"]=2;b[\"a\"]=2;b[\"b\"]=3;b[\"c\"]=2;b[\"d\"]=3;b[\"e\"]=3;b[\"f\"]=4} /inet /{ip=$2;hex=$4;sub(/0x/,\"\",hex);bits=0;for(i=1;i<=8;i++)bits+=b[tolower(substr(hex,i,1))];print ip\"/\"bits}'")
    if ip == "" { emit "" }
    emit trim(ip)
}

func sysuser() {
    let u = environ("USER")
    if u != "" { emit u }
    emit exec("whoami")
}

func syshost() {
    let h = exec("hostname -s 2>/dev/null")
    if h == "" { emit "localhost" }
    emit h
}

func sysarch() {
    let a = exec("uname -m")
    if a == "arm64"  { emit "arm64" }
    if a == "x86_64" { emit "x86_64" }
    if a == "" { emit "unknown" }
    emit a
}
