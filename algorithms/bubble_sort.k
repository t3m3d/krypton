// Bubble Sort algorithm
// Sorts a comma-separated list of numbers

func listSwap(list, i, j, n) {
    let sb = sbNew()
    let k = 0
    while k < n {
        if k > 0 { sb = sbAppend(sb, ",") }
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

func bubbleSort(list) {
    let n = count(list)
    let i = 0
    while i < n - 1 {
        let j = 0
        while j < n - 1 - i {
            let a = toInt(split(list, j))
            let b = toInt(split(list, j + 1))
            if a > b {
                list = listSwap(list, j, j + 1, n)
            }
            j = j + 1
        }
        i = i + 1
    }
    emit list
}

just run {
    let data = "64,34,25,12,22,11,90"
    print("Before: " + data)
    let sorted = bubbleSort(data)
    print("After:  " + sorted)
}
