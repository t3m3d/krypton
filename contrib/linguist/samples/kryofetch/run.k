import "head:windows"
import "head:fileio"

func kfcls() {
    let E = fromCharCode(27)
    kp(E + "[2J" + E + "[H")
    emit ""
}

// STD_OUTPUT_HANDLE = (DWORD)-11 = 4294967285 unsigned.
// 2.0: GetStdHandle is now Win32-marshalled in x64.k (atoi's the int
// arg, itoa's the HANDLE return). Pass the int as a string directly;
// dropping the legacy toHandle() wrapper.
func kfstdout() {
    emit GetStdHandle("4294967285")
}

// kfinit: enable UTF-8 output and VT100 escape processing
func kfinit() {
    SetConsoleOutputCP("65001")
    let h       = kfstdout()
    let modeBuf = bufNew("4")
    bufSetDword(modeBuf, "0")
    GetConsoleMode(h, modeBuf)
    let m    = toInt(bufGetDword(modeBuf))
    let newm = bitOr(m + "", "4")
    SetConsoleMode(h, newm)
    emit ""
}

// kfconsize: console window columns,rows via CONSOLE_SCREEN_BUFFER_INFO
func kfconsize() {
    let h    = kfstdout()
    let csbi = structNew("CONSOLE_SCREEN_BUFFER_INFO")
    GetConsoleScreenBufferInfo(h, csbi)
    let right = toInt(structGet(csbi, "CONSOLE_SCREEN_BUFFER_INFO", "srWindowRight"))
    let left  = toInt(structGet(csbi, "CONSOLE_SCREEN_BUFFER_INFO", "srWindowLeft"))
    let bot   = toInt(structGet(csbi, "CONSOLE_SCREEN_BUFFER_INFO", "srWindowBottom"))
    let top   = toInt(structGet(csbi, "CONSOLE_SCREEN_BUFFER_INFO", "srWindowTop"))
    if right == 0 { emit "0,0" }
    let cols = right - left + 1 + ""
    let rows = bot - top + 1 + ""
    emit cols + "," + rows
}

// kfshell: identify the calling shell.
//
// Two-tier detection:
//   1. Walk the parent process tree via Toolhelp32 — exact exe name of
//      whatever spawned us. Right answer when it works.
//   2. Env-var fallback for when the process walk yields nothing.
func _kfshell_byEnv() {
    // Most reliable PowerShell Core signal — set on pwsh.exe startup,
    // NOT typically inherited by spawned cmd.exe children.
    let psdc = environ("POWERSHELL_DISTRIBUTION_CHANNEL")
    if psdc != "" { emit "PowerShell" }
    // Windows PowerShell 5.x and PowerShell Core both set this.
    let psmod = environ("PSModulePath")
    if psmod != "" { emit "PowerShell" }
    emit "cmd"
}

// 2.0: Win32 returns are already itoa'd strings — drop handleInt() wraps.
func kfshell() {
    let mypid  = GetCurrentProcessId()
    let snap   = CreateToolhelp32Snapshot("2", "0")
    let entry  = structNew("PROCESSENTRY32")
    structSet(entry, "PROCESSENTRY32", "dwSize", "304")
    let ppid   = ""
    let result = ""
    // first pass: find our parent PID
    let ok = Process32First(snap, entry)
    while ok != "0" {
        let pid = structGet(entry, "PROCESSENTRY32", "th32ProcessID")
        if pid == mypid {
            ppid = structGet(entry, "PROCESSENTRY32", "th32ParentProcessID")
        }
        ok = Process32Next(snap, entry)
    }
    // second pass: find parent exe name
    structSet(entry, "PROCESSENTRY32", "dwSize", "304")
    ok = Process32First(snap, entry)
    while ok != "0" {
        let pid = structGet(entry, "PROCESSENTRY32", "th32ProcessID")
        if pid == ppid {
            result = structGet(entry, "PROCESSENTRY32", "szExeFile")
        }
        ok = Process32Next(snap, entry)
    }
    CloseHandle(snap)
    // Process walk yielded nothing → env-var fallback.
    if result == "" { emit _kfshell_byEnv() }
    let low = toLower(result)
    if contains(low, "powershell") { emit "PowerShell" }
    if contains(low, "pwsh")       { emit "PowerShell" }
    if contains(low, "bash")       { emit "bash" }
    if contains(low, "zsh")        { emit "zsh" }
    if contains(low, "nu")         { emit "nushell" }
    if contains(low, "cmd")        { emit "cmd" }
    emit result
}

import "utils.k"
import "cpu.k"
import "os.k"
import "mem.k"
import "disk.k"
import "gpu.k"

