// avg - Compute average of numbers from a file

just run {
    if argCount() < 1 {
        print("Usage: avg <file>")
        print("File should contain one number per line")
    } else {
        let content = readFile(arg(0))
        let lc = lineCount(content)
        let total = 0
        let count = 0
        let i = 0
        while i < lc {
            let line = getLine(content, i)
            if len(line) > 0 {
                total = total + toInt(line)
                count = count + 1
            }
            i = i + 1
        }
        if count > 0 {
            let avg = total / count
            print("Count: " + count)
            print("Sum: " + total)
            print("Average (integer): " + avg)
        } else {
            print("No numbers found")
        }
    }
}
