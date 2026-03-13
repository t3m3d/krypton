# Krypton Built-in Functions Reference

Complete reference for all 72 built-in functions in Krypton v0.5.0.

All values in Krypton are strings. Functions that operate on numbers parse their arguments with `atoi` and return numeric strings. Lists are comma-separated strings (`"a,b,c"`). Maps are interleaved key-value lists (`"name,Alice,age,30"`).

---

## I/O

### print(s) / kp(s)
Prints `s` followed by a newline to stdout.
```krypton
print("hello")    // prints: hello
kp("world")       // prints: world
```

### printErr(s)
Prints `s` followed by a newline to stderr.
```krypton
printErr("warning: something happened")
```

### readLine(prompt)
Displays `prompt` then reads a line from stdin. Returns the input without the trailing newline.
```krypton
let name = readLine("Enter your name: ")
```

### input()
Reads a line from stdin (no prompt). Returns the input without the trailing newline.
```krypton
let line = input()
```

### readFile(path)
Reads the entire contents of a file. Returns empty string if the file doesn't exist.
```krypton
let src = readFile("hello.k")
print(len(src) + " bytes")
```

### writeFile(path, data)
Writes `data` to the file at `path`. Returns `"1"` on success, `"0"` on failure.
```krypton
writeFile("output.txt", "hello world")
```

### arg(n)
Returns command-line argument at index `n` (0-based, after the program name).
```krypton
let filename = arg(0)
```

### argCount()
Returns the number of command-line arguments (excluding the program name).
```krypton
if argCount() < 1 {
    print("Usage: program <file>")
}
```

---

## Strings

### len(s)
Returns the length of string `s`.
```krypton
len("hello")     // "5"
```

### substring(s, start, end)
Returns the substring from index `start` (inclusive) to `end` (exclusive).
```krypton
substring("hello", 1, 4)    // "ell"
```

### charAt(s, i)
Returns the character at index `i`. Returns empty string if out of bounds.
```krypton
charAt("hello", 0)    // "h"
charAt("hello", 4)    // "o"
```

### indexOf(s, sub)
Returns the index of the first occurrence of `sub` in `s`, or `"-1"` if not found.
```krypton
indexOf("hello world", "world")    // "6"
indexOf("hello", "xyz")            // "-1"
```

### contains(s, sub)
Returns `"1"` if `s` contains `sub`, `"0"` otherwise.
```krypton
contains("hello world", "world")    // "1"
```

### startsWith(s, prefix)
Returns `"1"` if `s` starts with `prefix`.
```krypton
startsWith("hello", "hel")    // "1"
```

### endsWith(s, suffix)
Returns `"1"` if `s` ends with `suffix`.
```krypton
endsWith("hello.k", ".k")    // "1"
```

### replace(s, old, new)
Replaces all occurrences of `old` with `new` in `s`.
```krypton
replace("hello world", "world", "krypton")    // "hello krypton"
```

### trim(s)
Removes leading and trailing whitespace (spaces, tabs, newlines).
```krypton
trim("  hello  ")    // "hello"
```

### toLower(s)
Converts to lowercase.
```krypton
toLower("Hello World")    // "hello world"
```

### toUpper(s)
Converts to uppercase.
```krypton
toUpper("hello")    // "HELLO"
```

### repeat(s, n)
Returns `s` repeated `n` times.
```krypton
repeat("ab", 3)    // "ababab"
repeat("-", 20)    // "--------------------"
```

### padLeft(s, width, pad)
Left-pads `s` to `width` using `pad` character(s). No-op if `s` is already wide enough.
```krypton
padLeft("42", 5, "0")     // "00042"
padLeft("hi", 6, ".")     // "....hi"
```

### padRight(s, width, pad)
Right-pads `s` to `width` using `pad` character(s).
```krypton
padRight("hi", 6, ".")    // "hi...."
```

### charCode(s)
Returns the ASCII code of the first character of `s`.
```krypton
charCode("A")    // "65"
charCode("0")    // "48"
```

### fromCharCode(n)
Returns the character with ASCII code `n`.
```krypton
fromCharCode(65)    // "A"
fromCharCode(10)    // newline
```

### splitBy(s, delim)
Splits `s` by the delimiter `delim` and returns a comma-separated list.
```krypton
splitBy("one::two::three", "::")    // "one,two,three"
splitBy("a-b-c", "-")              // "a,b,c"
```

