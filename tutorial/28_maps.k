// Tutorial 28: Maps (Key-Value Pairs)
// k:map stores values under string keys.
//
// Like lists, a map is a plain string under the hood, so every "change"
// returns a NEW map — reassign the variable each time.

import "k:map"

just run {
    let ages = mapNew()
    ages = mapSet(ages, "alice", "30")
    ages = mapSet(ages, "bob", "25")
    ages = mapSet(ages, "carol", "41")

    print("alice      = " + mapGet(ages, "alice"))
    print("hasKey bob?  " + hasKey(ages, "bob"))
    print("hasKey dave? " + hasKey(ages, "dave"))
    print("keys       = " + keys(ages))
    print("values     = " + values(ages))
    print("count      = " + length(keys(ages)))

    // Setting an existing key overwrites its value.
    ages = mapSet(ages, "alice", "31")
    print("alice      = " + mapGet(ages, "alice"))
}
