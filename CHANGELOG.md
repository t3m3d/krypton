# Changelog

All notable changes to the Krypton language and compiler.

## [0.6.0] - 2026-03-14

### Language
- `for item in list { ... }` — for-in loop over comma-separated lists
- `do { ... } while cond` — do-while loop
- `match expr { val { } ... else { } }` — pattern matching
- `continue` statement in loops
- Compound assignment: `+=`, `-=`, `*=`, `/=`, `%=`
- `const` declarations: `const x = value`
- Ternary operator: `cond ? trueExpr : falseExpr` (nestable)

### Built-in Functions (30 new, 72 total)
- **Math:** `range`, `pow`, `sqrt`, `sign`, `clamp`
- **Strings:** `padLeft`, `padRight`, `charCode`, `fromCharCode`, `trim`, `toLower`, `toUpper`, `contains`, `endsWith`, `indexOf`, `replace`, `charAt`, `repeat`, `format`
- **Lists:** `append`, `join`, `reverse`, `sort`, `slice`, `length`, `unique`, `splitBy`, `listIndexOf`, `insertAt`, `removeAt`, `replaceAt`, `fill`, `zip`, `every`, `some`, `countOf`, `sumList`, `maxList`, `minList`
- **Conversion:** `hex`, `bin`, `parseInt`, `toStr`
- **I/O:** `printErr`, `readLine`, `writeFile`, `input`, `exit`

### Compiler
- Fixed `isKW` — `struct/class/type/try/catch/throw` were orphaned before keyword chain
- Fixed duplicate dead code block outside `compileStmt` (85 stray lines)
- Removed `defined()`/`not defined()` fake syntax from module scaffolding
- Clean module/import/export comment stubs
- Self-host verified

---

## [0.8.0] - 2026-03-13

### Language
 - Module/import/export support
 - Error handling: try, catch, throw
 - Struct/class/type declarations
 - Foundation for advanced features (lambdas, pattern matching, concurrency)

### Compiler
 - Updated kompiler/compile.k with new keywords and statement support
 - Ready for full release testing

---

## [0.5.0] - 2026-03-12

### Language
- Ternary operator: `cond ? trueExpr : falseExpr` (nestable)
- `const` declarations: `const x = "value"`

### Built-in Functions (15 new, 72 total)
- **List ops:** `splitBy`, `listIndexOf`, `insertAt`, `removeAt`, `replaceAt`, `fill`, `zip`, `every`, `some`, `countOf`
- **Aggregation:** `sumList`, `maxList`, `minList`
- **Conversion:** `hex`, `bin`

### Compiler
- Added `?` token to lexer
- Added `const` keyword
- Ternary expression parsing with correct precedence
- Self-host verified (485 KB with icon)

---

## [0.4.0] - 2026-03-12

### Language
- `continue` statement in loops
- `match` statement with pattern values and `else` fallback
- `do-while` loop: `do { ... } while cond`

### Built-in Functions (15 new, 57 total)
- **Math:** `range`, `pow`, `sqrt`, `sign`, `clamp`
- **Strings:** `padLeft`, `padRight`, `charCode`, `fromCharCode`
- **Lists:** `slice`, `length`, `unique`
- **I/O:** `printErr`, `readLine`
- **Debug:** `assert`

### Bugfix
- Fixed `%` modulo operator in expressions — lexer emitted `MOD` token but parser checked for `PERCENT` (broken since v0.1.0, only `%=` worked since v0.3.0)

### Compiler
- Self-host verified (470 KB with icon)

---

## [0.3.0] - 2026-03-12

### Language
- Compound assignment operators: `+=`, `-=`, `*=`, `/=`, `%=`
- `for-in` loop: `for item in list { ... }`

### Built-in Functions (12 new, 42 total)
- **Lists:** `append`, `join`, `reverse`, `sort`
- **Maps:** `keys`, `values`, `hasKey`, `remove`
- **Strings:** `repeat`, `format`
- **Conversion:** `parseInt`, `toStr`

### Compiler
- Added compound assignment tokens (PLUSEQ, MINUSEQ, STAREQ, SLASHEQ, MODEQ)
- Added `kr_listlen` for comma-based list length (fixes for-in iteration)
- First version with embedded icon via Windows resource compiler
- Self-host verified (455 KB with icon)

---

## [0.2.0] - 2026-03-11

### Built-in Functions (15 new, 30 total)
- **Strings:** `indexOf`, `contains`, `replace`, `charAt`, `trim`, `toLower`, `toUpper`, `endsWith`
- **I/O:** `writeFile`, `input`
- **Math:** `abs`, `min`, `max`
- **System:** `exit`, `type`

