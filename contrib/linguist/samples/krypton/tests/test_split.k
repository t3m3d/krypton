// Test split function
// Verifies splitting comma-separated values

func check(name, expected, actual) {
    if expected == actual {
        kp("[PASS] " + name)
    } else {
        kp("[FAIL] " + name + " expected=" + expected + " actual=" + actual)
    }
}

just run {
    kp("Split Tests")
    kp("===========")

    let csv = "apple,banana,cherry,date,elderberry"

    check("split 0", "apple", split(csv, 0))
    check("split 1", "banana", split(csv, 1))
    check("split 2", "cherry", split(csv, 2))
    check("split 3", "date", split(csv, 3))
    check("split 4", "elderberry", split(csv, 4))

    // Count
    check("count", "5", "" + count(csv))

    // Numbers
    let nums = "10,20,30,40,50"
    check("num split 0", "10", split(nums, 0))
    check("num split 2", "30", split(nums, 2))
    check("num count", "5", "" + count(nums))

    // Single item
    let single = "only"
    check("single split 0", "only", split(single, 0))
    check("single count", "1", "" + count(single))

    // Two items
    let pair = "first,second"
    check("pair 0", "first", split(pair, 0))
    check("pair 1", "second", split(pair, 1))
    check("pair count", "2", "" + count(pair))

    emit "ok"
}
