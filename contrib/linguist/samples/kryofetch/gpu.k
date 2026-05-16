// Filter helpers — drop garbage / virtual entries from the GPU list.

func _gpu_isPrintable(s) {
    let i = "0"
    while toInt(i) < len(s) {
        let n = toInt(charCode(substring(s, toInt(i), toInt(i) + 1)))
        if n < 32 { emit "0" }
        if n > 126 { emit "0" }
        i = toInt(i) + 1 + ""
    }
    emit "1"
}

func _gpu_isVirtual(name) {
    let low = toLower(name)
    if contains(low, "microsoft basic display") { emit "1" }
    if contains(low, "remote display")          { emit "1" }
    if contains(low, "rdp ")                    { emit "1" }
    if contains(low, "citrix")                  { emit "1" }
    if contains(low, "hyper-v")                 { emit "1" }
    if contains(low, "hyperv")                  { emit "1" }
    if contains(low, "vmware")                  { emit "1" }
    if contains(low, "virtualbox")              { emit "1" }
    if contains(low, "parallels")               { emit "1" }
    if contains(low, "displaylink")             { emit "1" }
    if contains(low, "vgpu")                    { emit "1" }
    emit "0"
}

// gpunames: enumerate GPU names from registry (no WMI/powershell).
// 2.0: phResult = bufNew(8), bufGetQword extracts HKEY. NULL ptr args use
// toHandle("0"). RegEnumKeyExA returns marshalled int-string. Filters out
// virtual / mirror / RDP adapters and entries with non-printable bytes
// (registry sometimes returns garbage for second-slot adapters with no
// real DriverDesc).
func gpunames() {
    let regBase  = "SYSTEM\\CurrentControlSet\\Control\\Video"
    let HKLM     = "2147483650"
    let kread    = "131097"
    let phResult = bufNew("8")
    let openR = RegOpenKeyExA(HKLM, regBase, "0", kread, phResult)
    if openR != "0" { emit "Unknown GPU" }
    let hb = bufGetQword(phResult)
    let result  = ""
    let subBuf  = bufNew("256")
    let subSz   = bufNew("4")
    let idx = "0"
    while toInt(idx) < 16 {
        bufSetDword(subSz, "256")
        let enumRet = RegEnumKeyExA(hb, idx, subBuf, subSz, toHandle("0"), toHandle("0"), toHandle("0"), toHandle("0"))
        if enumRet != "0" { break }
        let sub = bufStr(subBuf)
        let devPath = regBase + "\\" + sub + "\\0000"
        let gpuName = trim(regHklmStr(devPath, "DriverDesc"))
        if gpuName != "" {
            if _gpu_isPrintable(gpuName) == "1" {
                if _gpu_isVirtual(gpuName) == "0" {
                    if result != "" { result = result + "\n" }
                    result = result + gpuName
                }
            }
        }
        idx = toInt(idx) + 1 + ""
    }
    RegCloseKey(hb)
    if result == "" { emit "Unknown GPU" }
    emit result
}

func kfvramreg() {
    let regBase  = "SYSTEM\\CurrentControlSet\\Control\\Video"
    let HKLM     = "2147483650"
    let kread    = "131097"
    let phResult = bufNew("8")
    let openR = RegOpenKeyExA(HKLM, regBase, "0", kread, phResult)
    if openR != "0" { emit "" }
    let hb = bufGetQword(phResult)
    let result = ""
    let cnt    = "0"
    let subBuf = bufNew("256")
    let subSz  = bufNew("4")
    let idx    = "0"
    while toInt(idx) < 16 {
        if toInt(cnt) >= 2 { break }
        bufSetDword(subSz, "256")
        let enumRet = RegEnumKeyExA(hb, idx, subBuf, subSz, toHandle("0"), toHandle("0"), toHandle("0"), toHandle("0"))
        if enumRet != "0" { break }
        let sub     = bufStr(subBuf)
        let devPath = regBase + "\\" + sub + "\\0000"
        let mem     = regHklmQword(devPath, "HardwareInformation.qwMemorySize")
        if mem == "0" { mem = regHklmDword(devPath, "HardwareInformation.MemorySize") }
        if mem == "0" { mem = regHklmDword(devPath, "HardwareInformation.MemorySizeLegacy") }
        if mem != "0" {
            let mb = div64(mem, "1048576")
            if result != "" { result = result + "\n" }
            result = result + mb + ":0"
            cnt = toInt(cnt) + 1 + ""
        }
        idx = toInt(idx) + 1 + ""
    }
    RegCloseKey(hb)
    emit result
}