### Compiler
- Self-host verified (230 KB)

---

## [0.1.0] - 2026-03-10

### Initial Release
- Krypton-to-C transpiler written in Krypton (self-hosting)
- Core syntax: `let`, `func`/`fn`, `emit`/`return`, `if`/`else`, `while`, `break`
- Entry point: `just run { ... }`
- String-based value model (all values are strings, numeric-aware arithmetic)
- Arena allocator with 256 MB blocks
- Handle-based StringBuilder

### Built-in Functions (15)
- **I/O:** `print`/`kp`, `readFile`, `arg`, `argCount`
- **Strings:** `len`, `substring`, `split`, `startsWith`, `getLine`, `lineCount`, `count`
- **Conversion:** `toInt`
- **Low-level:** `envNew`, `envSet`, `envGet`, `makeResult`, `getResultTag`, `getResultVal`, `getResultEnv`, `getResultPos`, `isTruthy`, `sbNew`, `sbAppend`, `sbToString`

### Compiler
- C++ bootstrap → self-hosted fixed-point achieved
- Bootstrap chain preserved in `build/versions/`## [0.8.0] - 2026-03-16

### Module System

`import`, `export`, and `module` are now fully implemented.

**import** — load another Krypton file and inline its functions:

    import "stdlib/result.k"
    import "stdlib/math_utils.k"

    just run {
        let r = ok("hello")
        kp(unwrap(r))
        kp(gcd(48, 18))
    }

Import features:
- Path resolution relative to the source file's directory
- Import caching — duplicate imports silently skipped
- Works with both flat files and legacy `go name { }` wrapped files
- Error reporting when imported file is not found
- Merged function tables — imported functions visible to the compiler

**export** — mark a function as part of a module's public API:

    export func add(a, b) {
        emit toInt(a) + toInt(b) + ""
    }

**module** — declare the current file's module name:

    module math_utils

### Stdlib — Fully Importable

All 34 stdlib modules have been converted to the flat function format.
The `go name { }` wrapper has been removed from all of them.
A `module name` declaration has been added to each file.

Modules ready to import:
    stdlib/assert.k         stdlib/bitwise.k        stdlib/builder.k
    stdlib/char_utils.k     stdlib/collections.k    stdlib/convert.k
    stdlib/counter.k        stdlib/csv.k             stdlib/debug.k
    stdlib/file_utils.k     stdlib/format.k          stdlib/hex.k
    stdlib/io_utils.k       stdlib/json.k            stdlib/lines.k
    stdlib/list_utils.k     stdlib/map.k             stdlib/math_utils.k
    stdlib/option.k         stdlib/pair.k            stdlib/path.k
    stdlib/queue.k          stdlib/random.k          stdlib/range.k
    stdlib/result.k         stdlib/search.k          stdlib/set.k
    stdlib/sort.k           stdlib/stack.k           stdlib/string_utils.k
    stdlib/struct_utils.k   stdlib/test_framework.k  stdlib/text.k
    stdlib/validate.k

### Compiler (compile.k)
- Real import processing: loads file, tokenizes, scans functions, emits forward
  decls and bodies before the main file's functions
- Base directory resolution for relative import paths
- Import cache prevents duplicate compilation
- `export func` now actually compiles the following function
- `module name` emits a C comment marker
- Error message when source file cannot be read
- Top-level struct declarations now compiled in the second pass
- `fn` keyword accepted alongside `func` in all positions

### Interpreter (run.k)
- `import "file.k"` loads file and merges function table at runtime
- `module` and `export` keywords handled (skip gracefully)

### New Examples
- `examples/import_demo.k` — uses result.k, math_utils.k, json.k together
- `examples/hello_modules.k` — minimal import example

### Compiler stats
- compile.k: 66 functions, 134 builtins, 3433 lines
- Self-host verified with kcc_v077.exe

---

## [0.7.7] - 2026-03-16

### Language
- List literals: `[1, 2, 3]` compiles to comma-separated string `"1,2,3"`
- Empty list literal: `[]` produces `""`

### Interpreter (run.k) — Full Language Parity
- Added 86 missing builtins — now handles 113 total (up from 27)
- Added: `for-in`, `match`, `do-while`, `continue`, `try/catch/throw`
- Added: compound assignment (`+=`, `-=`, `*=`, `/=`, `%=`)
- Added: DOT field access (`obj.field`) and field assignment (`obj.field = val`)
- Added: `struct` declaration handling (skip at runtime)
- The interpreter now matches the compiler in language feature support