func run() {
    kfcls()
    kfinit()

    let E     = fromCharCode(27)
    let GRN   = E + "[32;1m"
    let CYN   = E + "[36;1m"
    let RST   = E + "[0m"
    let BLU   = E + "[34m"
    let CY    = E + "[36m"
    let LW    = "40"

    let l0  = BLU + "        ,.=:!!t3Z3z.," + RST
    let l1  = BLU + "       :tt:::tt333EE3" + RST
    let l2  = BLU + "       Et:::ztt33EEEL" + CY + " @Ee.,      ..," + RST
    let l3  = BLU + "      ;tt:::tt333EE7" + CY + " ;EEEEEEttttt33#" + RST
    let l4  = BLU + "     :Et:::zt333EEQ" + CY + "  SEEEEEttttt33QL" + RST
    let l5  = BLU + "     it::::tt333EEF" + CY + " @EEEEttttt33F" + RST
    let l6  = BLU + "    ;3=*^   " + "\"" + "*4EEV" + CY + " :EEEEttttt33@." + RST
    let l7  = CY + "    ,.=::::!t=.," + BLU + "  @EEEEtttz33QF" + RST
    let l8  = CY + "   ;::::::::zt33)" + BLU + "   " + "\"" + "4EEEtttji" + RST
    let l9  = CY + "  :t::::::::tt33." + BLU + " :Z3z..    " + RST
    let l10 = CY + "  i::::::::zt33F" + BLU + " AEEEtttt::::ztF" + RST
    let l11 = CY + " ;:::::::::t33V" + BLU + " ;EEEttttt::::t3" + RST
    let l12 = CY + " E::::::::zt33L" + BLU + " @EEEtttt::::z3F" + RST
    let l13 = CY + "{3=*^   " + "\"" + "*4E3)" + BLU + " ;EEEtttt:::::tZ" + RST
    let l14 = CY + "            " + BLU + " :EEEEtttt::::z7" + RST
    let l15 = BLU + "                 " + "\"" + "VEzjt:;;z>*" + RST

    let usr  = sysuser()
    let host = syshost()
    let arch = sysarch()
    let os   = osver()
    let cpu  = cpubrand()
    let ci   = cpucores()
    let cn   = firstpart(ci, ",")
    let tn   = afterpart(ci, ",")

    let mi   = raminfo()
    let tmb  = firstpart(mi, ",")
    let fmb  = afterpart(mi, ",")
    let umb  = toInt(tmb) - toInt(fmb) + ""
    let tgb  = toInt(tmb) / 1024 + ""
    let ugb  = toInt(umb) / 1024 + ""
    let rpct = toInt(umb) * 100 / toInt(tmb) + ""
    let rb   = rambar(umb, tmb)

    let di   = driveinfo()
    let d1 = nthline(di, "0")
    let d2 = nthline(di, "1")
    let d3 = nthline(di, "2")

    let gp   = gpunames()
    let ng   = linecount(gp)
    let g1 = ""
    let g2 = ""
    if ng == "1" { g1 = gp }
    if toInt(ng) >= 2 {
        g1 = nthline(gp, "0")
        g2 = nthline(gp, "1")
    }
    if g1 == "" { g1 = "None" }

    let vd  = gpuvram()
    let vn  = linecount(vd)
    let vr1 = ""
    let vr2 = ""
    if toInt(vn) >= 1 { vr1 = nthline(vd, "0") }
    if toInt(vn) >= 2 { vr2 = nthline(vd, "1") }

    let tc   = kfconsize()
    let cols = firstpart(tc, ",")
    let rows = afterpart(tc, ",")
    let up   = uptime()
    let sh   = kfshell()
    let tnm  = kfterminal()
    let res  = kfresolution()
    let thm  = kftheme()
    let bat  = kfbattery()

    let lb0  = "User"
    let v0   = usr + "@" + host
    let lb1  = "OS"
    let v1   = os + " " + arch
    let lb2  = "CPU"
    let v2   = cpu + " (" + cn + "c / " + tn + "t)"
    let lb3  = "RAM"
    let v3   = rb + "  " + ugb + " GB / " + tgb + " GB  " + rpct + "%"
    let lb4  = "Disk"
    let v4   = d1
    let lb5  = ""
    let v5   = d2
    let lb6  = ""
    let v6   = d3
    let lb7  = "GPU"
    let v7   = fmtgpu(g1, vr1)
    let lb8  = ""
    let v8   = ""
    if g2 != "" {
        lb8 = "GPU2"
        v8  = fmtgpu(g2, vr2)
    }
    let lb9  = "Shell"
    let v9   = sh
    let lb10 = ""
    let v10  = ""
    let termv = ""
    if tnm != "" { termv = tnm }
    if cols != "0" {
        if termv != "" { termv = termv + " " + cols + "x" + rows }
        if termv == "" { termv = cols + "x" + rows }
    }
    if termv != "" {
        lb10 = "Term"
        v10  = termv
    }
    let lb11 = "Res"
    let v11  = res
    let lb12 = "Uptime"
    let v12  = up
    let lb13 = "Pkgs"
    let v13  = kfpkgs()
    let lb14 = "Theme"
    let v14  = thm
    let lb15 = ""
    let v15  = ""
    if bat != "" {
        lb15 = "Battery"
        v15  = bat
    }

    let idx = "0"
    while toInt(idx) < 16 {
        let logo = ""
        if idx == "0"  { logo = l0  }
        if idx == "1"  { logo = l1  }
        if idx == "2"  { logo = l2  }
        if idx == "3"  { logo = l3  }
        if idx == "4"  { logo = l4  }
        if idx == "5"  { logo = l5  }
        if idx == "6"  { logo = l6  }
        if idx == "7"  { logo = l7  }
        if idx == "8"  { logo = l8  }
        if idx == "9"  { logo = l9  }
        if idx == "10" { logo = l10 }
        if idx == "11" { logo = l11 }
        if idx == "12" { logo = l12 }
        if idx == "13" { logo = l13 }
        if idx == "14" { logo = l14 }
        if idx == "15" { logo = l15 }

        let lb = ""
        let v  = ""
        if idx == "0"  { lb = lb0;  v = v0  }
        if idx == "1"  { lb = lb1;  v = v1  }
        if idx == "2"  { lb = lb2;  v = v2  }
        if idx == "3"  { lb = lb3;  v = v3  }
        if idx == "4"  { lb = lb4;  v = v4  }
        if idx == "5"  { lb = lb5;  v = v5  }
        if idx == "6"  { lb = lb6;  v = v6  }
        if idx == "7"  { lb = lb7;  v = v7  }
        if idx == "8"  { lb = lb8;  v = v8  }
        if idx == "9"  { lb = lb9;  v = v9  }
        if idx == "10" { lb = lb10; v = v10 }
        if idx == "11" { lb = lb11; v = v11 }
        if idx == "12" { lb = lb12; v = v12 }
        if idx == "13" { lb = lb13; v = v13 }
        if idx == "14" { lb = lb14; v = v14 }
        if idx == "15" { lb = lb15; v = v15 }

        let info = ""
        if lb != "" {
            let lbc    = lb + ":"
            let padlen = 7 - len(lbc)
            let pad    = ""
            let pi     = "0"
            while toInt(pi) < padlen {
                pad = pad + " "
                pi  = toInt(pi) + 1 + ""
            }
            info = GRN + lbc + RST + pad + v
        } else {
            if v != "" { info = "       " + v }
        }

        kp(padansi(logo, toInt(LW)) + "  " + info)
        idx = toInt(idx) + 1 + ""
    }

    kp("")
    kp(CYN + "  KryoFetch" + RST + " by KryptonBytes")
    kp("")
    colorpalette()
    kp("")
    emit
}

