// Tutorial 11: Comma-Separated Lists
// Using strings with commas as lists

func listGet(list, index) {
    emit split(list, index)
}

func listSize(list) {
    emit count(list)
}

just run {
    // Comma-separated values act as lists
    let fruits = "apple,banana,cherry,date"

    kp("List: " + fruits)
    kp("Size: " + listSize(fruits))

    // Access by index using split()
    kp("First: " + split(fruits, 0))
    kp("Third: " + split(fruits, 2))

    // Iterate over the list
    let i = 0
    let n = count(fruits)
    while i < n {
        kp("  [" + i + "] " + split(fruits, i))
        i = i + 1
    }

    // Building lists
    let numbers = ""
    i = 1
    while i <= 5 {
        if i > 1 {
            numbers = numbers + ","
        }
        numbers = numbers + "" + (i * i)
        i = i + 1
    }
    kp("Squares: " + numbers)
}
