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
- Bootstrap chain preserved in `build/versions/`## [0.7.2] - 2026-03-15

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


