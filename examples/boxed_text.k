// Draw an ASCII box around a line of text.

func repeat(ch, n) {
    let out = ""
    let i = 0
    while i < toInt(n) {
        out = out + ch
        i += 1
    }
    emit out
}

func box(text) {
    let w = len(text) + 4
    let bar = "+" + repeat("-", "" + (w - 2)) + "+"
    kp(bar)
    kp("| " + text + " |")
    kp(bar)
}

just run {
    box("Hello, Krypton!")
    kp("")
    box("Native compilation works")
    kp("")
    box("a")
    kp("")
    box("123456789012345678901234567890")
}
