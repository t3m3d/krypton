// Maximum Subarray (Kadane's Algorithm)

func maxSubarray(list) {
    let n = count(list)
    let maxSoFar = toInt(split(list, 0))
    let maxEndingHere = maxSoFar
    let i = 1
    while i < n {
        let val = toInt(split(list, i))
        if val > maxEndingHere + val {
            maxEndingHere = val
        } else {
            maxEndingHere = maxEndingHere + val
        }
        if maxEndingHere > maxSoFar {
            maxSoFar = maxEndingHere
        }
        i = i + 1
    }
    emit maxSoFar
}

just run {
    let data = "-2,1,-3,4,-1,2,1,-5,4"
    print("Array: " + data)
    print("Max subarray sum: " + maxSubarray(data))

    let data2 = "1,2,3,-2,5"
    print("")
    print("Array: " + data2)
    print("Max subarray sum: " + maxSubarray(data2))

    let data3 = "-1,-2,-3,-4"
    print("")
    print("Array: " + data3)
    print("Max subarray sum: " + maxSubarray(data3))
}
