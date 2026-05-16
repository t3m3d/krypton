// Merge Sort
// Top-down recursive merge of two sorted halves.

func _ms_get(arr, i) { emit toInt(split(arr, i)) }

func _ms_slice(arr, lo, hi) {
    // Returns elements [lo, hi) as a comma-list. Empty if lo>=hi.
    if lo >= hi { emit "" }
    let sb = sbNew()
    let i = lo
    while i < hi {
        if i > lo { sb = sbAppend(sb, ",") }
        sb = sbAppend(sb, split(arr, i))
        i += 1
    }
    emit sbToString(sb)
}

func _ms_merge(a, b) {
    // Both already sorted. Returns merged sorted list.
    if len(a) == 0 { emit b }
    if len(b) == 0 { emit a }
    let na = count(a)
    let nb = count(b)
    let i = 0
    let j = 0
    let sb = sbNew()
    let first = 1
    while i < na && j < nb {
        if first { first = 0 } else { sb = sbAppend(sb, ",") }
        if _ms_get(a, i) <= _ms_get(b, j) {
            sb = sbAppend(sb, split(a, i))
            i += 1
        } else {
            sb = sbAppend(sb, split(b, j))
            j += 1
        }
    }
    while i < na {
        if first { first = 0 } else { sb = sbAppend(sb, ",") }
        sb = sbAppend(sb, split(a, i))
        i += 1
    }
    while j < nb {
        if first { first = 0 } else { sb = sbAppend(sb, ",") }
        sb = sbAppend(sb, split(b, j))
        j += 1
    }
    emit sbToString(sb)
}

func mergeSort(lst) {
    if len(lst) == 0 { emit "" }
    let n = count(lst)
    if n <= 1 { emit lst }
    let mid = n / 2
    let left  = mergeSort(_ms_slice(lst, 0, mid))
    let right = mergeSort(_ms_slice(lst, mid, n))
    emit _ms_merge(left, right)
}

just run {
    kp("Merge Sort")
    kp("==========")
    let cases = "5,3,8,1,4,2,7,6"
    kp("  in:  " + cases)
    kp("  out: " + mergeSort(cases))

    let rev = "9,8,7,6,5,4,3,2,1"
    kp("  in:  " + rev)
    kp("  out: " + mergeSort(rev))

    let dup = "4,2,4,1,2,4,1"
    kp("  in:  " + dup)
    kp("  out: " + mergeSort(dup))
}
