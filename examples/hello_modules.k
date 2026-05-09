// hello_modules.k — simplest possible import example

module hello

import "k:math_utils"
import "k:string_utils"

just run {
    kp("=== Hello Modules ===")

    // From math_utils.k
    kp(`isPrime(7) = {isPrime(7)}`)
    kp(`factorial(6) = {factorial(6)}`)
    kp(`gcd(24, 36) = {gcd(24, 36)}`)

    // From string_utils.k
    let s = "  hello krypton  "
    kp(`trimmed: "{trim(s)}"`)
    kp(`upper: {toUpper(trim(s))}`)
    kp(`reversed: {reverse("krypton")}`)
}
