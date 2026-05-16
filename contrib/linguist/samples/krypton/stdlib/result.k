// result.k — Result type for error handling without exceptions
// A Result is either "ok:VALUE" or "err:MESSAGE"

module result

func ok(val) {
    emit "ok:" + val
}

func err(msg) {
    emit "err:" + msg
}

func isOk(result) {
    emit startsWith(result, "ok:")
}

func isErr(result) {
    emit startsWith(result, "err:")
}

func unwrap(result) {
    if startsWith(result, "ok:") {
        emit substring(result, 3, len(result))
    }
    print("ERROR: unwrap called on Err result: " + result)
    exit(1)
    emit ""
}

func unwrapErr(result) {
    if startsWith(result, "err:") {
        emit substring(result, 4, len(result))
    }
    print("ERROR: unwrapErr called on Ok result: " + result)
    exit(1)
    emit ""
}

func unwrapOr(result, default) {
    if startsWith(result, "ok:") {
        emit substring(result, 3, len(result))
    }
    emit default
}

func resultMap(result, func_name) {
    if startsWith(result, "err:") { emit result }
    let val = substring(result, 3, len(result))
    emit ok(val)
}
