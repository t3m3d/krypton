// Exercise the new k:fp helpers (zip/enumerate/take/drop/count/range/join).

import "k:fp"

just run {
    let xs = "10,20,30,40,50"
    let ys = "a,b,c"

    print("zip       = " + fpZip(xs, ys) + "  (expect 10:a,20:b,30:c)")
    print("enumerate = " + fpEnumerate(ys) + "  (expect 0:a,1:b,2:c)")
    print("take 3    = " + fpTake(xs, 3) + "  (expect 10,20,30)")
    print("drop 3    = " + fpDrop(xs, 3) + "  (expect 40,50)")
    print("count >25 = " + fpCount(xs, func(v) { emit toInt(v) > 25 }) + "  (expect 3)")
    print("fpRange   = " + fpRange(0, 5) + "  (expect 0,1,2,3,4)")
    print("join '|'  = " + fpJoin(ys, "|") + "  (expect a|b|c)")

    // Compose: take 3, double each, sum
    let result = fpReduce(
        fpMap(fpTake(xs, 3), func(v) { emit toInt(v) * 2 }),
        "0",
        func(acc, v) { emit toInt(acc) + toInt(v) }
    )
    print("composed  = " + result + "  (expect 120 = 2*(10+20+30))")
}
