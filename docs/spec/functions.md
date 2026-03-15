# Krypton Built-in Functions Reference

**Version 0.7.2** — Complete reference for all 127 built-in functions.

All values in Krypton are strings. Functions that operate on numbers parse their arguments and return numeric strings. Lists are comma-separated strings (`"a,b,c"`). Maps are interleaved key-value lists (`"name,Alice,age,30"`).

---

## I/O

### print(s) / kp(s)
Prints `s` followed by a newline to stdout.
```
print("hello")
kp("world")
```

### printErr(s)
Prints `s` followed by a newline to stderr.
```
printErr("warning: file not found")
```

### readLine(prompt)
Displays `prompt` then reads a line from stdin. Returns the input without the trailing newline.
```
let name = readLine("Enter your name: ")
```

### input()
Reads a line from stdin with no prompt.
```
let line = input()
```

### readFile(path)
Reads the entire contents of a file. Returns `""` if the file does not exist.
```
let src = readFile("hello.k")
```

### writeFile(path, data)
Writes `data` to a file. Returns `"1"` on success, `"0"` on failure.
```
writeFile("out.txt", "hello\n")
```

### arg(n)
Returns command-line argument at index `n` (0-based, skipping the program name).
```
let filename = arg(0)
```

### argCount()
Returns the number of command-line arguments passed.
```
let n = argCount()
```

---

## Strings

### len(s)
Returns the length of string `s`.
```
len("hello")    // "5"
```

### substring(s, start, end)
Returns the substring from index `start` to `end` (exclusive).
```
substring("hello", 1, 3)    // "el"
```

### charAt(s, i)
Returns the character at index `i`.
```
charAt("hello", 0)    // "h"
```

### indexOf(s, sub)
Returns the position of `sub` in `s`, or `"-1"` if not found.
```
indexOf("hello world", "world")    // "6"
```

### contains(s, sub)
Returns `"1"` if `s` contains `sub`, otherwise `"0"`.
```
contains("hello", "ell")    // "1"
```

### startsWith(s, prefix)
Returns `"1"` if `s` starts with `prefix`.
```
startsWith("hello", "he")    // "1"
```

### endsWith(s, suffix)
Returns `"1"` if `s` ends with `suffix`.
```
endsWith("hello", "lo")    // "1"
```

### replace(s, old, new)
Replaces all occurrences of `old` with `new` in `s`.
```
replace("aabbcc", "bb", "XX")    // "aaXXcc"
```

### trim(s)
Strips leading and trailing whitespace.
```
trim("  hello  ")    // "hello"
```

### lstrip(s)
Strips leading whitespace only.
```
lstrip("  hello  ")    // "hello  "
```

### rstrip(s)
Strips trailing whitespace only.
```
rstrip("  hello  ")    // "  hello"
```

### center(s, width, pad)
Centers `s` within `width` characters, padding with `pad`.
```
center("hi", 8, "-")    // "---hi---"
```

### toLower(s)
Converts to lowercase.
```
toLower("Hello")    // "hello"
```

### toUpper(s)
Converts to uppercase.
```
toUpper("hello")    // "HELLO"
```

### repeat(s, n)
Repeats `s` exactly `n` times.
```
repeat("ab", 3)    // "ababab"
```

### padLeft(s, width, pad)
Left-pads `s` to `width` using `pad` character.
```
padLeft("42", 6, "0")    // "000042"
```

### padRight(s, width, pad)
Right-pads `s` to `width` using `pad` character.
```
padRight("hi", 6, ".")    // "hi...."
```

### charCode(s)
Returns the ASCII code of the first character of `s`.
```
charCode("A")    // "65"
```

### fromCharCode(n)
Returns the character with ASCII code `n`.
```
fromCharCode(65)    // "A"
```

### splitBy(s, delim)
Splits `s` by the string delimiter `delim` into a comma-separated list.
```
splitBy("one::two::three", "::")    // "one,two,three"
```

### format(fmt, arg)
Replaces the first `{}` in `fmt` with `arg`.
```
format("Hello {}!", "world")    // "Hello world!"
```

### strReverse(s)
Reverses a string.
```
strReverse("hello")    // "olleh"
```

### isAlpha(s)
Returns `"1"` if all characters in `s` are alphabetic.
```
isAlpha("abc")    // "1"
isAlpha("ab1")    // "0"
```

### isDigit(s)
Returns `"1"` if all characters in `s` are numeric digits.
```
isDigit("123")    // "1"
isDigit("12x")    // "0"
```

### isSpace(s)
Returns `"1"` if all characters in `s` are whitespace.
```
isSpace("   ")    // "1"
```

---

