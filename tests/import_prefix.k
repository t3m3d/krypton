// 1.8.4: Odin-style import prefixes.
// k:/core:  → stdlib (.k)
// head:/headers: → headers (.krh)

import "k:fs"
import "core:json_emit"
import "head:user32"

just run {
    print("import prefixes work: k:/core:/head:")
}
