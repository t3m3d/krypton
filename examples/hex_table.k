// Hex and binary table
// Demonstrates: for-in, range, hex, bin, padLeft, padRight, const

just run {
    const title = "Number Base Conversion Table"
    print(title)
    print(repeat("=", len(title)))

    // Header
    const header = padRight("Dec", 6, " ") + padRight("Hex", 8, " ") + "Bin"
    print(header)
    print(repeat("-", 28))

    // Print table for 0-31
    for n in range(0, 32) {
        const decStr = padRight(toStr(n), 6, " ")
        const hexStr = padRight("0x" + padLeft(hex(n), 2, "0"), 8, " ")
        const binStr = padLeft(bin(n), 8, "0")

        print(decStr + hexStr + binStr)
    }

    print(repeat("-", 28))

    // Show some larger values
    print("\nNotable values:")
    const notable = "64,127,128,255,256,1000,1024,65535"
    for n in notable {
        print("  " + padRight(n, 6, " ") + "= 0x" + hex(n) + " = " + bin(n) + "b")
    }
    emit "ok"
}
