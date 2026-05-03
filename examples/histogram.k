// ASCII bar-chart histogram from a list of numbers.

func bar(n) {
    let out = ""
    let i = 0
    while i < toInt(n) {
        out = out + "█"
        i += 1
    }
    emit out
}

func max(values) {
    let m = 0
    for v in values {
        if toInt(v) > m { m = toInt(v) }
    }
    emit m
}

just run {
    let data = "3,7,2,9,5,12,1,8,4,6"
    let m = max(data)
    let scale = 30
    kp("Histogram (max " + m + "):")
    for v in data {
        let n = toInt(v)
        let width = (n * scale) / m
        kp(`  {v} | ` + bar("" + width))
    }
}
