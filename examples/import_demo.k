// import_demo.k — demonstrates the module system

module main

import "stdlib/result.k"
import "stdlib/math_utils.k"
import "stdlib/json.k"

func safeSqrt(n) {
    if n < 0 {
        emit err("cannot take sqrt of negative number")
    }
    emit ok(sqrt(toInt(n)) + "")
}

func buildStats(numbers) {
    let m = ""
    m = mapSet(m, "count", length(numbers) + "")
    m = mapSet(m, "sum", sumList(numbers) + "")
    m = mapSet(m, "min", minList(numbers) + "")
    m = mapSet(m, "max", maxList(numbers) + "")
    m = mapSet(m, "sorted", sort(numbers))
    emit m
}

just run {
    kp("=== Module System Demo ===")

    // Using result.k
    let r1 = safeSqrt("144")
    let r2 = safeSqrt("-5")

    if isOk(r1) {
        kp(`sqrt(144) = {unwrap(r1)}`)
    }
    if isErr(r2) {
        kp(`error: {unwrapErr(r2)}`)
    }

    // Using math_utils.k
    kp(`gcd(48, 18) = {gcd(48, 18)}`)
    kp(`isPrime(17) = {isPrime(17)}`)
    kp(`fibonacci(10) = {fibonacci(10)}`)

    // Using json.k
    let stats = buildStats("5,3,9,1,7,2,8,4,6")
    kp("")
    kp("Stats as JSON:")
    kp(jsonObject(stats))

    // Array of results
    let nums = [4, 9, 16, 25, 36]
    kp("")
    kp("Square roots:")
    for n in nums {
        let r = safeSqrt(n)
        kp(`  sqrt({n}) = {unwrap(r)}`)
    }
}
