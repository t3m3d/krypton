import "utils_macos.k"

func cpubrand() {
    let brand = exec("sysctl -n machdep.cpu.brand_string 2>/dev/null")
    if brand != "" { emit brand }
    // Apple Silicon doesn't expose brand_string; use hw.chip_model (Tahoe+) or hw.model
    let chip = exec("sysctl -n hw.chip_model 2>/dev/null")
    if chip != "" { emit chip }
    let model = exec("sysctl -n hw.model 2>/dev/null")
    if model != "" { emit model }
    emit "Unknown CPU"
}

func cpucores() {
    let phys = exec("sysctl -n hw.physicalcpu 2>/dev/null")
    let logi = exec("sysctl -n hw.logicalcpu 2>/dev/null")
    if phys == "" { phys = "0" }
    if logi == "" { logi = phys }
    emit phys + "," + logi
}
