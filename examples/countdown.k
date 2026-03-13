// Countdown timer with do-while and match
// Demonstrates: do-while, continue, match, const, compound assignment, ternary

func describePhase(n) {
    let phase = ""
    match n {
        10 { phase = "Launch sequence initiated" }
        5  { phase = "Final countdown" }
        3  { phase = "Ignition sequence start" }
        1  { phase = "Main engine start" }
        0  { phase = "LIFTOFF!" }
        else { phase = "" }
    }
    emit phase
}

func formatTime(seconds) {
    const mins = seconds / 60
    const secs = seconds % 60
    emit padLeft(mins, 2, "0") + ":" + padLeft(secs, 2, "0")
}

just run {
    const title = "Rocket Launch Countdown"
    print(title)
    print(repeat("=", len(title)))
    print("")

    let t = 10
    do {
        const timeStr = formatTime(t)
        const phase = describePhase(t)
        const display = "T-" + padLeft(t, 2, " ") + " [" + timeStr + "]"

        if phase != "" {
            print(display + "  << " + phase)
        } else {
            print(display)
        }

        t -= 1
    } while t >= 0

    print("")
    print("Mission status: GO")

    // Also demonstrate do-while with continue
    print("")
    print("Even numbers via do-while + continue:")
    let sb = sbNew()
    let i = 0
    let first = 1
    do {
        i += 1
        if i % 2 != 0 {
            continue
        }
        if !first { sb = sbAppend(sb, ", ") }
        sb = sbAppend(sb, i)
        first = 0
    } while i < 20
    print("  " + sbToString(sb))

    emit "ok"
}
