// Heap Sort
// Builds a max-heap, then repeatedly swaps root to the end and sifts down.
// Heap is stored as a comma-list — index 0 is root, parent of i is (i-1)/2,
// children are 2i+1 and 2i+2.

func _hs_get(h, i) { emit toInt(split(h, i)) }

func _hs_swap(h, i, j) {
    let n = count(h)
    let sb = sbNew()
    let k = 0
    while k < n {
        if k > 0 { sb = sbAppend(sb, ",") }
        if k == i {
            sb = sbAppend(sb, split(h, j))
        } else if k == j {
            sb = sbAppend(sb, split(h, i))
        } else {
            sb = sbAppend(sb, split(h, k))
        }
        k += 1
    }
    emit sbToString(sb)
}

func _hs_siftDown(h, start, end) {
    // end is exclusive (length of the active heap region).
    let cur = h
    let root = start
    let cont = 1
    while cont {
        let child = 2 * root + 1
        if child >= end { cont = 0 }
        if cont {
            if child + 1 < end {
                if _hs_get(cur, child + 1) > _hs_get(cur, child) {
                    child = child + 1
                }
            }
            if _hs_get(cur, root) < _hs_get(cur, child) {
                cur = _hs_swap(cur, root, child)
                root = child
            } else {
                cont = 0
            }
        }
    }
    emit cur
}

func heapSort(lst) {
    if len(lst) == 0 { emit "" }
    let n = count(lst)
    if n <= 1 { emit lst }
    let h = lst
    // Heapify (build max-heap from bottom non-leaf up).
    let start = (n / 2) - 1
    while start >= 0 {
        h = _hs_siftDown(h, start, n)
        start -= 1
    }
    // Extract max repeatedly.
    let endi = n - 1
    while endi > 0 {
        h = _hs_swap(h, 0, endi)
        h = _hs_siftDown(h, 0, endi)
        endi -= 1
    }
    emit h
}

just run {
    kp("Heap Sort")
    kp("=========")
    let cases = "5,3,8,1,4,2,7,6"
    kp("  in:  " + cases)
    kp("  out: " + heapSort(cases))

    let rev = "9,8,7,6,5,4,3,2,1"
    kp("  in:  " + rev)
    kp("  out: " + heapSort(rev))

    let dup = "4,2,4,1,2,4,1"
    kp("  in:  " + dup)
    kp("  out: " + heapSort(dup))
}