func kfpdhgpu() {
    let hQ  = handleOut()
    let ret = handleInt(PdhOpenQueryA(toHandle("0"), toHandle("0"), hQ))
    if toInt(ret) != 0 { emit "0" }
    let q   = handleGet(hQ)
    let hC   = handleOut()
    let ret2 = handleInt(PdhAddEnglishCounterA(q, "\\GPU Adapter Memory(*)\\Dedicated Usage", toHandle("0"), hC))
    if toInt(ret2) != 0 {
        ret2 = handleInt(PdhAddEnglishCounterA(q, "\\GPU Local Adapter Memory(*)\\Local Usage", toHandle("0"), hC))
    }
    if toInt(ret2) != 0 {
        PdhCloseQuery(q)
        emit "0"
    }
    let c = handleGet(hC)
    PdhCollectQueryData(q)
    PdhCollectQueryData(q)
    let szBuf  = bufNew("4")
    let cntBuf = bufNew("4")
    bufSetDword(szBuf, "0")
    bufSetDword(cntBuf, "0")
    PdhGetFormattedCounterArrayA(c, toHandle("1024"), szBuf, cntBuf, toHandle("0"))
    let sz  = bufGetDword(szBuf)
    let cnt = bufGetDword(cntBuf)
    if toInt(sz) == 0 {
        bufSetDword(szBuf, "0")
        bufSetDword(cntBuf, "0")
        PdhGetFormattedCounterArrayA(c, toHandle("512"), szBuf, cntBuf, toHandle("0"))
        sz  = bufGetDword(szBuf)
        cnt = bufGetDword(cntBuf)
    }
    if toInt(sz) == 0 {
        PdhCloseQuery(q)
        emit "0"
    }
    let items = bufNew(sz)
    let fmt   = "1024"
    if toInt(cnt) == 0 { fmt = "512" }
    PdhGetFormattedCounterArrayA(c, toHandle(fmt), szBuf, cntBuf, items)
    let used = "0"
    let i = "0"
    while toInt(i) < toInt(cnt) {
        let off    = toInt(i) * 24
        let status = bufGetDwordAt(items, off + 8)
        let ok = "0"
        if toInt(status) >= 0 { ok = "1" }
        if ok == "1" {
            let valMB = div64(bufGetQwordAt(items, off + 16), "1048576")
            used = toInt(used) + toInt(valMB) + ""
        }
        i = toInt(i) + 1 + ""
    }
    PdhCloseQuery(q)
    emit used
}

func kfdxgivram() {
    let guid = bufNew("16")
    bufSetDwordAt(guid, "0",  "2071029484")   // 0x7B7166EC
    bufSetDwordAt(guid, "4",  "1152262599")   // 0x44AE21C7
    bufSetDwordAt(guid, "8",  "-1362552142")   // 0xAEC91AB2
    bufSetDwordAt(guid, "12", "1776491058")   // 0x69E31A32

    let hD = LoadLibraryA("dxgi.dll")
    if handleValid(hD) == "0" { emit "" }

    let pC = GetProcAddress(hD, "CreateDXGIFactory")
    if handleValid(pC) == "0" {
        FreeLibrary(hD)
        emit ""
    }

    let pFOut = handleOut()
    let hr1   = callPtr(pC, guid, pFOut)
    let pF    = handleGet(pFOut)
    if toInt(handleInt(hr1)) < 0 {
        FreeLibrary(hD)
        emit ""
    }
    if handleValid(pF) == "0" {
        FreeLibrary(hD)
        emit ""
    }

    let fv  = ptrDeref(pF)
    let pE  = ptrIndex(fv, "7")
    let pFR = ptrIndex(fv, "2")

    let result = ""
    let cnt    = "0"
    let i      = "0"
    while toInt(cnt) < 2 {
        let pAOut = handleOut()
        let hr2   = callPtr(pE, pF, toHandle(i), pAOut)
        if toInt(handleInt(hr2)) < 0 { break }
        let pA = handleGet(pAOut)
        if handleValid(pA) == "0" { break }

        let av  = ptrDeref(pA)
        let pG  = ptrIndex(av, "8")
        let pAR = ptrIndex(av, "2")

        let desc = bufNew("304")
        callPtr(pG, pA, desc)
        let vram = bufGetQwordAt(desc, "272")
        if vram != "0" {
            let mb = div64(vram, "1048576")
            if result != "" { result = result + "\n" }
            result = result + mb
            cnt = toInt(cnt) + 1 + ""
        }
        callPtr(pAR, pA)
        i = toInt(i) + 1 + ""
    }
    callPtr(pFR, pF)
    FreeLibrary(hD)
    emit result
}