### Built-in Functions Added to Interpreter
All v0.2.0–v0.7.5 builtins including: string ops (toLower, toUpper, trim,
lstrip, rstrip, replace, indexOf, contains, splitBy, strReverse, isAlpha,
isDigit, center, padLeft, padRight, repeat, format), list ops (append, join,
sort, reverse, unique, range, first, last, head, tail, every, some, countOf,
sumList, maxList, minList, insertAt, removeAt, replaceAt, fill, zip, slice,
listIndexOf), math (pow, sqrt, hex, bin, sign, clamp, abs, min, max, floor,
ceil, round), struct ops (structNew, getField, setField, hasField, structFields),
map ops (mapGet, mapSet, mapDel), system (random, timestamp, environ, exit),
and more.

### New Stdlib Modules
- `stdlib/result.k` — Result type: `ok(val)`, `err(msg)`, `isOk`, `unwrap`, `unwrapOr`
- `stdlib/option.k` — Option type: `some(val)`, `none()`, `isSome`, `optUnwrap`, `optUnwrapOr`
- `stdlib/json.k` — JSON builder: `jsonStr`, `jsonObject`, `jsonArray`, `jsonBool`, `jsonNull`

### Docs
- `docs/roadmap.md` — Full roadmap to v1.0.0 native compilation documented

### Compiler
- Import statement improved: attempts to read file, reports whether found
- compile.k: 63 functions, 134 builtins, 3211 lines
- Self-host verified with kcc_v075.exe

---

## [0.7.5] - 2026-03-16

### Language
- String interpolation upgraded to full expressions: `` `{a + b}`, `{len(s)}`, `{func(x)}` ``
  Previously only simple identifiers worked. Expressions inside `{}` are now tokenized
  and compiled as full Krypton expressions.

### Built-in Functions (7 new, 134 total)
- **Maps:** `mapGet(map, key)`, `mapSet(map, key, val)`, `mapDel(map, key)` — key-value map operations that complement the existing `keys()`/`values()`/`hasKey()`
- **Lists:** `listMap(lst, prefix, suffix)` — wrap each item, `listFilter(lst, val)` — keep matching items (`"!val"` to exclude)
- **Strings:** `strSplit(s, delim)` — alias for `splitBy` with clearer name
- **System:** `sprintf(fmt, ...)` — C-style format strings via `vsnprintf`

### Stdlib
- All 27 stdlib modules modernized: `i = i + 1` → `i += 1`, `i = i - 1` → `i -= 1`
- New module: `stdlib/struct_utils.k` — `structToString`, `structCopy`, `structFromMap`, `structToMap`, `structEqual`

### Algorithms
- All 23 algorithm files modernized to use compound assignment operators

### Examples
- All 33 remaining examples modernized to current syntax
- New: `examples/task_manager.k` — showcase using structs, try/catch, interpolation, match

### Interpreter
- `run.k` updated to support string interpolation (backtick strings with `{expr}`)

### Compiler
- `#include <stdarg.h>` added to generated runtime for `sprintf`
- Self-host verified with kcc_v072.exe

---

## [0.7.2] - 2026-03-15

### Critical Fix
- `struct`, `class`, `type`, `try`, `catch`, `throw` were missing from `isKW()` — the tokenizer was producing `ID:struct` instead of `KW:struct`, meaning structs and try/catch were silently broken in any real program. Fixed.

### Language
- String interpolation: `` `Hello {name}, version {ver}!` `` — backtick strings with `{identifier}` placeholders compile to `kr_cat()` chains

### Docs
- `docs/spec/functions.md` — fully updated to v0.7.2 with all 127 functions
- `docs/spec/grammar.md` — updated with structs, try/catch, interpolation, DOT token
- `docs/spec/types.md` — completely rewritten to accurately describe Krypton's string-based type model (old version described a fictional static type system)
- `docs/roadmap.md` — updated with accurate history and near-term plans

### Tutorials
- `21_structs.k` — struct declaration, literals, dot access, dynamic structs
- `22_try_catch.k` — try/catch/throw with nesting and rethrow
- `23_for_in.k` — for-in with nesting, counters, range
- `24_string_interpolation.k` — backtick strings with expressions
- `25_match.k` — match statement pattern matching

### Tests
- `tests/test_structs.k` — full struct coverage
- `tests/test_try_catch.k` — exception handling coverage
- `tests/test_interpolation.k` — string interpolation coverage
- `tests/test_for_in.k` — for-in loop coverage including triple nesting

### Examples Updated
- `fibonacci.k`, `fizzbuzz.k`, `hello.k`, `factorial.k` modernized to use `+=`, `for-in`, string interpolation

### Compiler
- Self-host verified with kcc_v071.exe

---


