// Tutorial 30: Building JSON
// k:json turns Krypton values into JSON strings.

import "k:json"
import "k:map"

just run {
    // Scalars
    print(jsonStr("hello"))            // "hello"
    print(jsonNum(42))                 // 42
    print(jsonBool("1"))               // true
    print(jsonNull())                  // null

    // jsonStr escapes quotes and backslashes for you.
    print(jsonStr("she said \"hi\""))

    // Arrays come from a comma-list.
    print(jsonArray("apple,banana,cherry"))

    // Objects come from a map.
    let person = mapNew()
    person = mapSet(person, "name", "Alice")
    person = mapSet(person, "city", "Paris")
    print(jsonObject(person))
}
