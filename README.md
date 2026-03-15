# Krypton

**A self-hosting programming language that compiles to C.**

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
![Version](https://img.shields.io/badge/version-0.7.1-green)

Krypton is a dynamically typed language with a clean syntax, 127 built-in functions, and a compiler written in itself. The compiler (`kcc`) transpiles `.k` source files to C, then you compile the C with GCC to get a native executable.

```
just run {
    print("Hello, World!")
}
```

---

## Quick Start

### 1. Download

Grab `kcc_v071.exe` from the [Releases](https://github.com/t3m3d/krypton/releases) page.

### 2. Write a program

```
// hello.k
just run {
    let name = "Krypton"
    print("Hello from " + name + "!")
}
```

### 3. Compile and run

```bash
kcc_v071.exe hello.k > hello.c
gcc -O2 -o hello hello.c
./hello
```

The output is standard C. GCC is required (TDM-GCC recommended on Windows).

---

## Language Features

### Variables and Constants

```
let x = 42
let name = "Krypton"
const pi = "314"
```

All values are strings at runtime. Numeric operations auto-detect when both operands are numbers.

### Functions

```
func add(a, b) {
    emit a + b
}

func greet(name) {
    emit "Hello, " + name
}
```

`emit` (or `return`) returns a value from a function.

### Structs

```
struct Point {
    let x
    let y
}

let p = Point { x: "10", y: "20" }
kp(p.x)

p.x = "42"
kp(p.x)
```

Struct names must start with an uppercase letter. Fields are accessed and assigned with dot notation.

### Exception Handling

```
try {
    throw "something went wrong"
} catch e {
    kp("caught: " + e)
}
```

### Control Flow

```
// if / else if / else
if x > 10 {
    print("big")
} else if x > 5 {
    print("medium")
} else {
    print("small")
}

// while loop
while i < 10 {
    i += 1
}

// for-in loop
let items = "a,b,c,d"
for item in items {
    print(item)
}

// do-while loop
let n = 1
do {
    n = n * 2
} while n < 100

// match statement
match color {
    "red"  { print("warm") }
    "blue" { print("cool") }
    else   { print("unknown") }
}

// break and continue
while i < 100 {
    i += 1
    if i % 2 == 0 { continue }
    if i > 50 { break }
    print(i)
}
```

### Ternary Operator

```
let label = score >= 90 ? "A" : score >= 80 ? "B" : "C"
```

### Compound Assignment

```
x += 10
x -= 5
x *= 2
x /= 3
x %= 7
```

### String Indexing

```
let s = "hello"
let first = s[0]    // "h"
```

### Entry Point

Every program needs an entry block:

```
just run {
    // your program here
}
```

---

## Built-in Functions (127)

### I/O
| Function | Description |
|----------|-------------|
| `print(s)` / `kp(s)` | Print string with newline |
| `printErr(s)` | Print to stderr |
| `readLine(prompt)` | Read line from stdin with prompt |
| `input()` | Read line from stdin |
| `readFile(path)` | Read entire file to string |
| `writeFile(path, data)` | Write string to file |
| `arg(n)` | Get command-line argument |
| `argCount()` | Get argument count |

### Strings
| Function | Description |
|----------|-------------|
| `len(s)` | String length |
| `substring(s, start, end)` | Extract substring |
| `charAt(s, i)` | Character at index |
| `indexOf(s, sub)` | Find substring position (-1 if absent) |
| `contains(s, sub)` | Check if string contains substring |
| `startsWith(s, prefix)` | Check prefix |
| `endsWith(s, suffix)` | Check suffix |
| `replace(s, old, new)` | Replace all occurrences |
| `trim(s)` | Strip leading and trailing whitespace |
| `lstrip(s)` | Strip leading whitespace |
| `rstrip(s)` | Strip trailing whitespace |
| `center(s, width, pad)` | Center string within width |
| `toLower(s)` | To lowercase |
| `toUpper(s)` | To uppercase |
| `repeat(s, n)` | Repeat string n times |
| `padLeft(s, width, pad)` | Left-pad to width |
| `padRight(s, width, pad)` | Right-pad to width |
| `charCode(s)` | ASCII code of first character |
| `fromCharCode(n)` | Character from ASCII code |
| `splitBy(s, delim)` | Split by delimiter into list |
| `format(fmt, arg)` | Replace `{}` in format string |
| `strReverse(s)` | Reverse a string |
| `isAlpha(s)` | True if all characters are alphabetic |
| `isDigit(s)` | True if all characters are numeric |
| `isSpace(s)` | True if all characters are whitespace |

### Numbers and Math
| Function | Description |
|----------|-------------|
| `toInt(s)` | Parse string to integer |
| `parseInt(s)` | Parse with whitespace tolerance |
| `abs(n)` | Absolute value |
| `min(a, b)` | Minimum of two values |
| `max(a, b)` | Maximum of two values |
| `pow(base, exp)` | Exponentiation |
| `sqrt(n)` | Integer square root |
| `sign(n)` | Sign: -1, 0, or 1 |
| `clamp(val, lo, hi)` | Clamp to range |
| `hex(n)` | Number to hexadecimal string |
| `bin(n)` | Number to binary string |
| `floor(n)` | Floor (integer) |
| `ceil(n)` | Ceiling (integer) |
| `round(n)` | Round (integer) |

### Lists
Lists are comma-separated strings: `"a,b,c"`

| Function | Description |
|----------|-------------|
| `split(s, i)` | Get item at index |
| `length(lst)` | Count items |
| `first(lst)` | Get first item |
| `last(lst)` | Get last item |
| `head(lst, n)` | Get first n items |
| `tail(lst, n)` | Get last n items |
| `append(lst, item)` | Append item |
| `insertAt(lst, i, item)` | Insert at position |
| `removeAt(lst, i)` | Remove by index |
| `remove(lst, item)` | Remove first matching item |
| `replaceAt(lst, i, val)` | Replace at index |
| `slice(lst, start, end)` | Extract sublist |
| `join(lst, sep)` | Join with separator |
| `reverse(lst)` | Reverse list |
| `sort(lst)` | Sort (numeric-aware) |
| `unique(lst)` | Remove duplicates |
| `fill(n, val)` | Create list of n copies |
| `zip(a, b)` | Interleave two lists |
| `listIndexOf(lst, item)` | Find item index (-1 if absent) |
| `every(lst, val)` | Check all items match value |
| `some(lst, val)` | Check any item matches value |
| `countOf(lst, item)` | Count occurrences |
| `sumList(lst)` | Sum numeric items |
| `maxList(lst)` | Maximum of list |
| `minList(lst)` | Minimum of list |
| `range(start, end)` | Generate number list |
| `words(s)` | Split string on whitespace into list |
| `lines(s)` | Split string on newlines into list |

### Maps
Maps are interleaved key-value lists: `"name,Alice,age,30"`

| Function | Description |
|----------|-------------|
| `keys(map)` | Get all keys |
| `values(map)` | Get all values |
| `hasKey(map, key)` | Check if key exists |

### Structs
| Function | Description |
|----------|-------------|
| `structNew()` | Create a new empty dynamic struct |
| `setField(obj, name, val)` | Set a field value |
| `getField(obj, name)` | Get a field value |
| `hasField(obj, name)` | Check if field exists |
| `structFields(obj)` | Get comma-separated list of field names |

### Exception Handling
| Function | Description |
|----------|-------------|
| `throw(msg)` | Throw an exception (function form) |

### Line Operations
| Function | Description |
|----------|-------------|
| `getLine(s, i)` | Get line by index |
| `lineCount(s)` | Count lines |
| `count(s)` | Alias for lineCount |

### System
| Function | Description |
|----------|-------------|
| `random(n)` | Random integer from 0 to n-1 |
| `timestamp()` | Current Unix timestamp |
| `environ(name)` | Read environment variable |
| `exit(code)` | Exit with code |

### Type and Conversion
| Function | Description |
|----------|-------------|
| `type(s)` | Returns `"number"` or `"string"` |
| `toStr(s)` | Identity (all values are strings) |
| `isTruthy(s)` | Returns `"1"` or `"0"` |
| `assert(cond, msg)` | Assert condition or abort |

### StringBuilder
| Function | Description |
|----------|-------------|
| `sbNew()` | Create mutable string builder |
| `sbAppend(sb, s)` | Append to builder |
| `sbToString(sb)` | Get final string |

### Environment (Low-level)
| Function | Description |
|----------|-------------|
| `envNew()` | Create environment |
| `envSet(env, key, val)` | Set variable |
| `envGet(env, key)` | Get variable |
| `makeResult(tag, val, env, pos)` | Pack result |
| `getResultTag(r)` | Unpack tag |
| `getResultVal(r)` | Unpack value |
| `getResultEnv(r)` | Unpack environment |
| `getResultPos(r)` | Unpack position |

---

## Project Structure

```
krypton/
├── kompiler/              # Self-hosting compiler (Krypton source)
│   └── compile.k          # The compiler — written in Krypton
├── assets/                # Icon and Windows resource file
├── examples/              # 56 example programs
├── algorithms/            # 24 classic algorithm implementations
├── stdlib/                # Standard library modules
├── tutorial/              # 20-lesson progressive tutorial
├── tests/                 # Test suite
├── tools/                 # Command-line utilities written in Krypton
├── docs/                  # Documentation and roadmap
├── grammar/               # EBNF grammar definition
├── archive/               # Legacy C++ bootstrap compiler (historical)
├── Spec.md                # Language specification
├── CHANGELOG.md           # Version history
└── LICENSE                # Apache 2.0
```

---

## Self-Hosting

Krypton's compiler is written in Krypton. The full bootstrap chain:

```
kcc (C++) → v010 → v020 → v030 → v040 → v050 → v060 → v070 → v071
```

Each version was compiled by the previous one. Compiler binaries are available in [Releases](https://github.com/t3m3d/krypton/releases).

---

## Contributing

Krypton welcomes contributors who care about:

- Language design and compiler engineering
- Writing examples, tests, and documentation
- Trying the language and reporting issues

See [LICENSE](LICENSE) for terms (Apache 2.0).

---

**Krypton** — Copyright 2026 [t3m3d](https://github.com/t3m3d)
