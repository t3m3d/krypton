// Insertion Sort algorithm

func insertionSort(list) {
    let n = count(list)
    let i = 1
    while i < n {
        let key = toInt(split(list, i))
        let j = i - 1
        // Shift elements right
        let shifted = 1
        while j >= 0 && shifted {
            let val = toInt(split(list, j))
            if val > key {
                // Move val to j+1
                let sb = sbNew()
                let k = 0
                while k < n {
                    if k > 0 { sb = sbAppend(sb, ",") }
                    if k == j + 1 {
                        sb = sbAppend(sb, "" + val)
                    } else if k == j {
                        sb = sbAppend(sb, "" + key)
                    } else {
                        sb = sbAppend(sb, split(list, k))
                    }
                    k = k + 1
                }
                list = sbToString(sb)
                j = j - 1
            } else {
                shifted = 0
            }
        }
        i = i + 1
    }
    emit list
}

just run {
    let data = "12,11,13,5,6"
    print("Before: " + data)
    print("After:  " + insertionSort(data))
}
