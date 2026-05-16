// List utilities for Krypton
// Lists are represented as comma-separated strings

module list_utils


// Create a new empty list
func listNew() {
    emit ""
}

// Append an item to the list
func listAppend(list, item) {
    if list == "" {
        emit item
    }
    emit list + "," + item
}

// Get item at index from a comma-separated list
func listGet(list, idx) {
    emit split(list, idx)
}

// Get the size of a list
func listSize(list) {
    if list == "" {
        emit 0
    }
    emit count(list)
}

// Check if list contains an item
func listContains(list, item) {
    let size = count(list)
    let i = 0
    while i < size {
        if split(list, i) == item {
            emit 1
        }
        i += 1
    }
    emit 0
}

// Find index of item in list, returns -1 if not found
func listIndexOf(list, item) {
    let size = count(list)
    let i = 0
    while i < size {
        if split(list, i) == item {
            emit i
        }
        i += 1
    }
    emit 0 - 1
}

// Reverse a list
func listReverse(list) {
    let size = count(list)
    let result = ""
    let i = size - 1
    while i >= 0 {
        let item = split(list, i)
        if result == "" {
            result = item
        } else {
            result = result + "," + item
        }
        i -= 1
    }
    emit result
}

// Take first n items from list
func listTake(list, n) {
    let size = count(list)
    let result = ""
    let i = 0
    while i < n {
        if i >= size {
            break
        }
        let item = split(list, i)
        if result == "" {
            result = item
        } else {
            result = result + "," + item
        }
        i += 1
    }
    emit result
}

// Drop first n items from list
func listDrop(list, n) {
    let size = count(list)
    let result = ""
    let i = n
    while i < size {
        let item = split(list, i)
        if result == "" {
            result = item
        } else {
            result = result + "," + item
        }
        i += 1
    }
    emit result
}

// Get the last item in a list
func listLast(list) {
    let size = count(list)
    emit split(list, size - 1)
}

// Get the first item in a list
func listFirst(list) {
    emit split(list, 0)
}

// Concatenate two lists
func listConcat(a, b) {
    if a == "" {
        emit b
    }
    if b == "" {
        emit a
    }
    emit a + "," + b
}

// Remove duplicates from a list
func listUnique(list) {
    let size = count(list)
    let result = ""
    let i = 0
    while i < size {
        let item = split(list, i)
        // Check if already in result
        let found = 0
        if result != "" {
            let rSize = count(result)
            let j = 0
            while j < rSize {
                if split(result, j) == item {
                    found = 1
                    break
                }
                j += 1
            }
        }
        if found == 0 {
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

// Sum all numeric items in a list
func listSum(list) {
    let size = count(list)
    let total = 0
    let i = 0
    while i < size {
        total = total + toInt(split(list, i))
        i += 1
    }
    emit total
}