### format(fmt, arg)
Replaces the first `{}` in `fmt` with `arg`.
```krypton
format("Hello, {}!", "world")    // "Hello, world!"
```

---

## Numbers and Math

### toInt(s)
Parses `s` as an integer.
```krypton
toInt("42")    // "42"
toInt("abc")   // "0"
```

### parseInt(s)
Like `toInt` but tolerates leading whitespace.
```krypton
parseInt("  42")    // "42"
```

### abs(n)
Returns the absolute value.
```krypton
abs(-5)    // "5"
abs(3)     // "3"
```

### min(a, b)
Returns the smaller of two numbers.
```krypton
min(3, 7)    // "3"
```

### max(a, b)
Returns the larger of two numbers.
```krypton
max(3, 7)    // "7"
```

### pow(base, exp)
Returns `base` raised to the power `exp`.
```krypton
pow(2, 10)    // "1024"
pow(3, 3)     // "27"
```

### sqrt(n)
Returns the integer square root (floor).
```krypton
sqrt(16)    // "4"
sqrt(10)    // "3"
```

### sign(n)
Returns `"1"` if positive, `"-1"` if negative, `"0"` if zero.
```krypton
sign(42)     // "1"
sign(-3)     // "-1"
sign(0)      // "0"
```

### clamp(val, lo, hi)
Clamps `val` to the range `[lo, hi]`.
```krypton
clamp(15, 0, 10)    // "10"
clamp(-5, 0, 10)    // "0"
clamp(7, 0, 10)     // "7"
```

### hex(n)
Converts a number to its hexadecimal string representation.
```krypton
hex(255)    // "ff"
hex(16)     // "10"
```

### bin(n)
Converts a number to its binary string representation.
```krypton
bin(10)     // "1010"
bin(255)    // "11111111"
```

---

## Lists

Lists in Krypton are comma-separated strings. `"apple,banana,cherry"` is a 3-element list.

### split(s, i)
Returns the item at index `i` from a comma-separated list.
```krypton
let fruits = "apple,banana,cherry"
split(fruits, 0)    // "apple"
split(fruits, 2)    // "cherry"
```

### length(lst)
Returns the number of items in a list.
```krypton
length("a,b,c")    // "3"
length("")          // "0"
```

### append(lst, item)
Appends `item` to the end of the list.
```krypton
append("a,b", "c")    // "a,b,c"
append("", "first")   // "first"
```

### insertAt(lst, i, item)
Inserts `item` at position `i`.
```krypton
insertAt("a,b,d", 2, "c")    // "a,b,c,d"
```

### removeAt(lst, i)
Removes the item at position `i`.
```krypton
removeAt("a,b,c,d", 1)    // "a,c,d"
```

### remove(lst, item)
Removes all occurrences of `item` from the list.
```krypton
remove("a,b,a,c", "a")    // "b,c"
```

### replaceAt(lst, i, val)
Replaces the item at position `i` with `val`.
```krypton
replaceAt("a,b,c", 1, "X")    // "a,X,c"
```

### slice(lst, start, end)
Returns a sublist from index `start` (inclusive) to `end` (exclusive). Supports negative indices.
```krypton
slice("a,b,c,d,e", 1, 4)     // "b,c,d"
slice("a,b,c,d,e", -3, -1)   // "c,d"
```

### join(lst, sep)
Joins list items with `sep` (replaces commas with `sep`).
```krypton
join("a,b,c", " - ")    // "a - b - c"
join("1,2,3", "+")       // "1+2+3"
```

### reverse(lst)
Reverses the order of items.
```krypton
reverse("a,b,c")    // "c,b,a"
```

### sort(lst)
Sorts items. Numeric-aware: numbers sort numerically, strings sort lexicographically.
```krypton
sort("3,1,2")         // "1,2,3"
sort("banana,apple")  // "apple,banana"
```

### unique(lst)
Removes duplicate items, preserving first occurrence order.
```krypton
unique("a,b,a,c,b")    // "a,b,c"
```

### fill(n, val)
Creates a list of `n` copies of `val`.
```krypton
fill(4, "x")    // "x,x,x,x"
fill(3, "0")    // "0,0,0"
```

### zip(a, b)
Interleaves two lists element by element. Truncates to the shorter list.
```krypton
zip("1,2,3", "a,b,c")    // "1,a,2,b,3,c"
```