func kfdxgibudget() {
    let hD = LoadLibraryA("dxgi.dll")
    if handleValid(hD) == "0" { emit "0" }
    let pC = GetProcAddress(hD, "CreateDXGIFactory1")
    if handleValid(pC) == "0" { FreeLibrary(hD)  emit "0" }
    let g1 = bufNew("16")
    bufSetDwordAt(g1, "0",  "1997188728")
    bufSetDwordAt(g1, "4",  "1304097391")
    bufSetDwordAt(g1, "8",  "1009068456")
    bufSetDwordAt(g1, "12", "-2018258557")
    let pFOut = handleOut()
    let hr1 = callPtr(pC, g1, pFOut)
    if toInt(handleInt(hr1)) < 0 { FreeLibrary(hD)  emit "0" }
    let pF = handleGet(pFOut)
    if handleValid(pF) == "0" { FreeLibrary(hD)  emit "0" }
    let fv  = ptrDeref(pF)
    let pE1 = ptrIndex(fv, "12")
    let pFR = ptrIndex(fv, "2")
    let g3 = bufNew("16")
    bufSetDwordAt(g3, "0",  "1683580836")
    bufSetDwordAt(g3, "4",  "1125127058")
    bufSetDwordAt(g3, "8",  "1400936615")
    bufSetDwordAt(g3, "12", "-40681778")
    let result = "0"
    let pA1Out = handleOut()
    let hr2 = callPtr(pE1, pF, toHandle("0"), pA1Out)
    if toInt(handleInt(hr2)) >= 0 {
        let pA1 = handleGet(pA1Out)
        if handleValid(pA1) != "0" {
            let av1  = ptrDeref(pA1)
            let pQI  = ptrIndex(av1, "0")
            let pA1R = ptrIndex(av1, "2")
            let pA3Out = handleOut()
            let hr3 = callPtr(pQI, pA1, g3, pA3Out)
            if toInt(handleInt(hr3)) >= 0 {
                let pA3 = handleGet(pA3Out)
                if handleValid(pA3) != "0" {
                    let av3 = ptrDeref(pA3)
                    let pQV  = ptrIndex(av3, "14")
                    let pA3R = ptrIndex(av3, "2")
                    let info = bufNew("32")
                    callPtr(pQV, pA3, toHandle("0"), toHandle("0"), info)
                    let usageMB = div64(bufGetQwordAt(info, "8"), "1048576")
                    if toInt(usageMB) > 0 { result = usageMB + "" }
                    callPtr(pA3R, pA3)
                }
            }
            callPtr(pA1R, pA1)
        }
    }
    callPtr(pFR, pF)
    FreeLibrary(hD)
    emit result
}

func gpuvram() {
    // 2.0: registry for totals (works), PDH for usage (pdh.dll is not in
    // the Win32 marshalling list — raw-pointer 1.x convention still works).
    // Skip DXGI paths: they need LoadLibraryA + COM vtable, which is
    // fragile.
    let v = kfvramreg()
    if v == "" { emit "" }
    let used = kfpdhgpu()
    let n    = linecount(v)
    let result = ""
    let i = "0"
    while toInt(i) < toInt(n) {
        let line  = nthline(v, i)
        let tb    = firstpart(line, ":")
        let entry = tb + ":0"
        if i == "0" { entry = tb + ":" + used }
        if result != "" { result = result + "\n" }
        result = result + entry
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
