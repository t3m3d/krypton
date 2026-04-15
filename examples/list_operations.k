// List operations showcase
// Demonstrates: for-in, sort, reverse, slice, join, zip, unique, range,
//               indexOf, sumList, maxList, minList, fill, every, some, countOf

just run {
    kp("=== List Operations ===")
    kp("")

    // --- sort and reverse ---
    const fruits = "banana,apple,cherry,date,elderberry,apricot"
    kp("Original:  " + fruits)
    kp("Sorted:    " + sort(fruits))
    kp("Reversed:  " + reverse(fruits))

    // --- slice ---
    const nums = "10,20,30,40,50,60,70,80"
    kp("\nFull list: " + nums)
    kp("Slice 2-5: " + slice(nums, 2, 5))
    kp("First 4:   " + slice(nums, 0, 4))

    // --- join ---
    const words = "Krypton,is,a,self-hosting,language"
    kp("\nCSV:    " + words)
    kp("Spaced: " + join(words, " "))
    kp("Piped:  " + join(words, " | "))

    // --- range and for-in ---
    kp("\nSquares 1-10:")
    let sb = sbNew()
    let first = 1
    for n in range(1, 11) {
        if !first { sb = sbAppend(sb, ", ") }
        sb = sbAppend(sb, n + "^2=" + n * n)
        first = 0
    }
    kp("  " + sbToString(sb))

    // --- zip ---
    const names = "Alice,Bob,Charlie"
    const scores = "95,87,91"
    const zipped = zip(names, scores)
    kp("\nZipped pairs: " + zipped)
    kp("  keys:   " + keys(zipped))
    kp("  values: " + values(zipped))

    // --- unique and countOf ---
    const data = "red,blue,red,green,blue,red,yellow,green"
    kp("\nWith dupes: " + data)
    kp("Unique:     " + unique(data))
    kp("Red count:  " + countOf(data, "red"))
    kp("Blue count: " + countOf(data, "blue"))

    // --- aggregate functions ---
    const grades = "85,92,78,95,88,76,91,83"
    kp("\nGrades: " + grades)
    kp("Sum:    " + sumList(grades))
    kp("Min:    " + minList(grades))
    kp("Max:    " + maxList(grades))
    kp("Avg:    " + sumList(grades) / length(grades))

    // --- fill and every ---
    const zeros = fill(5, "0")
    kp("\nFilled: " + zeros)
    kp("All 0?  " + (every(zeros, "0") ? "yes" : "no"))
    kp("Any 1?  " + (some(zeros, "1") ? "yes" : "no"))

    // --- listIndexOf ---
    const haystack = "cat,dog,bird,fish,hamster"
    kp("\nList: " + haystack)
    kp("Index of 'bird':  " + listIndexOf(haystack, "bird"))
    kp("Index of 'snake': " + listIndexOf(haystack, "snake"))

    emit "ok"
}