### listIndexOf(lst, item)
Returns the index of `item` in the list, or `"-1"` if not found.
```krypton
listIndexOf("a,b,c", "b")    // "1"
listIndexOf("a,b,c", "z")    // "-1"
```

### every(lst, val)
Returns `"1"` if every item in the list equals `val`.
```krypton
every("5,5,5", "5")    // "1"
every("5,3,5", "5")    // "0"
```

### some(lst, val)
Returns `"1"` if any item in the list equals `val`.
```krypton
some("1,2,3", "2")    // "1"
some("1,2,3", "9")    // "0"
```

### countOf(lst, item)
Counts how many times `item` appears in the list.
```krypton
countOf("a,b,a,c,a", "a")    // "3"
```

### sumList(lst)
Returns the sum of all numeric items.
```krypton
sumList("10,20,30")    // "60"
```

### maxList(lst)
Returns the maximum numeric value in the list.
```krypton
maxList("5,1,9,3")    // "9"
```

### minList(lst)
Returns the minimum numeric value in the list.
```krypton
minList("5,1,9,3")    // "1"
```

### range(start, end)
Generates a list of numbers from `start` (inclusive) to `end` (exclusive).
```krypton
range(0, 5)    // "0,1,2,3,4"
range(3, 7)    // "3,4,5,6"
```

---

## Map Operations

Maps in Krypton are interleaved key-value lists: `"name,Alice,age,30"` has keys `name`, `age` and values `Alice`, `30`.

### keys(map)
Returns a comma-separated list of all keys (even-indexed items).
```krypton
keys("name,Alice,age,30")    // "name,age"
```

### values(map)
Returns a comma-separated list of all values (odd-indexed items).
```krypton
values("name,Alice,age,30")    // "Alice,30"
```

### hasKey(map, key)
Returns `"1"` if the key exists in the map.
```krypton
hasKey("name,Alice,age,30", "age")     // "1"
hasKey("name,Alice,age,30", "email")   // "0"
```

---

## Line Operations

These operate on newline-separated strings (as opposed to comma-separated lists).

### getLine(s, i)
Returns line number `i` (0-based) from a newline-separated string.
```krypton
let text = "alpha\nbeta\ngamma"
getLine(text, 1)    // "beta"
```

### lineCount(s)
Returns the number of lines.
```krypton
lineCount("a\nb\nc")    // "3"
```

### count(s)
Alias for `lineCount`.

---

## Type and Conversion

### type(s)
Returns `"number"` if `s` is a valid integer, `"string"` otherwise.
```krypton
type("42")       // "number"
type("hello")    // "string"
type("-7")       // "number"
```

### toStr(s)
Identity function — all values are already strings.
```krypton
toStr(42)    // "42"
```

### isTruthy(s)
Returns `"0"` if `s` is empty, `"0"`, or `"false"`. Returns `"1"` otherwise.
```krypton
isTruthy("hello")    // "1"
isTruthy("")         // "0"
isTruthy("0")        // "0"
```

### exit(code)
Exits the program with the given exit code.
```krypton
exit(1)
```

### assert(cond, msg)
If `cond` is falsy, prints `msg` to stderr and exits with code 1. Returns `"1"` on success.
```krypton
assert(x > 0, "x must be positive")
```

---

## StringBuilder

For efficient string construction in loops. Uses mutable handles internally.

### sbNew()
Creates a new string builder. Returns a handle string.
```krypton
let sb = sbNew()
```

### sbAppend(sb, s)
Appends `s` to the builder. Returns the handle.
```krypton
sb = sbAppend(sb, "hello ")
sb = sbAppend(sb, "world")
```

### sbToString(sb)
Returns the accumulated string.
```krypton
let result = sbToString(sb)    // "hello world"
```

---

## Environment (Low-level)

These power the compiler's own interpreter. They implement a linked-list environment for variable binding.

### envNew()
Creates an empty environment.

### envSet(env, key, val)
Returns a new environment with `key` bound to `val`.

### envGet(env, key)
Looks up `key` in the environment. Prints an error to stderr if not found.

### makeResult(tag, val, env, pos)
Packs a tagged result (used by the interpreter for parse results).

### getResultTag(r), getResultVal(r), getResultEnv(r), getResultPos(r)
Unpack fields from a result struct.
