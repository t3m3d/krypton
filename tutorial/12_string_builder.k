// Tutorial 12: String Builder
// Efficient string construction

just run {
    // sbNew() creates a new string builder
    let sb = sbNew()

    // sbAppend() appends to the builder
    sb = sbAppend(sb, "Hello")
    sb = sbAppend(sb, ", ")
    sb = sbAppend(sb, "World!")

    // sbToString() converts builder to final string
    let result = sbToString(sb)
    kp(result)

    // String builder for building output
    let output = sbNew()
    let i = 1
    while i <= 5 {
        output = sbAppend(output, "Line " + i + "\n")
        i = i + 1
    }
    kp(sbToString(output))

    // Building CSV data
    let csv = sbNew()
    csv = sbAppend(csv, "name,age,city\n")
    csv = sbAppend(csv, "Alice,30,NYC\n")
    csv = sbAppend(csv, "Bob,25,LA\n")
    csv = sbAppend(csv, "Carol,35,Chicago\n")
    kp("CSV Data:")
    kp(sbToString(csv))
}
