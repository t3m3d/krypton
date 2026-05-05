// native_extras.k — list/map helpers under their short names
// Native pipeline doesn't bundle these as builtins. Import this file to
// get sort/slice/join/zip/keys/values/etc. Functions intentionally use
// the same NAMES that compile.k recognises as builtins, so on the C path
// these definitions are silently ignored (the `kr_*` C wrappers win) and
// on the native path they take over.

module native_extras


func join(list, sep) {
    if list == "" { emit "" }
    let sb = sbNew()
    let total = count(list)
    let i = 0
    while i < total {
        if i > 0 { sb = sbAppend(sb, sep) }
        sb = sbAppend(sb, split(list, i))
        i = i + 1
    }
    emit sbToString(sb)
}

func slice(list, start, end) {
    if list == "" { emit "" }
    let s = toInt(start)
    let e = toInt(end)
    let n = count(list)
    if s < 0 { s = 0 }
    if e > n { e = n }
    if s >= e { emit "" }
    let sb = sbNew()
    let i = s
    while i < e {
        if i > s { sb = sbAppend(sb, ",") }
        sb = sbAppend(sb, split(list, i))
        i = i + 1
    }
    emit sbToString(sb)
}

func splitBy(s, sep) {
    if s == "" { emit "" }
    if sep == "" { emit s }
    let sb = sbNew()
    let n = len(s)
    let m = len(sep)
    let last = 0
    let first = 1
    let i = 0
    while i <= n - m {
        if substring(s, i, i + m) == sep {
            if !first { sb = sbAppend(sb, ",") }
            sb = sbAppend(sb, substring(s, last, i))
            first = 0
            i = i + m
            last = i
        } else {
            i = i + 1
        }
    }
    if !first { sb = sbAppend(sb, ",") }
    sb = sbAppend(sb, substring(s, last, n))
    emit sbToString(sb)
}

func sumList(list) {
    if list == "" { emit 0 }
    let n = count(list)
    let sum = 0
    let i = 0
    while i < n {
        sum = sum + toInt(split(list, i))
        i = i + 1
    }
    emit sum
}

func minList(list) {
    if list == "" { emit 0 }
    let n = count(list)
    if n == 0 { emit 0 }
    let m = toInt(split(list, 0))
    let i = 1
    while i < n {
        let v = toInt(split(list, i))
        if v < m { m = v }
        i = i + 1
    }
    emit m
}

func maxList(list) {
    if list == "" { emit 0 }
    let n = count(list)
    if n == 0 { emit 0 }
    let m = toInt(split(list, 0))
    let i = 1
    while i < n {
        let v = toInt(split(list, i))
        if v > m { m = v }
        i = i + 1
    }
    emit m
}

func countOf(list, item) {
    if list == "" { emit 0 }
    let n = count(list)
    let c = 0
    let i = 0
    while i < n {
        if split(list, i) == item { c = c + 1 }
        i = i + 1
    }
    emit c
}

func unique(list) {
    if list == "" { emit "" }
    let n = count(list)
    let acc = ""
    let i = 0
    while i < n {
        let item = split(list, i)
        let already = 0
        let na = 0
        if acc != "" { na = count(acc) }
        let j = 0
        while j < na {
            if split(acc, j) == item { already = 1 }
            j = j + 1
        }
        if !already {
            if acc == "" {
                acc = item
            } else {
                acc = acc + "," + item
            }
        }
        i = i + 1
    }
    emit acc
}

func keys(m) {
    if m == "" { emit "" }
    let n = count(m)
    let sb = sbNew()
    let i = 0
    let first = 1
    while i < n {
        if !first { sb = sbAppend(sb, ",") }
        sb = sbAppend(sb, split(m, i))
        first = 0
        i = i + 2
    }
    emit sbToString(sb)
}

func values(m) {
    if m == "" { emit "" }
    let n = count(m)
    let sb = sbNew()
    let i = 1
    let first = 1
    while i < n {
        if !first { sb = sbAppend(sb, ",") }
        sb = sbAppend(sb, split(m, i))
        first = 0
        i = i + 2
    }
    emit sbToString(sb)
}

func hasKey(m, k) {
    if m == "" { emit "0" }
    let n = count(m)
    let i = 0
    while i < n {
        if split(m, i) == k { emit "1" }
        i = i + 2
    }
    emit "0"
}

func mapGet(m, k) {
    if m == "" { emit "" }
    let n = count(m)
    let i = 0
    while i < n {
        if split(m, i) == k { emit split(m, i + 1) }
        i = i + 2
    }
    emit ""
}

