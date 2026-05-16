// Exercise the new k:fp stdlib over native lambdas.

import "k:fp"

just run {
    let xs = "1,2,3,4,5"

    let doubled = fpMap(xs, func(x) { emit toInt(x) * 2 })
    print("map double  = " + doubled + "  (expect 2,4,6,8,10)")

    let evens = fpFilter(xs, func(x) { emit toInt(x) % 2 == 0 })
    print("filter even = " + evens + "  (expect 2,4)")

    let sum = fpReduce(xs, "0", func(acc, x) { emit toInt(acc) + toInt(x) })
    print("sum         = " + sum + "  (expect 15)")

    let product = fpReduce(xs, "1", func(acc, x) { emit toInt(acc) * toInt(x) })
    print("product     = " + product + "  (expect 120)")

    let firstBig = fpFind(xs, func(x) { emit toInt(x) > 3 })
    print("find >3     = " + firstBig + "  (expect 4)")

    let anyBig = fpAny(xs, func(x) { emit toInt(x) > 4 })
    print("any >4      = " + anyBig + "  (expect true)")

    let allPos = fpAll(xs, func(x) { emit toInt(x) > 0 })
    print("all >0      = " + allPos + "  (expect true)")

    let allBig = fpAll(xs, func(x) { emit toInt(x) > 2 })
    print("all >2      = " + allBig + "  (expect false)")

    print("each squared:")
    fpEach(xs, func(x) {
        let sq = toInt(x) * toInt(x)
        print("  " + x + " -> " + sq)
    })
}