## Numbers and Math

### toInt(s)
Parses a string to its integer representation.
```
toInt("42")      // "42"
toInt("  7  ")   // "7"
```

### parseInt(s)
Parses a string to integer with leading whitespace tolerance.
```
parseInt("  42")    // "42"
```

### abs(n)
Returns the absolute value of `n`.
```
abs(-5)    // "5"
```

### min(a, b)
Returns the smaller of `a` and `b`.
```
min(3, 7)    // "3"
```

### max(a, b)
Returns the larger of `a` and `b`.
```
max(3, 7)    // "7"
```

### pow(base, exp)
Returns `base` raised to the power `exp` (integer).
```
pow(2, 8)    // "256"
```

### sqrt(n)
Returns the integer square root of `n`.
```
sqrt(144)    // "12"
```

### sign(n)
Returns `"-1"`, `"0"`, or `"1"` depending on the sign of `n`.
```
sign(-5)    // "-1"
sign(0)     // "0"
sign(3)     // "1"
```

### clamp(val, lo, hi)
Clamps `val` to the range `[lo, hi]`.
```
clamp(15, 0, 10)    // "10"
clamp(-3, 0, 10)    // "0"
```

### hex(n)
Returns the hexadecimal string representation of `n`.
```
hex(255)    // "ff"
hex(16)     // "10"
```

### bin(n)
Returns the binary string representation of `n`.
```
bin(10)     // "1010"
bin(255)    // "11111111"
```

### floor(n)
Returns the floor of `n` (integer, same as `toInt` for integer inputs).
```
floor(42)    // "42"
```

### ceil(n)
Returns the ceiling of `n`.
```
ceil(42)    // "42"
```

### round(n)
Returns `n` rounded to the nearest integer.
```
round(42)    // "42"
```

---

## Lists

Lists are comma-separated strings: `"a,b,c"`

### split(s, i)
Returns the item at index `i` from a comma-separated list.
```
split("a,b,c", 1)    // "b"
```

### length(lst)
Returns the number of items in a list.
```
length("a,b,c")    // "3"
```

### first(lst)
Returns the first item in a list.
```
first("a,b,c")    // "a"
```

### last(lst)
Returns the last item in a list.
```
last("a,b,c")    // "c"
```

### head(lst, n)
Returns the first `n` items as a list.
```
head("a,b,c,d", 2)    // "a,b"
```

### tail(lst, n)
Returns the last `n` items as a list.
```
tail("a,b,c,d", 2)    // "c,d"
```

### append(lst, item)
Appends `item` to the end of the list.
```
append("a,b", "c")    // "a,b,c"
```

### insertAt(lst, i, item)
Inserts `item` at position `i`.
```
insertAt("a,b,d", 2, "c")    // "a,b,c,d"
```

### removeAt(lst, i)
Removes the item at position `i`.
```
removeAt("a,b,c", 1)    // "a,c"
```

### remove(lst, item)
Removes the first occurrence of `item`.
```
remove("a,b,a,c", "a")    // "b,a,c"
```

### replaceAt(lst, i, val)
Replaces the item at position `i` with `val`.
```
replaceAt("a,b,c", 1, "X")    // "a,X,c"
```

### slice(lst, start, end)
Returns items from index `start` to `end` (exclusive).
```
slice("a,b,c,d", 1, 3)    // "b,c"
```

### join(lst, sep)
Joins list items with separator `sep`.
```
join("a,b,c", "-")    // "a-b-c"
```

### reverse(lst)
Reverses the order of items.
```
reverse("a,b,c")    // "c,b,a"
```

### sort(lst)
Sorts items. Numeric-aware: numbers sort by value, strings lexicographically.
```
sort("3,1,4,1,5")    // "1,1,3,4,5"
```

### unique(lst)
Removes duplicate items, preserving first occurrence order.
```
unique("a,b,a,c,b")    // "a,b,c"
```

### fill(n, val)
Creates a list of `n` copies of `val`.
```
fill(4, "hi")    // "hi,hi,hi,hi"
```

### zip(a, b)
Interleaves two lists element by element.
```
zip("1,2,3", "a,b,c")    // "1,a,2,b,3,c"
```

### listIndexOf(lst, item)
Returns the index of `item` in the list, or `"-1"` if not found.
```
listIndexOf("a,b,c", "b")    // "1"
```

### every(lst, val)
Returns `"1"` if every item in the list equals `val`.
```
every("5,5,5", "5")    // "1"
every("5,5,3", "5")    // "0"
```

### some(lst, val)
Returns `"1"` if any item in the list equals `val`.
```
some("1,2,3", "2")    // "1"
some("1,2,3", "9")    // "0"
```

