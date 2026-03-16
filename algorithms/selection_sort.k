// Selection Sort algorithm

func selectionSort(list) {
    let n = count(list)
    let i = 0
    while i < n - 1 {
        let minIdx = i
        let j = i + 1
        while j < n {
            if toInt(split(list, j)) < toInt(split(list, minIdx)) {
                minIdx = j
            }
            j += 1
        }
        if minIdx != i {
            // Swap
            let sb = sbNew()
            let k = 0
            while k < n {
                if k > 0 { sb = sbAppend(sb, ",") }
                if k == i {
                    sb = sbAppend(sb, split(list, minIdx))
                } else if k == minIdx {
                    sb = sbAppend(sb, split(list, i))
                } else {
                    sb = sbAppend(sb, split(list, k))
                }
                k += 1
            }
            list = sbToString(sb)
        }
        i += 1
    }
    emit list
}

just run {
    let data = "29,10,14,37,13,5,45"
    print("Before: " + data)
    print("After:  " + selectionSort(data))
}
