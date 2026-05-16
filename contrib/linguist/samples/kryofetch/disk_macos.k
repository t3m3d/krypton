import "utils_macos.k"

func driveinfo() {
    // Data volume = real user usage; externals must be >1 GB to skip virtual FSes
    let raw = exec("df -Pm 2>/dev/null | awk 'NR>1 && /^\\/dev\\// && ($6==\"/System/Volumes/Data\" || ($6~/^\\/Volumes\\// && $2+0>1000)) {print $2, $3, ($6==\"/System/Volumes/Data\" ? \"/\" : $6)}' | head -3")
    if raw == "" { emit "" }

    let result = ""
    let i = "0"
    while toInt(i) < 3 {
        let line = nthline(raw, i)
        if line != "" {
            let totalMB = firstpart(line, " ")
            let rest1   = afterpart(line, " ")
            let usedMB  = firstpart(rest1, " ")
            let mount   = afterpart(rest1, " ")
            if toInt(totalMB) > 0 {
                let totalGB = toInt(totalMB) / 1024
                let usedGB  = toInt(usedMB)  / 1024
                let bar     = rambar(usedMB, totalMB)
                let pct     = toInt(usedMB) * 100 / toInt(totalMB) + ""
                let entry   = bar + "  " + mount + " " + usedGB + "GB/" + totalGB + "GB " + pct + "%"
                if result != "" { result = result + "\n" }
                result = result + entry
            }
        }
        i = toInt(i) + 1 + ""
    }
    emit result
}
