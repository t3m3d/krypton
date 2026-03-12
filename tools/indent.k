// indent - Add or remove indentation from code

just run {
    if argCount() < 2 {
        print("Usage: indent <spaces> <file>")
        print("  Use positive number to indent, negative to dedent")
    } else {
        let spaces = toInt(arg(0))
        let content = readFile(arg(1))
        let lc = lineCount(content)
        let i = 0
        while i < lc {
            let line = getLine(content, i)
            if spaces > 0 {
                // Add indent
                let pad = ""
                let j = 0
                while j < spaces {
                    pad = pad + " "
                    j = j + 1
                }
                print(pad + line)
            } else if spaces < 0 {
                // Remove indent
                let remove = 0 - spaces
                if len(line) >= remove {
                    // Check if it's all spaces
                    let allSpaces = 1
                    let j = 0
                    while j < remove {
                        if line[j] != " " {
                            allSpaces = 0
                            break
                        }
                        j = j + 1
                    }
                    if allSpaces {
                        print(substring(line, remove, len(line)))
                    } else {
                        print(line)
                    }
                } else {
                    print(line)
                }
            } else {
                print(line)
            }
            i = i + 1
        }
    }
}
