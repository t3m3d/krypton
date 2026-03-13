# Krypton

**A self-hosting programming language that compiles to C.**

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
![Version](https://img.shields.io/badge/version-0.5.0-green)

Krypton is a dynamically typed language with a clean syntax, 72 built-in functions, and a compiler written in itself. The compiler (`kcc`) transpiles `.k` source files to C, then you compile the C with any C compiler to get a native executable.

```krypton
just run {
    print("Hello, World!")
}
```

---

## Quick Start

### 1. Download

Grab `kcc.exe` from the [Releases](https://github.com/t3m3d/krypton/releases) page.

### 2. Write a program

```krypton
// hello.k
just run {
    let name = "Krypton"
    print("Hello from " + name + "!")
}
```

### 3. Compile and run

```bash
kcc hello.k > hello.c
cl /O2 hello.c              # Windows (MSVC)
gcc -O2 -o hello hello.c    # Linux / macOS
./hello
```

The output is standard C — any C compiler works.

---

## Language Features

### Variables and Constants

```krypton
let x = 42
let name = "Krypton"
const pi = "314"
```

All values are strings at runtime. Numeric operations auto-detect when both operands are numbers.

### Functions

```krypton
func add(a, b) {
    emit a + b
}

func greet(name) {
    emit "Hello, " + name
}
```

`emit` (or `return`) returns a value from a function.

### Control Flow

```krypton
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
    i = i + 1
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
    "red" { print("warm") }
    "blue" { print("cool") }
    else { print("unknown") }
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

```krypton
let label = score >= 90 ? "A" : score >= 80 ? "B" : "C"
```

### Compound Assignment

```krypton
x += 10
x -= 5
x *= 2
x /= 3
x %= 7
```

### String Indexing

```krypton
let s = "hello"
let first = s[0]    // "h"
```

### Entry Point

Every program needs an entry block:

```krypton
just run {
    // your program here
}
```

---

## Built-in Functions (72)

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
| `trim(s)` | Strip whitespace |
| `toLower(s)` | To lowercase |
| `toUpper(s)` | To uppercase |
| `repeat(s, n)` | Repeat string n times |
| `padLeft(s, width, pad)` | Left-pad to width |
| `padRight(s, width, pad)` | Right-pad to width |
| `charCode(s)` | ASCII code of first character |
| `fromCharCode(n)` | Character from ASCII code |
| `splitBy(s, delim)` | Split string by delimiter into list |
| `format(fmt, arg)` | Replace `{}` in format string |

### Numbers and Math
| Function | Description |
|----------|-------------|
| `toInt(s)` | Parse string to integer |
| `parseInt(s)` | Parse with whitespace tolerance |
| `abs(n)` | Absolute value |
| `min(a, b)` | Minimum of two |
| `max(a, b)` | Maximum of two |
| `pow(base, exp)` | Exponentiation |
| `sqrt(n)` | Integer square root |
| `sign(n)` | Sign: -1, 0, or 1 |
| `clamp(val, lo, hi)` | Clamp to range |
| `hex(n)` | Number to hexadecimal string |
| `bin(n)` | Number to binary string |

### Lists
Lists are comma-separated strings: `"a,b,c"`

| Function | Description |
|----------|-------------|
| `split(s, i)` | Get item at index from comma-sep list |
| `length(lst)` | Count items in list |
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

### Map Operations
Maps are interleaved key-value lists: `"name,Alice,age,30"`

| Function | Description |
|----------|-------------|
| `keys(map)` | Get all keys |
| `values(map)` | Get all values |
| `hasKey(map, key)` | Check if key exists |

### Line Operations
| Function | Description |
|----------|-------------|
| `getLine(s, i)` | Get line by index (newline-separated) |
| `lineCount(s)` | Count lines |
| `count(s)` | Alias for lineCount |

### Type and Conversion
| Function | Description |
|----------|-------------|
| `type(s)` | Returns `"number"` or `"string"` |
| `toStr(s)` | Identity (all values are strings) |
| `isTruthy(s)` | Returns `"1"` or `"0"` |
| `exit(code)` | Exit with code |
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
├── kompiler/compile.k     # The self-hosting compiler (Krypton source)
├── build/versions/         # Versioned compiler binaries (v0.1.0 – v0.5.0)
├── examples/               # 56 example programs
├── algorithms/             # 24 classic algorithm implementations
├── stdlib/                 # 30 standard library modules
├── tutorial/               # 20-lesson progressive tutorial
├── tests/                  # Test suite
├── Spec.md                 # Language specification
├── krypton.rc              # Windows resource (icon + version)
└── LICENSE                 # Apache 2.0
```

## Self-Hosting

Krypton's compiler is written in Krypton. The bootstrap chain:

1. **C++ bootstrap** compiles `compile.k` to C
2. **compile.k** compiled to native `kcc.exe`
3. **kcc.exe** can compile itself (fixed-point verified)

Every version from v0.1.0 to v0.5.0 is preserved in `build/versions/`.

## Contributing

Krypton welcomes contributors who care about:

- Language design and compiler engineering
- Writing examples, tests, and documentation
- Trying the language and reporting issues

See [LICENSE](LICENSE) for terms (Apache 2.0).

---

**Krypton** — Copyright 2026 [t3m3d](https://github.com/t3m3d)
