// Closure-aware functional helpers. Mirrors stdlib/fp.k API but
// receivers are typed `cb: closure` so lambdas with captures can be
// passed in.
//
// Usage choice:
//   k:fp   — receivers expect raw function pointers; lambdas WITHOUT
//            captures only; faster per-call (no envGet overhead).
//   k:fpc  — receivers expect closures; lambdas WITH captures only;
//            one envGet per dispatch.
//
// LIMITATION (2.0-alpha-3): a lambda is tagged `closure` only if its
// body references free vars. A capture-free lambda like
// `func(v) { emit toInt(v) * 2 }` is tagged `fp` and CANNOT be passed
// to k:fpc receivers (calling it crashes — fpc dispatch expects
// closure-shaped value, gets raw fp). The reverse is also true: a
// closure (env head) cannot be passed to k:fp.
//
// Rule of thumb:
//   - lambda touches an outer var          → use k:fpc
//   - lambda uses only its params           → use k:fp
//
//   import "k:fpc"
//
//   let n = 5
//   let scaled = fpcMap("1,2,3", func(v) { emit toInt(v) * n })
//
// Implementation detail: closures are env heads built by Krypton's
// native lambda lowering (see project_v20_alpha3.md). irCall
// dispatches `closure` typed locals through env extraction:
// `LOAD f; PUSH "__fp__"; envGet 2; LOAD f; <args>; callPtr (argc+2)`.
//
//   import "k:fpc"
//
//   let n = 5
//   let xs = "1,2,3,4,5"
//   let scaled = fpcMap(xs, func(v) { emit toInt(v) * n })   // captures n
//
// Implementation detail: closures are env heads built by Krypton's
// native lambda lowering (see project_v20_alpha3.md). irCall
// dispatches `closure` typed locals through env extraction:
// `LOAD f; PUSH "__fp__"; envGet 2; LOAD f; <args>; callPtr (argc+2)`.

module fpc


func fpcMap(list, cb: closure) {
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


func fpcFilter(list, pred: closure) {
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


func fpcReduce(list, initial, cb: closure) {
    let n = count(list)
    let acc = initial
    let i = 0
    while i < n {
        acc = cb(acc, split(list, i))
        i += 1
    }
    emit acc
}


func fpcEach(list, cb: closure) {
    let n = count(list)
    let i = 0
    while i < n {
        cb(split(list, i))
        i += 1
    }
}


func fpcFind(list, pred: closure) {
    let n = count(list)
    let i = 0
    while i < n {
        let elem = split(list, i)
        if isTruthy(pred(elem)) { emit elem }
        i += 1
    }
    emit ""
}


func fpcAny(list, pred: closure) {
    let n = count(list)
    let i = 0
    while i < n {
        if isTruthy(pred(split(list, i))) { emit "true" }
        i += 1
    }
    emit "false"
}


func fpcAll(list, pred: closure) {
    let n = count(list)
    let i = 0
    while i < n {
        if !isTruthy(pred(split(list, i))) { emit "false" }
        i += 1
    }
    emit "true"
}


func fpcCount(list, pred: closure) {
    let n = count(list)
    let c = 0
    let i = 0
    while i < n {
        if isTruthy(pred(split(list, i))) { c = c + 1 }
        i += 1
    }
    emit c
}
