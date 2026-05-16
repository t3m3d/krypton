// Binary Search algorithm

func binarySearch(list, target) {
    let lo = 0
    let hi = count(list) - 1
    while lo <= hi {
        let mid = (lo + hi) / 2
        let val = toInt(split(list, mid))
        if val == target {
            emit mid
        } else if val < target {
            lo = mid + 1
        } else {
            hi = mid - 1
        }
    }
    emit 0 - 1
}

just run {
    // Must be sorted
    let data = "2,5,8,12,16,23,38,56,72,91"
    kp("Data: " + data)

    let targets = "23,8,100,2,91,50"
    let i = 0
    while i < count(targets) {
        let t = toInt(split(targets, i))
        let idx = binarySearch(data, t)
        if idx >= 0 {
            kp("  Found " + t + " at index " + idx)
        } else {
            kp("  " + t + " not found")
        }
        i += 1
    }
}
