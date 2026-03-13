// List operations showcase
// Demonstrates: for-in, sort, reverse, slice, join, zip, unique, range,
//               indexOf, sumList, maxList, minList, fill, every, some, countOf

just run {
    print("=== List Operations ===")
    print("")

    // --- sort and reverse ---
    const fruits = "banana,apple,cherry,date,elderberry,apricot"
    print("Original:  " + fruits)
    print("Sorted:    " + sort(fruits))
    print("Reversed:  " + reverse(fruits))

    // --- slice ---
    const nums = "10,20,30,40,50,60,70,80"
    print("\nFull list: " + nums)
    print("Slice 2-5: " + slice(nums, 2, 5))
    print("Last 3:    " + slice(nums, -3, -0))

    // --- join ---
    const words = "Krypton,is,a,self-hosting,language"
    print("\nCSV:    " + words)
    print("Spaced: " + join(words, " "))
    print("Piped:  " + join(words, " | "))

    // --- range and for-in ---
    print("\nSquares 1-10:")
    let sb = sbNew()
    let first = 1
    for n in range(1, 11) {
        if !first { sb = sbAppend(sb, ", ") }
        sb = sbAppend(sb, n + "^2=" + n * n)
        first = 0
    }
    print("  " + sbToString(sb))

    // --- zip ---
    const names = "Alice,Bob,Charlie"
    const scores = "95,87,91"
    const zipped = zip(names, scores)
    print("\nZipped pairs: " + zipped)
    print("  keys:   " + keys(zipped))
    print("  values: " + values(zipped))

    // --- unique and countOf ---
    const data = "red,blue,red,green,blue,red,yellow,green"
    print("\nWith dupes: " + data)
    print("Unique:     " + unique(data))
    print("Red count:  " + countOf(data, "red"))
    print("Blue count: " + countOf(data, "blue"))

    // --- aggregate functions ---
    const grades = "85,92,78,95,88,76,91,83"
    print("\nGrades: " + grades)
    print("Sum:    " + sumList(grades))
    print("Min:    " + minList(grades))
    print("Max:    " + maxList(grades))
    print("Avg:    " + sumList(grades) / length(grades))

    // --- fill and every ---
    const zeros = fill(5, "0")
    print("\nFilled: " + zeros)
    print("All 0?  " + (every(zeros, "0") ? "yes" : "no"))
    print("Any 1?  " + (some(zeros, "1") ? "yes" : "no"))

    // --- listIndexOf ---
    const haystack = "cat,dog,bird,fish,hamster"
    print("\nList: " + haystack)
    print("Index of 'bird':  " + listIndexOf(haystack, "bird"))
    print("Index of 'snake': " + listIndexOf(haystack, "snake"))

    emit "ok"
}
