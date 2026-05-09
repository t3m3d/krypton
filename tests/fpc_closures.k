// fpc.k closure-aware variants. ALL lambdas in this test capture at
// least one outer var so they're tagged `closure`. Capture-free
// lambdas would crash (use k:fp for those — see fpc.k header).

import "k:fpc"

just run {
    let xs = "1,2,3,4,5"

    let n = 10
    let scaled = fpcMap(xs, func(v) { emit toInt(v) * n })
    print("scaled by 10: " + scaled + "  (expect 10,20,30,40,50)")

    let prefix = "item-"
    let labeled = fpcMap(xs, func(v) { emit prefix + v })
    print("labeled: " + labeled + "  (expect item-1,item-2,item-3,item-4,item-5)")

    let threshold = 3
    let big = fpcFilter(xs, func(v) { emit toInt(v) > threshold })
    print("> 3: " + big + "  (expect 4,5)")

    let mult = 2
    let total = fpcReduce(xs, "0", func(acc, v) { emit toInt(acc) + toInt(v) * mult })
    print("sum*mult: " + total + "  (expect 30 = 2*(1+2+3+4+5))")

    let bonus = 100
    let anyBig = fpcAny(xs, func(v) { emit toInt(v) > bonus })
    print("any > 100: " + anyBig + "  (expect false)")

    let posCheck = 0
    let allPos = fpcAll(xs, func(v) { emit toInt(v) > posCheck })
    print("all > 0:   " + allPos + "  (expect true)")

    let countThresh = 2
    let cnt = fpcCount(xs, func(v) { emit toInt(v) > countThresh })
    print("count > 2: " + cnt + "  (expect 3)")

    let target = 3
    let found = fpcFind(xs, func(v) { emit toInt(v) == target })
    print("find = 3:  " + found + "  (expect 3)")

    let mark = "[hit]"
    print("each:")
    fpcEach(xs, func(v) { print("  " + mark + " " + v) })
}
