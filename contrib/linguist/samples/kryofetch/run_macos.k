import "utils_macos.k"
import "cpu_macos.k"
import "os_macos.k"
import "mem_macos.k"
import "disk_macos.k"
import "gpu_macos.k"

func kfcls() {
    let E = fromCharCode(27)
    kp(E + "[2J" + E + "[H")
    emit ""
}

func kfinit() {
    emit ""
}

func kfconsize() {
    let cols = exec("tput cols 2>/dev/null")
    let rows = exec("tput lines 2>/dev/null")
    if cols == "" { emit "0,0" }
    emit cols + "," + rows
}

func kfshell() {
    let sh = environ("SHELL")
    if contains(sh, "zsh") {
        let v = trim(exec("zsh --version 2>/dev/null | awk '{print $2}'"))
        if v != "" { emit "zsh " + v }
        emit "zsh"
    }
    if contains(sh, "bash") {
        let v = trim(exec("bash --version 2>/dev/null | head -1 | grep -oE '[0-9]+\\.[0-9]+\\.[0-9]+'"))
        if v != "" { emit "bash " + v }
        emit "bash"
    }
    if contains(sh, "fish") {
        let v = trim(exec("fish --version 2>/dev/null | awk '{print $NF}'"))
        if v != "" { emit "fish " + v }
        emit "fish"
    }
    if contains(sh, "nu") { emit "nushell" }
    if sh != "" { emit sh }
    emit "unknown"
}

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

    let GR2 = E + "[32m"
    let YEL = E + "[33m"
    let ORG = E + "[33;1m"
    let RED = E + "[31m"
    let PUR = E + "[35m"

    let l0  = GR2 + "                    'c." + RST
    let l1  = GR2 + "                 ,xNMM." + RST
    let l2  = YEL + "               .OMMMMo" + RST
    let l3  = YEL + "               OMMM0," + RST
    let l4  = ORG + "     .;loddo:' loolloddol;." + RST
    let l5  = ORG + "   cKMMMMMMMMMMNWMMMMMMMMMM0:" + RST
    let l6  = RED + " .KMMMMMMMMMMMMMMMMMMMMMMMWd." + RST
    let l7  = RED + " XMMMMMMMMMMMMMMMMMMMMMMMX." + RST
    let l8  = PUR + ";MMMMMMMMMMMMMMMMMMMMMMMM:" + RST
    let l9  = PUR + ":MMMMMMMMMMMMMMMMMMMMMMMM:" + RST
    let l10 = BLU + ".MMMMMMMMMMMMMMMMMMMMMMMMX." + RST
    let l11 = BLU + " kMMMMMMMMMMMMMMMMMMMMMMMMWd." + RST
    let l12 = BLU + " .XMMMMMMMMMMMMMMMMMMMMMMMMMMk" + RST
    let l13 = BLU + "  .XMMMMMMMMMMMMMMMMMMMMMMMMK." + RST
    let l14 = BLU + "    kMMMMMMMMMMMMMMMMMMMMMMd" + RST
    let l15 = BLU + "     ;KMMMMMMMWXXWMMMMMMMk." + RST

    let usr  = sysuser()
    let host = syshost()
    let arch = sysarch()
    let os   = osver()
    let kern = kfkernel()
    let mdl  = sysmodel()
    let cpu  = cpubrand()
    let ci   = cpucores()
    let cn   = firstpart(ci, ",")
    let tn   = afterpart(ci, ",")

    let swp  = swapinfo()
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
    let tfnt = kftermfont()
    let res  = kfresolution()
    let diraw = kfdisplayinfo()
    let dinm  = firstpart(diraw, "|")
    let diraw2 = afterpart(diraw, "|")
    let dipx   = firstpart(diraw2, "|")
    let diraw3 = afterpart(diraw2, "|")
    let dihz   = firstpart(diraw3, "|")
    let diraw4 = afterpart(diraw3, "|")
    let dict   = firstpart(diraw4, "|")
    let discl  = afterpart(diraw4, "|")
    let paren_pos = indexOf(mdl, "(")
    let inch_pos  = indexOf(mdl, "-inch")
    let disize = ""
    if toInt(inch_pos) > 0 {
        if toInt(paren_pos) > 0 { disize = substring(mdl, toInt(paren_pos) + 1, toInt(inch_pos)) }
    }
    let wm   = kfwmver()
    let wmth = kfaccent()
    let thm  = kfthemename()
    let lip  = kflocalip()
    let batraw = kfbattraw()
    let bchip = nthline(batraw, "0")
    let bpct  = nthline(batraw, "1")
    let bmins = nthline(batraw, "2")
    let bchrg = nthline(batraw, "3")
    let bfull = nthline(batraw, "4")
    let bstat = "Discharging"
    if bchrg == "Yes" { bstat = "Charging" }
    if bfull == "Yes" { bstat = "Charged" }
    let bh  = toInt(bmins) / 60 + ""
    let brm = toInt(bmins) - toInt(bh) * 60 + ""
    let btimestr = ""
    if toInt(bmins) > 0 {
        if toInt(bmins) < 65535 { btimestr = bh + " hours, " + brm + " mins remaining" }
    }
    let batval = bpct + "%"
    if btimestr != "" { batval = batval + " (" + btimestr + ")" }
    batval = batval + " [" + bstat + "]"
    let batlbl = "Battery"
    if bchip != "" { batlbl = "Battery (" + bchip + ")" }

    // Build packed info list — only non-empty entries are added
    let IL = ""
    IL = IL + GRN + "User:  " + RST + usr + "@" + host + "\n"
    IL = IL + GRN + "OS:    " + RST + os + " " + arch + "\n"
    IL = IL + GRN + "Host:  " + RST + mdl + "\n"
    IL = IL + GRN + "Kernel:" + RST + kern + "\n"
    IL = IL + GRN + "CPU:   " + RST + cpu + " (" + cn + "c / " + tn + "t)" + "\n"
    IL = IL + GRN + "GPU:   " + RST + fmtgpu(g1, vr1) + "\n"
    if g2 != "" { IL = IL + GRN + "GPU2:  " + RST + fmtgpu(g2, vr2) + "\n" }
    IL = IL + GRN + "RAM:   " + RST + rb + "  " + ugb + " GB / " + tgb + " GB  " + rpct + "%" + "\n"
    IL = IL + GRN + "Swap:  " + RST + swp + "\n"
    IL = IL + GRN + "Disk:  " + RST + d1 + "\n"
    if d2 != "" { IL = IL + "       " + d2 + "\n" }
    if d3 != "" { IL = IL + "       " + d3 + "\n" }
    IL = IL + GRN + "Shell: " + RST + sh + "\n"
    let termv = ""
    if tnm != "" { termv = tnm }
    if cols != "0" {
        if termv != "" { termv = termv + " " + cols + "x" + rows }
        if termv == "" { termv = cols + "x" + rows }
    }
    if termv != "" { IL = IL + GRN + "Term:  " + RST + termv + "\n" }
    if tfnt != "" { IL = IL + GRN + "TermFont:" + RST + tfnt + "\n" }
    IL = IL + GRN + "Res:   " + RST + res + "\n"
    let diline = dipx
    if discl != "" { diline = diline + " @ " + discl }
    if disize != "" { diline = diline + " in " + disize + "\"" }
    if dihz != "" { diline = diline + ", " + dihz }
    if dict != "" { diline = diline + " [" + dict + "]" }
    if dinm != "" { IL = IL + GRN + "Display (" + dinm + "):" + RST + diline + "\n" }
    IL = IL + GRN + "WM:    " + RST + wm + "\n"
    IL = IL + GRN + "WMTheme:" + RST + wmth + "\n"
    IL = IL + GRN + "Theme: " + RST + thm + "\n"
    IL = IL + GRN + "Uptime:" + RST + up + "\n"
    IL = IL + GRN + "Pkgs:  " + RST + kfpkgs() + "\n"
    if lip != "" { IL = IL + GRN + "IP(en0):" + RST + lip + "\n" }
    if bchip != "" { IL = IL + GRN + batlbl + ":" + RST + batval + "\n" }

    let idx = "0"
    let infolen = linecount(IL)
    let maxidx = "16"
    if toInt(infolen) > 16 { maxidx = infolen }
    while toInt(idx) < toInt(maxidx) {
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

        kp(padansi(logo, toInt(LW)) + "  " + infoline(IL, idx))
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
    run()
}
