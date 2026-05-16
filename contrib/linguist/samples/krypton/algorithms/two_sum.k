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
            j += 1
        }
        i += 1
    }
    emit "-1,-1"
}

just run {
    let nums = "2,7,11,15"
    let target = 9
    kp("Numbers: " + nums)
    kp("Target: " + target)
    let result = twoSum(nums, target)
    let i = toInt(split(result, 0))
    let j = toInt(split(result, 1))
    if i >= 0 {
        kp("Found: [" + i + "," + j + "] => " + split(nums, i) + " + " + split(nums, j) + " = " + target)
    } else {
        kp("No solution found")
    }

    kp("")
    let nums2 = "3,2,4"
    let target2 = 6
    kp("Numbers: " + nums2)
    kp("Target: " + target2)
    let result2 = twoSum(nums2, target2)
    let i2 = toInt(split(result2, 0))
    let j2 = toInt(split(result2, 1))
    if i2 >= 0 {
        kp("Found: [" + i2 + "," + j2 + "] => " + split(nums2, i2) + " + " + split(nums2, j2) + " = " + target2)
    }
}
