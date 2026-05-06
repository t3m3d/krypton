# Krypton Type System

**Version 1.8.0**

Krypton uses a **dynamic, string-based value model**. All values are strings at
runtime. There are no separate integer, boolean, or float types — numeric and
boolean operations work by inspecting and converting string content.

---

## The String Model

Every value in Krypton is a `char*` string in the generated C code, and a heap
pointer (or small int — see "Smart-int" below) in the native pipeline.

```
let x = 42          // x holds the string "42"
let name = "hello"  // name holds the string "hello"
let flag = true     // flag holds the string "1"
let no = false      // no holds the string "0"
```

---

## Numeric Strings

Arithmetic operators detect when both operands look like numbers and perform
integer arithmetic. Otherwise `+` concatenates.

```
10 + 20         // "30"   (both numeric)
"10" + "20"     // "30"   (both numeric — stays numeric!)
"hello" + "!"   // "hello!"  (not numeric → concat)
10 + " items"   // "10 items"  (one not numeric → concat)
```

Numeric detection uses: optional leading `-`, then all digits.

> **Important footgun:** `"" + 5 + "x"` is `"5" + "x"` → `5 + "x"` → `"5x"`
> only because `"x"` is not numeric. But `"" + 1 + "0"` parses each step
> left-to-right and ends up as numeric `1 + 0 = 1`, not the string `"10"`.
> When you want guaranteed string concatenation of numeric tokens, use
> `sbAppend` rather than chained `+`.

---

## Smart-int (native pipeline)

The native runtime distinguishes integers from string pointers by value range:

- Values `< 0x40000000` (1 GiB) are stored directly as small integers.
- Values `≥ 0x40000000` are heap pointers to NUL-terminated strings.

Heap and code segments are placed above `0x40000000`, so the convention is
unambiguous in normal use. Two consequences:

- Integer values at or above 1 GiB are **not safe** in the native pipeline —
  they collide with the heap range and will be interpreted as garbage pointers.
  Use `add64`, `mul64`, etc. (C path) when you need 32-bit-and-up arithmetic.
- The C-path runtime has no such restriction; all values are heap-allocated
  string buffers.

---

## Booleans and Truthiness

`true` and `false` are language keywords. Since v1.4.0 they evaluate to the
strings `"true"` and `"false"` respectively (previously `"1"` / `"0"`).
There's no distinct boolean runtime type — booleans are just strings, and
the rest of the runtime treats them via the truthiness rules below.

A value is **falsy** if it is:

- `""` — empty string
- `"0"` — the digit zero string
- `"false"` — the word false (matches the literal)
- The integer `0`

Everything else is **truthy**, including `"1"`, `"true"`, any non-zero
number, any non-empty non-`"0"`/non-`"false"` string.

```
if ""        { }   // never runs
if "0"       { }   // never runs
if "false"   { }   // never runs
if true      { }   // runs ("true" is truthy)
if "hi"      { }   // runs
if 0         { }   // never runs
if 1         { }   // runs
if !false    { }   // runs
```

`isTruthy(s)` returns `"1"` or `"0"` per the same rules. `if`, `while`, and
loops wrap their conditions in `isTruthy` automatically — without that wrap,
the empty string `""` (a non-zero pointer) would naïvely test as truthy.

### Two boolean representations

Two value forms can both represent "boolean":

| Form | Source | Examples |
|------|--------|----------|
| `"true"` / `"false"` strings | `true` / `false` literals | `let flag = true` → `"true"` |
| `"1"` / `"0"` ints | Comparison ops, logical ops, isDigit/hasField/etc. | `let v = 5 > 3` → `"1"` |

Both behave the same under `if`/`while`/`isTruthy`. They DON'T compare equal
under `==` because they're different string values:

```
true == (5 > 3)            // "0" — different value forms!
isTruthy(true) == isTruthy(5 > 3)  // "1" — both truthy
```

The `stdlib/booleans.k` module provides `bool(v)`, `boolToInt(v)`, and
`boolEq(a, b)` helpers to normalize between the two forms when you need
consistent comparisons or display.

---

## Boolean Results

Comparison and logical operators return `"1"` (true) or `"0"` (false):

```
10 > 5      // "1"
10 < 5      // "0"
"a" == "a"  // "1"
!true       // "0"
```

---

## Structs

Structs are dynamic — fields are name/value pairs. Two backing representations:

- **C path:** a slot array (`char**`) with field count in slot 0 and
  alternating name/value pointers thereafter. Field updates mutate the array
  in place.
- **Native:** a linked-list of `{name, value, prev}` 24-byte entries. Field
  updates are functional — `setField` returns a new head pointer; assign back
  with `obj = setField(obj, "k", "v")`. (The C runtime accepts but ignores
  the returned value; for portability, always re-assign.)

Both backings expose the same API: `structNew`, `setField`, `getField`,
`hasField`, `structFields`. There are no typed fields — a field holds whatever
string you assign to it.

```
struct Point {
    let x
    let y
}

let p = Point { x: "10", y: "20" }
kp(p.x)   // "10"
```

---

## Lists

Lists are comma-separated strings:

```
let items = "apple,banana,cherry"
kp(split(items, 0))  // "apple"
kp(length(items))    // "3"
```

Native pipeline supports `split`, `length` (a.k.a. `count`), `range`, and `s[i]`
indexing. Higher-level list operations (`sort`, `unique`, `slice`, `head`,
`tail`, `append`, `removeAt`, `replaceAt`, `zip`, `every`, `some`, `countOf`,
`sumList`, `minList`, `maxList`, `listMap`, `listFilter`) are C-path only today.

---

## Maps

Maps are interleaved key-value comma-separated strings:

```
let m = "name,Alice,age,30"
kp(keys(m))    // "name,age"  (C path)
kp(values(m))  // "Alice,30"  (C path)
```

Map operations (`mapGet`, `mapSet`, `mapDel`, `keys`, `values`, `hasKey`) are
C-path only today.

---

## Pairs

Pairs are encoded as `"value,position"` strings — used pervasively by parser
helpers in the compiler to return a (result, advance-cursor) tuple from a
single function call.

```
emit substring(src, 0, p) + "," + p
// later:
let v = pairVal(r)   // everything before the LAST comma
let pos = pairPos(r) // integer after the last comma
```

`pairVal` and `pairPos` live in `stdlib/pair.k`. Until native module imports
land, inline them when targeting the native pipeline (see
`tests/test_pair_ops.k`).

---

## Type Checking

The `type()` builtin (C path) returns `"number"` or `"string"`:

```
type("42")     // "number"
type("hello")  // "string"
type(true)     // "number"  (true is "1")
```

---

## Future

Static type annotations are accepted by the parser today (`let x: int = 42`,
`func add(a: int, b: int) -> int`) and emitted as typed C declarations on the
C path. They have no effect on the native pipeline yet and aren't enforced at
runtime. Genuine static checking is a 2.0 candidate; the runtime model will
remain string-based for compatibility.