### countOf(lst, item)
Returns the number of times `item` appears in the list.
```
countOf("a,b,a,c,a", "a")    // "3"
```

### sumList(lst)
Returns the sum of all numeric items.
```
sumList("10,20,30")    // "60"
```

### maxList(lst)
Returns the maximum numeric value in the list.
```
maxList("5,1,9,3")    // "9"
```

### minList(lst)
Returns the minimum numeric value in the list.
```
minList("5,1,9,3")    // "1"
```

### range(start, end)
Returns a comma-separated list of integers from `start` to `end` (exclusive).
```
range(1, 5)    // "1,2,3,4"
```

### words(s)
Splits a string on whitespace into a comma-separated list.
```
words("hello world foo")    // "hello,world,foo"
```

### lines(s)
Splits a string on newlines into a comma-separated list.
```
lines("a\nb\nc")    // "a,b,c"
```

---

## Maps

Maps are interleaved key-value comma-separated strings: `"name,Alice,age,30"`

### keys(map)
Returns a list of all keys.
```
keys("name,Alice,age,30")    // "name,age"
```

### values(map)
Returns a list of all values.
```
values("name,Alice,age,30")    // "Alice,30"
```

### hasKey(map, key)
Returns `"1"` if `key` exists in the map.
```
hasKey("name,Alice,age,30", "name")    // "1"
```

---

## Structs

### structNew()
Creates a new empty dynamic struct.
```
let obj = structNew()
```

### setField(obj, name, val)
Sets field `name` to `val` on the struct. Returns the struct.
```
setField(obj, "x", "10")
```

### getField(obj, name)
Returns the value of field `name`, or `""` if not set.
```
getField(obj, "x")    // "10"
```

### hasField(obj, name)
Returns `"1"` if the struct has a field named `name`.
```
hasField(obj, "x")    // "1"
```

### structFields(obj)
Returns a comma-separated list of all field names.
```
structFields(obj)    // "x,y"
```

---

## Line Operations

### getLine(s, i)
Returns the line at index `i` from a newline-separated string.
```
getLine("a\nb\nc", 1)    // "b"
```

### lineCount(s)
Returns the number of lines in a newline-separated string.
```
lineCount("a\nb\nc")    // "3"
```

### count(s)
Alias for `lineCount`.

---

## System

### random(n)
Returns a random integer from `0` to `n-1`.
```
random(10)    // "7"  (example)
```

### timestamp()
Returns the current Unix timestamp as a string.
```
timestamp()    // "1742000000"  (example)
```

### environ(name)
Returns the value of environment variable `name`, or `""` if not set.
```
environ("PATH")
```

### exit(code)
Exits the program with the given exit code.
```
exit(1)
```

---

## Exceptions

### throw(msg)
Throws an exception with message `msg`. Can also be used as a statement: `throw "msg"`.
```
throw("something went wrong")
```

---

## Type and Conversion

### type(s)
Returns `"number"` if `s` looks like a number, otherwise `"string"`.
```
type("42")      // "number"
type("hello")   // "string"
```

### toStr(s)
Returns `s` unchanged (identity function — all values are already strings).

### isTruthy(s)
Returns `"1"` if `s` is truthy, `"0"` if falsy.
```
isTruthy("hello")    // "1"
isTruthy("")         // "0"
isTruthy("0")        // "0"
```

### assert(cond, msg)
If `cond` is falsy, prints `msg` to stderr and exits with code 1.
```
assert(x > 0, "x must be positive")
```

---

## StringBuilder

StringBuilders allow efficient string assembly without repeated concatenation.

### sbNew()
Creates a new StringBuilder. Returns a handle string.
```
let sb = sbNew()
```

### sbAppend(sb, s)
Appends `s` to the StringBuilder. Returns the same handle.
```
sb = sbAppend(sb, "hello")
sb = sbAppend(sb, " world")
```

### sbToString(sb)
Returns the accumulated string from the StringBuilder.
```
let result = sbToString(sb)    // "hello world"
```

---

## Environment (Low-level)

These are used internally by the interpreter and for advanced use cases.

### envNew()
Creates a new empty environment (linked-list of bindings).

### envSet(env, key, val)
Adds a binding to the environment. Returns the new environment.

### envGet(env, key)
Looks up `key` in the environment. Returns `""` if not found.

### makeResult(tag, val, env, pos)
Packs a tag, value, environment, and position into a result struct.

### getResultTag(r)
Unpacks the tag from a result.

### getResultVal(r)
Unpacks the value from a result.

### getResultEnv(r)
Unpacks the environment from a result.

### getResultPos(r)
Unpacks the position from a result.
