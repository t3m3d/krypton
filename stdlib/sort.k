// Sorting utilities for comma-separated lists
// Sorts numeric or string elements

go sort {

    // Swap two elements in a list by index
    func listSwap(list, i, j) {
        let size = count(list)
        let sb = sbNew()
        let k = 0
        while k < size {
            if k > 0 {
                sb = sbAppend(sb, ",")
            }
            if k == i {
                sb = sbAppend(sb, split(list, j))
            } else if k == j {
                sb = sbAppend(sb, split(list, i))
            } else {
                sb = sbAppend(sb, split(list, k))
            }
            k = k + 1
        }
        emit sbToString(sb)
    }

    // Bubble sort for numeric lists
    func bubbleSortNum(list) {
        let size = count(list)
        let sorted = list
        let i = 0
        while i < size - 1 {
            let j = 0
            while j < size - 1 - i {
                let a = toInt(split(sorted, j))
                let b = toInt(split(sorted, j + 1))
                if a > b {
                    sorted = listSwap(sorted, j, j + 1)
                }
                j = j + 1
            }
            i = i + 1
        }
        emit sorted
    }

    // Selection sort for numeric lists
    func selectionSortNum(list) {
        let size = count(list)
        let sorted = list
        let i = 0
        while i < size - 1 {
            let minIdx = i
            let j = i + 1
            while j < size {
                if toInt(split(sorted, j)) < toInt(split(sorted, minIdx)) {
                    minIdx = j
                }
                j = j + 1
            }
            if minIdx != i {
                sorted = listSwap(sorted, i, minIdx)
            }
            i = i + 1
        }
        emit sorted
    }

    // Insertion sort for numeric lists
    func insertionSortNum(list) {
        let size = count(list)
        // Build a new sorted list
        let result = split(list, 0)
        let i = 1
        while i < size {
            let val = toInt(split(list, i))
            // Insert val into result at correct position
            let rSize = count(result)
            let inserted = 0
            let newResult = ""
            let j = 0
            while j < rSize {
                let cur = toInt(split(result, j))
                if inserted == 0 {
                    if val <= cur {
                        if newResult == "" {
                            newResult = "" + val
                        } else {
                            newResult = newResult + "," + val
                        }
                        inserted = 1
                    }
                }
                if newResult == "" {
                    newResult = split(result, j)
                } else {
                    newResult = newResult + "," + split(result, j)
                }
                j = j + 1
            }
            if inserted == 0 {
                newResult = newResult + "," + val
            }
            result = newResult
            i = i + 1
        }
        emit result
    }

    // Check if a numeric list is sorted
    func isSorted(list) {
        let size = count(list)
        let i = 0
        while i < size - 1 {
            if toInt(split(list, i)) > toInt(split(list, i + 1)) {
                emit 0
            }
            i = i + 1
        }
        emit 1
    }

    // Find minimum value in numeric list
    func listMin(list) {
        let size = count(list)
        let minVal = toInt(split(list, 0))
        let i = 1
        while i < size {
            let val = toInt(split(list, i))
            if val < minVal {
                minVal = val
            }
            i = i + 1
        }
        emit minVal
    }

    // Find maximum value in numeric list
    func listMax(list) {
        let size = count(list)
        let maxVal = toInt(split(list, 0))
        let i = 1
        while i < size {
            let val = toInt(split(list, i))
            if val > maxVal {
                maxVal = val
            }
            i = i + 1
        }
        emit maxVal
    }
}
