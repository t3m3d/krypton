import "utils_macos.k"

func gpunames() {
    let raw = exec("system_profiler SPDisplaysDataType 2>/dev/null | grep 'Chipset Model:' | sed 's/.*Chipset Model: //'")
    if raw == "" { emit "Unknown GPU" }
    emit raw
}

func gpuvram() {
    // Discrete/eGPU Macs list VRAM (Total). Apple Silicon uses unified memory (no entry).
    let raw = exec("system_profiler SPDisplaysDataType 2>/dev/null | grep 'VRAM (Total):' | sed 's/.*VRAM (Total): //'")
    if raw == "" { emit "" }

    let result = ""
    let i = "0"
    let n = linecount(raw)
    while toInt(i) < toInt(n) {
        let line = nthline(raw, i)
        let val  = firstpart(line, " ")
        let unit = afterpart(line, " ")
        let mb   = toInt(val)
        if contains(unit, "GB") { mb = mb * 1024 }
        if mb > 0 {
            if result != "" { result = result + "\n" }
            result = result + mb + ":0"
        }
        i = toInt(i) + 1 + ""
    }
    emit result
}

func fmtgpu(name, vramLine) {
    if name == "" { emit "" }
    if vramLine == "" { emit name }
    let tb = firstpart(vramLine, ":")
    let ub = afterpart(vramLine, ":")
    if toInt(tb) == 0 { emit name }
    let n   = toInt(tb)
    let gb  = n / 1024
    let t   = n * 10 / 1024 - gb * 10
    if toInt(ub) > 0 {
        let un  = toInt(ub)
        let ugb = un / 1024
        let ut  = un * 10 / 1024 - ugb * 10
        let pct = un * 100 / n
        let bar = rambar(ub, tb)
        emit bar + "  " + name + "  " + ugb + "." + ut + " GB / " + gb + "." + t + " GB  " + pct + "%"
    }
    emit name + " (" + gb + "." + t + " GB VRAM)"
}
