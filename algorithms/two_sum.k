// Two Sum - Find two numbers that add to target

func twoSum(list, target) {
    let n = count(list)
    let i = 0
    while i < n {
        let j = i + 1
        while j < n {
            let a = toInt(split(list, i))
            let b = toInt(split(list, j))
            if a + b == target {
                emit "" + i + "," + j
            }
            j = j + 1
        }
        i = i + 1
    }
    emit "-1,-1"
}

just run {
    let nums = "2,7,11,15"
    let target = 9
    print("Numbers: " + nums)
    print("Target: " + target)
    let result = twoSum(nums, target)
    let i = toInt(split(result, 0))
    let j = toInt(split(result, 1))
    if i >= 0 {
        print("Found: [" + i + "," + j + "] => " + split(nums, i) + " + " + split(nums, j) + " = " + target)
    } else {
        print("No solution found")
    }

    print("")
    let nums2 = "3,2,4"
    let target2 = 6
    print("Numbers: " + nums2)
    print("Target: " + target2)
    let result2 = twoSum(nums2, target2)
    let i2 = toInt(split(result2, 0))
    let j2 = toInt(split(result2, 1))
    if i2 >= 0 {
        print("Found: [" + i2 + "," + j2 + "] => " + split(nums2, i2) + " + " + split(nums2, j2) + " = " + target2)
    }
}
