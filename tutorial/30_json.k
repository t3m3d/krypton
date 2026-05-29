// Tutorial 30: Building JSON
// k:json turns Krypton values into JSON strings.

import "k:json"
import "k:map"

just run {
    // Scalars
    kp(jsonStr("hello"))            // "hello"
    kp(jsonNum(42))                 // 42
    kp(jsonBool("1"))               // true
    kp(jsonNull())                  // null

    // jsonStr escapes quotes and backslashes for you.
    kp(jsonStr("she said \"hi\""))

    // Arrays come from a comma-list.
    kp(jsonArray("apple,banana,cherry"))

    // Objects come from a map.
    let person = mapNew()
    person = mapSet(person, "name", "Alice")
    person = mapSet(person, "city", "Paris")
    kp(jsonObject(person))
}
