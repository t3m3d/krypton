// Functional helpers built on 2.0-alpha native lambdas.
//
// Lists are comma-separated strings (Krypton's standard list shape).
// Pass a lambda that takes the element string; convert inside if you
// need a numeric.
//
// Receiver params declared `cb: fp` so Krypton's native pipeline routes
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


func fpMap(list, cb: fp) {
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


func fpFilter(list, pred: fp) {
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


func fpReduce(list, initial, cb: fp) {
    let n = count(list)
    let acc = initial
    let i = 0
    while i < n {
        acc = cb(acc, split(list, i))
        i += 1
    }
    emit acc
}


func fpEach(list, cb: fp) {
    let n = count(list)
    let i = 0
    while i < n {
        cb(split(list, i))
        i += 1
    }
}


func fpFind(list, pred: fp) {
    let n = count(list)
    let i = 0
    while i < n {
        let elem = split(list, i)
        if isTruthy(pred(elem)) { emit elem }
        i += 1
    }
    emit ""
}


func fpAny(list, pred: fp) {
    let n = count(list)
    let i = 0
    while i < n {
        if isTruthy(pred(split(list, i))) { emit "true" }
        i += 1
    }
    emit "false"
}


func fpAll(list, pred: fp) {
    let n = count(list)
    let i = 0
    while i < n {
        if !isTruthy(pred(split(list, i))) { emit "false" }
        i += 1
    }
    emit "true"
}
