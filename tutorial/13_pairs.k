// Tutorial 13: Pairs
// Using pairs for key-value data

just run {
    // Pairs store a value and a position as "value,position"
    let token = "hello,0"

    // Extract parts with pairVal and pairPos
    print("Value: " + pairVal(token))
    print("Position: " + pairPos(token))

    // Create pairs
    let name = "Alice"
    let age = 30
    let person = name + "," + age
    print("Person: " + pairVal(person) + " (age " + pairPos(person) + ")")

    // Pairs in a loop (simulating token positions)
    let words = "the,0 quick,4 brown,10 fox,16"
    let items = "the,0,quick,4,brown,10,fox,16"
    let i = 0
    while i < 4 {
        let word = split(items, i * 2)
        let pos = split(items, i * 2 + 1)
        let pair = word + "," + pos
        print("  Token '" + pairVal(pair) + "' at position " + pairPos(pair))
        i = i + 1
    }
}
