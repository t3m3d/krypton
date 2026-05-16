// Functional helpers built on 2.0-alpha native lambdas.
//
// Lists are comma-separated strings (Krypton's standard list shape).
// Pass a lambda that takes the element string; convert inside if you
// need a numeric.
//
// Receiver params declared `cb: closure` so Krypton's native pipeline routes
// `cb(args)` through callPtr automatically — no explicit callPtr at the
// call site.
//
// Usage:
//   import "k:fp"
//   let xs = "1,2,3,4"
//   let doubled = fpMap(xs, func(x) { emit toInt(x) * 2 })
//   let evens   = fpFilter(xs, func(x) { emit toInt(x) % 2 == 0 })
//   let sum     = fpReduce(xs, "0", func(acc, x) { emit toInt(acc) + toInt(x) })

module fp


func fpMap(list, cb: closure) {
    let n = count(list)
    let result = ""
    let i = 0
    while i < n {
        let val = cb(split(list, i))
        if result == "" {
            result = "" + val
        } else {
            result = result + "," + val
        }
        i += 1
    }
    emit result
}


func fpFilter(list, pred: closure) {
    let n = count(list)
    let result = ""
    let i = 0
    while i < n {
        let elem = split(list, i)
        if isTruthy(pred(elem)) {
            if result == "" {
                result = "" + elem
            } else {
                result = result + "," + elem
            }
        }
        i += 1
    }
    emit result
}


func fpReduce(list, initial, cb: closure) {
    let n = count(list)
    let acc = initial
    let i = 0
    while i < n {
        acc = cb(acc, split(list, i))
        i += 1
    }
    emit acc
}


func fpEach(list, cb: closure) {
    let n = count(list)
    let i = 0
    while i < n {
        cb(split(list, i))
        i += 1
    }
}


func fpFind(list, pred: closure) {
    let n = count(list)
    let i = 0
    while i < n {
        let elem = split(list, i)
        if isTruthy(pred(elem)) { emit elem }
        i += 1
    }
    emit ""
}


func fpAny(list, pred: closure) {
    let n = count(list)
    let i = 0
    while i < n {
        if isTruthy(pred(split(list, i))) { emit "true" }
        i += 1
    }
    emit "false"
}


func fpAll(list, pred: closure) {
    let n = count(list)
    let i = 0
    while i < n {
        if !isTruthy(pred(split(list, i))) { emit "false" }
        i += 1
    }
    emit "true"
}


// fpZip(a, b): pair elements positionally → "a0:b0,a1:b1,...".
// Stops at min(len(a), len(b)).
func fpZip(a, b) {
    let na = count(a)
    let nb = count(b)
    let n  = na
    if nb < n { n = nb }
    let result = ""
    let i = 0
    while i < n {
        let pair = split(a, i) + ":" + split(b, i)
        if result == "" {
            result = pair
        } else {
            result = result + "," + pair
        }
        i += 1
    }
    emit result
}


// fpEnumerate(list): pair each element with its index → "0:a,1:b,...".
func fpEnumerate(list) {
    let n = count(list)
    let result = ""
    let i = 0
    while i < n {
        let pair = i + ":" + split(list, i)
        if result == "" {
            result = pair
        } else {
            result = result + "," + pair
        }
        i += 1
    }
    emit result
}


// fpTake(list, n): first n elements (or fewer if list is shorter).
func fpTake(list, n) {
    let total = count(list)
    let take = n
    if take > total { take = total }
    let result = ""
    let i = 0
    while i < take {
        if result == "" {
            result = split(list, i)
        } else {
            result = result + "," + split(list, i)
        }
        i += 1
    }
    emit result
}


// fpDrop(list, n): elements after the first n (or "" if n >= len).
func fpDrop(list, n) {
    let total = count(list)
    let result = ""
    let i = n
    while i < total {
        if result == "" {
            result = split(list, i)
        } else {
            result = result + "," + split(list, i)
        }
        i += 1
    }
    emit result
}


// fpCount(list, predicate): how many elements match.
func fpCount(list, pred: closure) {
    let n = count(list)
    let c = 0
    let i = 0
    while i < n {
        if isTruthy(pred(split(list, i))) { c = c + 1 }
        i += 1
    }
    emit c
}


// fpRange(start, end): "start,start+1,...,end-1" — comma-separated
// counterpart to the builtin range(). Useful when calling fpMap directly
// without going through `for in`.
func fpRange(start, end) {
    let result = ""
    let i = start
    while i < end {
        if result == "" {
            result = "" + i
        } else {
            result = result + "," + i
        }
        i = i + 1
    }
    emit result
}


// fpJoin(list, sep): re-join a comma-list using a different separator.
// Useful for printing or piping through string-shaped APIs.
func fpJoin(list, sep) {
    let n = count(list)
    let result = ""
    let i = 0
    while i < n {
        if result == "" {
            result = split(list, i)
        } else {
            result = result + sep + split(list, i)
        }
        i += 1
    }
    emit result
}
