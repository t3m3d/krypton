// Tutorial 27: Using the Standard Library
// Pull in stdlib modules with: import "k:<module>"
//
// Lesson 17 showed 'go' blocks for grouping your own code. Here we use
// modules someone else already wrote — they live in stdlib/ and are
// imported with the "k:" prefix.

import "k:list_utils"
import "k:math_utils"

just run {
    // list_utils gives growable-list helpers. A list is just a
    // comma-separated string under the hood.
    let nums = listNew()
    nums = listAppend(nums, 3)
    nums = listAppend(nums, 1)
    nums = listAppend(nums, 2)
    kp("list:    " + nums)
    kp("size:    " + listSize(nums))
    kp("sum:     " + listSum(nums))
    kp("reverse: " + listReverse(nums))

    // math_utils gives number helpers.
    kp("gcd(48,36):    " + gcd(48, 36))
    kp("clamp(15,0,10): " + clamp(15, 0, 10))
    kp("isPrime(17):   " + isPrime(17))
}
