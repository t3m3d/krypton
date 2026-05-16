// Quickselect — find the k-th smallest (0-indexed) element.
// Average O(n), worst O(n^2). Picks last as pivot (Lomuto).

func _qsl_get(arr, i) { emit toInt(split(arr, i)) }

func _qsl_swap(arr, i, j) {
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

func _qsl_findSemi(s) {
    let i = len(s) - 1
    while i >= 0 {
        if s[i] == ";" { emit i }
        i -= 1
    }
    emit -1
}
func _qsl_arr(p)   { let c = _qsl_findSemi(p); emit substring(p, 0, c) }
func _qsl_pivot(p) { let c = _qsl_findSemi(p); emit toInt(substring(p, c + 1, len(p))) }

func _qsl_partition(arr, lo, hi) {
    let pivot = _qsl_get(arr, hi)
    let i = lo - 1
    let j = lo
    let cur = arr
    while j < hi {
        if _qsl_get(cur, j) <= pivot {
            i += 1
            cur = _qsl_swap(cur, i, j)
        }
        j += 1
    }
    cur = _qsl_swap(cur, i + 1, hi)
    emit cur + ";" + (i + 1)
}

func quickselect(arr, lo, hi, k) {
    if lo == hi { emit _qsl_get(arr, lo) }
    let p = _qsl_partition(arr, lo, hi)
    let cur = _qsl_arr(p)
    let pi  = _qsl_pivot(p)
    if k == pi { emit _qsl_get(cur, pi) }
    if k < pi  { emit quickselect(cur, lo, pi - 1, k) }
    emit quickselect(cur, pi + 1, hi, k)
}

func kthSmallest(lst, k) {
    emit quickselect(lst, 0, count(lst) - 1, k)
}

just run {
    kp("Quickselect (k-th smallest, 0-indexed)")
    kp("======================================")
    let a = "7,4,1,9,2,6,3,8,5"
    kp("  in: " + a)
    let i = 0
    while i < count(a) {
        kp("  k=" + i + " -> " + kthSmallest(a, i))
        i += 1
    }

    let dup = "3,1,4,1,5,9,2,6,5,3,5"
    kp("  in: " + dup)
    kp("  median (k=" + (count(dup)/2) + ") -> " + kthSmallest(dup, count(dup)/2))
}
