// Convert a number of seconds into HH:MM:SS format.

func pad2(n) {
    if toInt(n) < 10 { emit "0" + n }
    emit "" + n
}

func format(seconds) {
    let h = seconds / 3600
    let rem = seconds % 3600
    let m = rem / 60
    let s = rem % 60
    emit pad2(h) + ":" + pad2(m) + ":" + pad2(s)
}

just run {
    let cases = "0,7,59,60,61,3599,3600,3661,86399,90061"
    for c in cases {
        let n = toInt(c)
        kp(c + " seconds = " + format(n))
    }
}