just run {
    // --watch [interval_ms]: re-render in a loop. gcCheckpoint at the
    // start of each iteration + gcRestore at the end reclaims per-render
    // allocations without disturbing pre-watch setup state. Tighter scope
    // than gcCollect (mark+sweep across the entire heap). Default
    // interval = 1000 ms.
    //
    // Krypton 2.0: Sleep is Win32-marshalled — pass interval as plain
    // string, no toHandle() wrap.
    let watch = "0"
    let intervalMs = "1000"
    let argc = argCount()
    let i = "0"
    while toInt(i) < toInt(argc) {
        let a = arg(i)
        if a == "--watch" {
            watch = "1"
            if toInt(i) + 1 < toInt(argc) {
                intervalMs = arg(toInt(i) + 1 + "")
            }
        }
        i = toInt(i) + 1 + ""
    }

    if watch == "0" {
        run()
    } else {
        while watch == "1" {
            run()
            Sleep(intervalMs)
            // 2.0 mark+sweep: reclaims unreachable allocations from this
            // render. Tighter than gcCheckpoint/gcRestore (which rolls
            // the arena back to a snapshot — fine in 1.x, but in 2.0
            // it can clobber heap state used by registry-iteration code
            // run later, manifesting as e.g. phantom GPU2 entries).
            gcCollect()
        }
    }
}
