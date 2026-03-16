// Collection utilities for Krypton
// Higher-order-style operations on comma-separated lists

go collections {

    // Apply operation to each element and build new list
    // (Since Krypton doesn't have first-class functions,
    //  these are specialized for common operations)

    // Double every numeric element
    func mapDouble(list) {
        let size = count(list)
        let result = ""
        let i = 0
        while i < size {
            let val = toInt(split(list, i)) * 2
            if result == "" {
                result = "" + val
            } else {
                result = result + "," + val
            }
            i += 1
        }
        emit result
    }

    // Square every numeric element
    func mapSquare(list) {
        let size = count(list)
        let result = ""
        let i = 0
        while i < size {
            let val = toInt(split(list, i))
            let sq = val * val
            if result == "" {
                result = "" + sq
            } else {
                result = result + "," + sq
            }
            i += 1
        }
        emit result
    }

    // Negate every numeric element
    func mapNegate(list) {
        let size = count(list)
        let result = ""
        let i = 0
        while i < size {
            let val = 0 - toInt(split(list, i))
            if result == "" {
                result = "" + val
            } else {
                result = result + "," + val
            }
            i += 1
        }
        emit result
    }

    // Filter: keep only positive numbers
    func filterPositive(list) {
        let size = count(list)
        let result = ""
        let i = 0
        while i < size {
            let val = toInt(split(list, i))
            if val > 0 {
                if result == "" {
                    result = "" + val
                } else {
                    result = result + "," + val
                }
            }
            i += 1
        }
        emit result
    }

    // Filter: keep only even numbers
    func filterEven(list) {
        let size = count(list)
        let result = ""
        let i = 0
        while i < size {
            let val = toInt(split(list, i))
            if val % 2 == 0 {
                if result == "" {
                    result = "" + val
                } else {
                    result = result + "," + val
                }
            }
            i += 1
        }
        emit result
    }

    // Filter: keep only odd numbers
    func filterOdd(list) {
        let size = count(list)
        let result = ""
        let i = 0
        while i < size {
            let val = toInt(split(list, i))
            if val % 2 != 0 {
                if result == "" {
                    result = "" + val
                } else {
                    result = result + "," + val
                }
            }
            i += 1
        }
        emit result
    }

    // Reduce: sum all elements
    func reduceSum(list) {
        let size = count(list)
        let total = 0
        let i = 0
        while i < size {
            total = total + toInt(split(list, i))
            i += 1
        }
        emit total
    }

    // Reduce: product of all elements
    func reduceProduct(list) {
        let size = count(list)
        let product = 1
        let i = 0
        while i < size {
            product = product * toInt(split(list, i))
            i += 1
        }
        emit product
    }

    // Check if all elements satisfy a condition (all positive)
    func allPositive(list) {
        let size = count(list)
        let i = 0
        while i < size {
            if toInt(split(list, i)) <= 0 {
                emit 0
            }
            i += 1
        }
        emit 1
    }

    // Check if any element satisfies a condition (any zero)
    func anyZero(list) {
        let size = count(list)
        let i = 0
        while i < size {
            if toInt(split(list, i)) == 0 {
                emit 1
            }
            i += 1
        }
        emit 0
    }

    // Zip two lists into pairs
    func zip(a, b) {
        let aSize = count(a)
        let bSize = count(b)
        let size = aSize
        if bSize < size {
            size = bSize
        }
        let result = ""
        let i = 0
        while i < size {
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
}
