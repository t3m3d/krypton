// Quicksort
// In-place partition style adapted to Krypton's comma-list strings.
// Picks the last element as pivot (Lomuto partition).

func _qs_listLen(lst) {
    if len(lst) == 0 { emit 0 }
    emit count(lst)
}

func _qs_listToSb(lst) {
    // Returns the list contents as a fresh sb so we can rebuild reordered.
    let sb = sbNew()
    let n = _qs_listLen(lst)
    let i = 0
    while i < n {
        if i > 0 { sb = sbAppend(sb, ",") }
        sb = sbAppend(sb, split(lst, i))
        i += 1
    }
    emit sbToString(sb)
}

func _qs_get(arr, i) {
    emit toInt(split(arr, i))
}

func _qs_swap(arr, i, j) {
    // Returns a new list with positions i and j swapped.
    let n = count(arr)
    let sb = sbNew()
    let k = 0
    while k < n {
        if k > 0 { sb = sbAppend(sb, ",") }
        if k == i {
            sb = sbAppend(sb, split(arr, j))
        } else if k == j {
            sb = sbAppend(sb, split(arr, i))
        } else {
            sb = sbAppend(sb, split(arr, k))
        }
        k += 1
    }
    emit sbToString(sb)
}

func _qs_partition(arr, lo, hi) {
    // Returns "newarr,pivotIdx" pair.
    let pivot = _qs_get(arr, hi)
    let i = lo - 1
    let j = lo
    let cur = arr
    while j < hi {
        if _qs_get(cur, j) <= pivot {
            i += 1
            cur = _qs_swap(cur, i, j)
        }
        j += 1
    }
    cur = _qs_swap(cur, i + 1, hi)
    emit cur + ";" + (i + 1)
}

func _qs_findSemi(s) {
    let i = len(s) - 1
    while i >= 0 {
        if s[i] == ";" { emit i }
        i -= 1
    }
    emit -1
}

func _qs_arr(p)  { let c = _qs_findSemi(p); emit substring(p, 0, c) }
func _qs_pivot(p){ let c = _qs_findSemi(p); emit toInt(substring(p, c + 1, len(p))) }

func quicksort(arr, lo, hi) {
    if lo >= hi { emit arr }
    let p = _qs_partition(arr, lo, hi)
    let cur = _qs_arr(p)
    let pi  = _qs_pivot(p)
    cur = quicksort(cur, lo, pi - 1)
    cur = quicksort(cur, pi + 1, hi)
    emit cur
}

func sortList(lst) {
    let n = _qs_listLen(lst)
    if n <= 1 { emit lst }
    emit quicksort(_qs_listToSb(lst), 0, n - 1)
}

just run {
    kp("Quicksort")
    kp("=========")
    let cases = "5,3,8,1,4,2,7,6"
    kp("  in:  " + cases)
    kp("  out: " + sortList(cases))

    let small = "3,1,2"
    kp("  in:  " + small)
    kp("  out: " + sortList(small))

    let dup = "4,2,4,1,2,4,1"
    kp("  in:  " + dup)
    kp("  out: " + sortList(dup))

    let one = "42"
    kp("  in:  " + one)
    kp("  out: " + sortList(one))
}