func mapSet(m, k, v) {
    if m == "" { emit k + "," + v }
    let n = count(m)
    let i = 0
    while i < n {
        if split(m, i) == k {
            let sb = sbNew()
            let j = 0
            while j < n {
                if j > 0 { sb = sbAppend(sb, ",") }
                if j == i + 1 {
                    sb = sbAppend(sb, v)
                } else {
                    sb = sbAppend(sb, split(m, j))
                }
                j = j + 1
            }
            emit sbToString(sb)
        }
        i = i + 2
    }
    emit m + "," + k + "," + v
}

func remove(list, item) {
    if list == "" { emit "" }
    let n = count(list)
    let sb = sbNew()
    let first = 1
    let i = 0
    while i < n {
        let cur = split(list, i)
        if cur != item {
            if !first { sb = sbAppend(sb, ",") }
            sb = sbAppend(sb, cur)
            first = 0
        }
        i = i + 1
    }
    emit sbToString(sb)
}

func fill(n_str, value) {
    let n = toInt(n_str)
    if n <= 0 { emit "" }
    let sb = sbNew()
    let i = 0
    while i < n {
        if i > 0 { sb = sbAppend(sb, ",") }
        sb = sbAppend(sb, value)
        i = i + 1
    }
    emit sbToString(sb)
}

func zip(a, b) {
    if a == "" { emit "" }
    if b == "" { emit "" }
    let na = count(a)
    let nb = count(b)
    let m = na
    if nb < na { m = nb }
    let sb = sbNew()
    let first = 1
    let i = 0
    while i < m {
        if !first { sb = sbAppend(sb, ",") }
        sb = sbAppend(sb, split(a, i))
        sb = sbAppend(sb, ",")
        sb = sbAppend(sb, split(b, i))
        first = 0
        i = i + 1
    }
    emit sbToString(sb)
}

func sign(n_str) {
    let n = toInt(n_str)
    if n > 0 { emit 1 }
    if n < 0 { emit -1 }
    emit 0
}

func clamp(v_str, lo_str, hi_str) {
    let v = toInt(v_str)
    let lo = toInt(lo_str)
    let hi = toInt(hi_str)
    if v < lo { emit lo }
    if v > hi { emit hi }
    emit v
}

func parseInt(s) {
    emit toInt(s)
}

// Lex compare for sort: returns 1 if a < b lexicographically
func _lexLT(a, b) {
    let i = 0
    let la = len(a)
    let lb = len(b)
    while i < la {
        if i >= lb { emit 0 }
        let ca = charCode(substring(a, i, i + 1))
        let cb = charCode(substring(b, i, i + 1))
        if ca < cb { emit 1 }
        if ca > cb { emit 0 }
        i = i + 1
    }
    if la < lb { emit 1 }
    emit 0
}

func sort(list) {
    if list == "" { emit "" }
    let n = count(list)
    if n <= 1 { emit list }
    let arr = list
    let i = 0
    while i < n - 1 {
        let j = 0
        while j < n - 1 - i {
            let a = split(arr, j)
            let b = split(arr, j + 1)
            if _lexLT(b, a) {
                let sb = sbNew()
                let k = 0
                while k < n {
                    if k > 0 { sb = sbAppend(sb, ",") }
                    if k == j {
                        sb = sbAppend(sb, b)
                    } else {
                        if k == j + 1 {
                            sb = sbAppend(sb, a)
                        } else {
                            sb = sbAppend(sb, split(arr, k))
                        }
                    }
                    k = k + 1
                }
                arr = sbToString(sb)
            }
            j = j + 1
        }
        i = i + 1
    }
    emit arr
}

// every(list, item) — return 1 if all items equal item, else 0
func every(list, item) {
    if list == "" { emit 1 }
    let n = count(list)
    let i = 0
    while i < n {
        if split(list, i) != item { emit 0 }
        i = i + 1
    }
    emit 1
}

// some(list, item) — return 1 if any item equals item, else 0
func some(list, item) {
    if list == "" { emit 0 }
    let n = count(list)
    let i = 0
    while i < n {
        if split(list, i) == item { emit 1 }
        i = i + 1
    }
    emit 0
}

// listIndexOf — return index of item in list, or -1
func listIndexOf(list, item) {
    if list == "" { emit -1 }
    let n = count(list)
    let i = 0
    while i < n {
        if split(list, i) == item { emit i }
        i = i + 1
    }
    emit -1
}
