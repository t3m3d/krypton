// Print a Celsius ↔ Fahrenheit conversion chart.

func cToF(c) {
    // F = C * 9/5 + 32
    emit (c * 9) / 5 + 32
}

func fToC(f) {
    // C = (F - 32) * 5/9
    emit ((f - 32) * 5) / 9
}

func pad(s, w) {
    let out = "" + s
    while len(out) < toInt(w) {
        out = " " + out
    }
    emit out
}

just run {
    kp("Celsius   Fahrenheit")
    kp("-------   ----------")
    let c = 0 - 40
    while c <= 100 {
        let f = cToF(c)
        kp(pad("" + c, "5") + "     " + pad("" + f, "8"))
        c += 10
    }

    kp("")
    kp("Fahrenheit   Celsius")
    kp("----------   -------")
    let f = 0 - 40
    while f <= 212 {
        let c2 = fToC(f)
        kp(pad("" + f, "5") + "        " + pad("" + c2, "5"))
        f += 20
    }
}
