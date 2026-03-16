// Search algorithms for Krypton
// Works with comma-separated numeric lists

go search {

    // Linear search: returns index or -1
    func linearSearch(list, target) {
        let size = count(list)
        let i = 0
        while i < size {
            if split(list, i) == target {
                emit i
            }
            i += 1
        }
        emit 0 - 1
    }

    // Binary search on a sorted numeric list: returns index or -1
    func binarySearch(list, target) {
        let lo = 0
        let hi = count(list) - 1
        let tgt = toInt(target)
        while lo <= hi {
            let mid = (lo + hi) / 2
            let midVal = toInt(split(list, mid))
            if midVal == tgt {
                emit mid
            } else if midVal < tgt {
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        emit 0 - 1
    }

    // Find first occurrence of a value greater than target
    func upperBound(list, target) {
        let size = count(list)
        let lo = 0
        let hi = size
        let tgt = toInt(target)
        while lo < hi {
            let mid = (lo + hi) / 2
            if toInt(split(list, mid)) <= tgt {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        emit lo
    }

    // Find first occurrence of a value >= target
    func lowerBound(list, target) {
        let size = count(list)
        let lo = 0
        let hi = size
        let tgt = toInt(target)
        while lo < hi {
            let mid = (lo + hi) / 2
            if toInt(split(list, mid)) < tgt {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        emit lo
    }

    // Count occurrences of a value in a list
    func countOccurrences(list, target) {
        let size = count(list)
        let cnt = 0
        let i = 0
        while i < size {
            if split(list, i) == target {
                cnt += 1
            }
            i += 1
        }
        emit cnt
    }

    // Find all indices of target, returned as comma-separated list
    func findAll(list, target) {
        let size = count(list)
        let result = ""
        let i = 0
        while i < size {
            if split(list, i) == target {
                if result == "" {
                    result = "" + i
                } else {
                    result = result + "," + i
                }
            }
            i += 1
        }
        emit result
    }

    // Find the index of the minimum value
    func findMinIndex(list) {
        let size = count(list)
        let minIdx = 0
        let minVal = toInt(split(list, 0))
        let i = 1
        while i < size {
            let val = toInt(split(list, i))
            if val < minVal {
                minVal = val
                minIdx = i
            }
            i += 1
        }
        emit minIdx
    }

    // Find the index of the maximum value
    func findMaxIndex(list) {
        let size = count(list)
        let maxIdx = 0
        let maxVal = toInt(split(list, 0))
        let i = 1
        while i < size {
            let val = toInt(split(list, i))
            if val > maxVal {
                maxVal = val
                maxIdx = i
            }
            i += 1
        }
        emit maxIdx
    }
}
