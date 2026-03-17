// option.k — Option type for nullable values
// An Option is either "some:VALUE" or "none"

module option

func optSome(val) {
    emit "some:" + val
}

func optNone() {
    emit "none"
}

func isSome(opt) {
    emit startsWith(opt, "some:")
}

func isNone(opt) {
    emit opt == "none"
}

func optUnwrap(opt) {
    if startsWith(opt, "some:") {
        emit substring(opt, 5, len(opt))
    }
    print("ERROR: optUnwrap called on None")
    exit(1)
    emit ""
}

func optUnwrapOr(opt, default) {
    if startsWith(opt, "some:") {
        emit substring(opt, 5, len(opt))
    }
    emit default
}

func optMap(opt, val) {
    if opt == "none" { emit "none" }
    emit optSome(val)
}
