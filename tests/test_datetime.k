// datetime smoke — verify accessors return digit-prefixed / well-shaped
// strings (not cmd.exe interactive-prompt garbage), and that arithmetic
// helpers compose. Doesn't pin specific values (clock moves).
import "k:datetime"

func expect(label, cond) {
    if cond != "1" {
        kp("FAIL " + label)
        exit("1")
    }
}

just run {
    let now = dtNowEpoch()
    expect("epoch non-empty", (len(now) > 0) + "")
    expect("epoch is digits", (now[0] >= "0" && now[0] <= "9") + "")
    expect("epoch >= 1.7B",   (toInt(now) > 1700000000) + "")

    let today = dtToday()
    expect("today shape",    (len(today) == 10) + "")
    expect("today digit0",   (today[0] >= "0" && today[0] <= "9") + "")
    expect("today dash4",    (today[4] == "-") + "")

    let iso = dtNowIso()
    expect("iso has T",      contains(iso, "T") + "")
    expect("iso has Z",      endsWith(iso, "Z") + "")

    let http = dtHttpDate()
    expect("http has GMT",   endsWith(http, "GMT") + "")

    // Pure arithmetic — deterministic.
    expect("addSec",    (dtAddSeconds("1000", "5") == "1005") + "")
    expect("addMin",    (dtAddMinutes("0", "2")    == "120") + "")
    expect("addHr",     (dtAddHours("0", "1")      == "3600") + "")
    expect("addDay",    (dtAddDays("0", "1")       == "86400") + "")
    expect("addNeg",    (dtAddSeconds("100", "-10") == "90") + "")
    expect("diff",      (dtDiffSeconds("100", "200") == "100") + "")

    kp("ok")
}
