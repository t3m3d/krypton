# Krypton Type System

**Version 0.7.2**

Krypton uses a **dynamic, string-based value model**. All values are strings at runtime. There are no separate integer, boolean, or float types — numeric and boolean operations work by inspecting and converting string content.

---

## The String Model

Every value in Krypton is a `char*` string in the generated C code.

```
let x = 42          // x holds the string "42"
let name = "hello"  // name holds the string "hello"
let flag = true     // flag holds the string "1"
let no = false      // no holds the string "0"
```

---

## Numeric Strings

Arithmetic operators detect when both operands look like numbers and perform integer arithmetic. Otherwise `+` concatenates.

```
10 + 20        // "30"  (both numeric)
"10" + "20"    // "30"  (both numeric)
"hello" + "!"  // "hello!"  (not numeric)
10 + " items"  // "10 items"  (one not numeric → concat)
```

Numeric detection uses: optional leading `-`, then all digits.

---

## Truthiness

A value is **falsy** if it is:
- `""` — empty string
- `"0"` — zero
- `"false"` — the word false

Everything else is **truthy**, including `"1"`, any non-zero number, any non-empty string.

```
if ""    { }   // never runs
if "0"   { }   // never runs
if "1"   { }   // runs
if "hi"  { }   // runs
if 0     { }   // never runs
if 1     { }   // runs
```

---

## Boolean Results

Comparison and logical operators return `"1"` (true) or `"0"` (false):

```
10 > 5     // "1"
10 < 5     // "0"
"a" == "a" // "1"
!true      // "0"
```

---

## Structs

Structs are dynamic — fields are string name/value pairs stored in arena memory. All field values are strings.

```
struct Point {
    let x
    let y
}

let p = Point { x: "10", y: "20" }
kp(p.x)   // "10"
```

There are no typed fields. A field holds whatever string you assign to it.

---

## Lists

Lists are comma-separated strings:

```
let items = "apple,banana,cherry"
kp(split(items, 0))   // "apple"
kp(length(items))     // "3"
```

---

## Maps

Maps are interleaved key-value comma-separated strings:

```
let m = "name,Alice,age,30"
kp(keys(m))      // "name,age"
kp(values(m))    // "Alice,30"
```

---

## Type Checking

The `type()` builtin returns `"number"` or `"string"`:

```
type("42")    // "number"
type("hello") // "string"
type(true)    // "number"  (true is "1")
```

---

## Future

Static type annotations are planned as an optional feature. The runtime model will remain string-based for compatibility.
