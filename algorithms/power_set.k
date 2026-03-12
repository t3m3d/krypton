// Power Set - Generate all subsets of a set

func powerSet(elements) {
    let n = len(elements)
    // 2^n subsets
    let total = 1
    let i = 0
    while i < n {
        total = total * 2
        i = i + 1
    }

    print("Power set of {" + elements + "} (" + total + " subsets):")

    let mask = 0
    while mask < total {
        let sb = sbNew()
        sb = sbAppend(sb, "{")
        let first = 1
        i = 0
        while i < n {
            // Check if bit i is set in mask
            let bit = mask
            let j = 0
            while j < i {
                bit = bit / 2
                j = j + 1
            }
            if bit % 2 == 1 {
                if !first { sb = sbAppend(sb, ",") }
                sb = sbAppend(sb, elements[i])
                first = 0
            }
            i = i + 1
        }
        sb = sbAppend(sb, "}")
        print("  " + sbToString(sb))
        mask = mask + 1
    }
}

just run {
    powerSet("ABC")
}
