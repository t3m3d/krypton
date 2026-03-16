// Set operations for Krypton
// Sets are comma-separated lists with unique elements

go set {

    // Create a new empty set
    func setNew() {
        emit ""
    }

    // Add an element to the set
    func setAdd(s, item) {
        // Check if already present
        if s == "" {
            emit item
        }
        let size = count(s)
        let i = 0
        while i < size {
            if split(s, i) == item {
                emit s
            }
            i += 1
        }
        emit s + "," + item
    }

    // Remove an element from the set
    func setRemove(s, item) {
        let size = count(s)
        let result = ""
        let i = 0
        while i < size {
            let elem = split(s, i)
            if elem != item {
                if result == "" {
                    result = elem
                } else {
                    result = result + "," + elem
                }
            }
            i += 1
        }
        emit result
    }

    // Check if set contains an element
    func setContains(s, item) {
        if s == "" {
            emit 0
        }
        let size = count(s)
        let i = 0
        while i < size {
            if split(s, i) == item {
                emit 1
            }
            i += 1
        }
        emit 0
    }

    // Get set size
    func setSize(s) {
        if s == "" {
            emit 0
        }
        emit count(s)
    }

    // Union of two sets
    func setUnion(a, b) {
        let result = a
        if b == "" {
            emit result
        }
        let bSize = count(b)
        let i = 0
        while i < bSize {
            result = setAdd(result, split(b, i))
            i += 1
        }
        emit result
    }

    // Intersection of two sets
    func setIntersect(a, b) {
        let result = ""
        if a == "" {
            emit result
        }
        if b == "" {
            emit result
        }
        let aSize = count(a)
        let i = 0
        while i < aSize {
            let item = split(a, i)
            if setContains(b, item) {
                if result == "" {
                    result = item
                } else {
                    result = result + "," + item
                }
            }
            i += 1
        }
        emit result
    }

    // Difference: elements in a but not in b
    func setDifference(a, b) {
        let result = ""
        if a == "" {
            emit result
        }
        let aSize = count(a)
        let i = 0
        while i < aSize {
            let item = split(a, i)
            if setContains(b, item) == 0 {
                if result == "" {
                    result = item
                } else {
                    result = result + "," + item
                }
            }
            i += 1
        }
        emit result
    }

    // Check if a is a subset of b
    func setIsSubset(a, b) {
        if a == "" {
            emit 1
        }
        let aSize = count(a)
        let i = 0
        while i < aSize {
            if setContains(b, split(a, i)) == 0 {
                emit 0
            }
            i += 1
        }
        emit 1
    }

    // Check if two sets are equal
    func setEqual(a, b) {
        if setIsSubset(a, b) {
            if setIsSubset(b, a) {
                emit 1
            }
        }
        emit 0
    }

    // Print set elements
    func setPrint(s) {
        kp("{" + s + "}")
    }
}
