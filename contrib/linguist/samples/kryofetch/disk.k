import "head:windows"

func driveinfo() {
    let drives = GetLogicalDrives()
    let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    let totalB  = structNew("ULARGE_INTEGER")
    let totalFB = structNew("ULARGE_INTEGER")
    let result  = ""
    let i = "0"
    while toInt(i) < 26 {
        let bit = bitShl("1", i)
        if bitAnd(drives, bit) != "0" {
            let letter = substring(letters, toInt(i), toInt(i) + 1)
            let root   = letter + ":\\"
            GetDiskFreeSpaceExA(root, toHandle("0"), totalB, totalFB)
            let totalGB = div64(structGet(totalB, "ULARGE_INTEGER", "QuadPart"), "1073741824")
            let freeGB  = div64(structGet(totalFB, "ULARGE_INTEGER", "QuadPart"), "1073741824")
            if toInt(totalGB) > 0 {
                let usedGB = toInt(totalGB) - toInt(freeGB) + ""
                let pct = toInt(usedGB) * 100 / toInt(totalGB) + ""
                let bar = rambar(usedGB, totalGB)
                let line = bar + "  " + root + " " + usedGB + "GB/" + totalGB + "GB " + pct + "%"
                if result != "" { result = result + "\n" }
                result = result + line
            }
        }
        i = toInt(i) + 1 + ""
    }
    emit result
}
