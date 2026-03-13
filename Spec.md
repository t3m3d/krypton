# Krypton Language Specification

**Version 0.5.0** — March 2026

---

## 1. Introduction

### 1.1 Purpose

Krypton is a dynamically typed programming language that compiles to C. The compiler (`kcc`) is self-hosting: it is written in Krypton and can compile itself.

### 1.2 Design Philosophy

- All values are strings
- Explicit over implicit
- Minimal surface area
- The compiler is the specification

### 1.3 Value Model

Every value in Krypton is a string. Numbers are strings that happen to contain digit characters. Arithmetic operations detect numeric operands and compute accordingly; otherwise they concatenate.

```krypton
let x = 10 + 20       // "30" (numeric addition)
let y = "hello" + " " + "world"  // "hello world" (concatenation)
let z = "10" + "20"   // "30" (both are numeric → addition)
```

Truthiness: `""`, `"0"`, and `"false"` are falsy. Everything else is truthy.

---

## 2. Lexical Structure

### 2.1 Character Set

Krypton source files use UTF-8 encoding.

### 2.2 Comments

```krypton
// Single-line comment
/* Multi-line
   comment */
```

### 2.3 Keywords

```
just  go  func  fn  let  const  emit  return
if  else  while  break  continue  for  in
match  do  module  true  false
```

Reserved for future use:
```
quantum  qpute  process  prepare  measure
```

### 2.4 Identifiers

Start with a letter or underscore, followed by letters, digits, or underscores. Case-sensitive.

### 2.5 Literals

- **Integer literals:** `0`, `42`, `-7`
- **String literals:** `"hello"`, `"line1\nline2"` (supports `\n`, `\t`, `\r`, `\\`, `\"`)
- **Boolean keywords:** `true` (compiles to `"1"`), `false` (compiles to `"0"`)

### 2.6 Operators

```
+  -  *  /  %
==  !=  <  >  <=  >=
&&  ||  !
=  +=  -=  *=  /=  %=
?  :
```

### 2.7 Punctuation

```
(  )  {  }  [  ]  ,  ;  ->
```

---

## 3. Declarations

### 3.1 Variables

```krypton
let name = expr
```

Declares a mutable variable initialized to the value of `expr`.

### 3.2 Constants

```krypton
const name = expr
```

Declares a variable. Semantically identical to `let` at the compiler level (no enforcement of immutability yet).

### 3.3 Functions

```krypton
func name(param1, param2) {
    // body
    emit value
}
```

- `func` and `fn` are interchangeable keywords
- Parameters are untyped (all values are strings)
- `emit` or `return` returns a value from the function
- Functions without an explicit `emit` return `""`

### 3.4 Entry Point

Every program must have exactly one entry block:

```krypton
just run {
    // program body
}
```

`go run { ... }` is also accepted.

---

## 4. Statements

### 4.1 Variable Declaration

```krypton
let x = 42
const y = "hello"
```

### 4.2 Assignment

```krypton
x = newValue
```

### 4.3 Compound Assignment

```krypton
x += 10     // x = x + 10
x -= 5      // x = x - 5
x *= 2      // x = x * 2
x /= 3      // x = x / 3
x %= 7      // x = x % 7
```

### 4.4 If / Else

```krypton
if condition {
    // ...
} else if otherCondition {
    // ...
} else {
    // ...
}
```

Conditions are evaluated for truthiness.

### 4.5 While Loop

```krypton
while condition {
    // body
}
```

### 4.6 Do-While Loop

```krypton
do {
    // body runs at least once
} while condition
```

### 4.7 For-In Loop

```krypton
for item in collection {
    // item is bound to each element
}
```

`collection` is a comma-separated list string. The loop iterates over each comma-delimited element.

### 4.8 Break and Continue

```krypton
while condition {
    if done { break }
    if skip { continue }
}
```

`break` exits the innermost loop. `continue` skips to the next iteration.

### 4.9 Match Statement

```krypton
match expr {
    "value1" { /* ... */ }
    "value2" { /* ... */ }
    else { /* default */ }
}
```

Compares `expr` against each case value using string equality. Falls through to `else` if no match. Only the first matching branch executes.

### 4.10 Emit / Return

```krypton
emit value
return value
```

Returns `value` from the current function. In the entry block, causes program exit.

### 4.11 Expression Statement

Any expression can be used as a statement (typically function calls):

```krypton
print("hello")
myFunction(arg1, arg2)
```

---

## 5. Expressions

### 5.1 Precedence (highest to lowest)

| Precedence | Operators | Associativity |
|------------|-----------|---------------|
| 1 | Postfix: `[i]`, `f()` | Left |
| 2 | Unary: `-`, `!` | Right |
| 3 | Multiplicative: `*`, `/`, `%` | Left |
| 4 | Additive: `+`, `-` | Left |
| 5 | Relational: `<`, `>`, `<=`, `>=` | Left |
| 6 | Equality: `==`, `!=` | Left |
| 7 | Logical AND: `&&` | Left |
| 8 | Logical OR: `\|\|` | Left |
| 9 | Ternary: `? :` | Right |

### 5.2 Arithmetic

```krypton
a + b    // addition if both numeric, concatenation otherwise
a - b    // subtraction
a * b    // multiplication
a / b    // integer division
a % b    // modulo
-a       // negation
```

### 5.3 Comparison

```krypton
a == b    // string equality → "1" or "0"
a != b    // string inequality
a < b     // numeric if both numeric, lexicographic otherwise
a > b
a <= b
a >= b
```

### 5.4 Logical

```krypton
a && b    // short-circuit AND (truthy → "1", falsy → "0")
a || b    // short-circuit OR
!a        // logical NOT
```

### 5.5 Ternary

```krypton
condition ? trueExpr : falseExpr
```

Evaluates `condition` for truthiness. Nestable:

```krypton
x > 0 ? "positive" : x == 0 ? "zero" : "negative"
```

### 5.6 String Indexing

```krypton
s[i]    // returns single character at index i
```

### 5.7 Function Calls

```krypton
functionName(arg1, arg2, arg3)
```

---

## 6. Compilation Model

### 6.1 Pipeline

```
source.k → kcc → output.c → C compiler → native executable
```

1. Krypton source is tokenized and parsed
2. The compiler emits C source code with an embedded runtime
3. Any standard C compiler produces the final binary

### 6.2 C Runtime

The generated C includes a complete runtime:

- **Arena allocator** — 256 MB bump-allocation blocks
- **String constants** — `""`, `"0"`, `"1"` are pre-allocated (no heap allocation)
- **72 built-in functions** — `kr_*` prefixed C functions
- **Handle-based StringBuilder** — mutable buffers for efficient string building
- **Linked-list environments** — for the interpreter's variable binding

### 6.3 Self-Hosting

The compiler (`kompiler/compile.k`) compiles itself:

1. C++ bootstrap compiles `compile.k` → `compile_self.c`
2. C compiler builds `compile_self.c` → `kcc.exe`
3. `kcc.exe` compiles `compile.k` → identical `compile_self.c` (fixed-point)

---

## 7. Built-in Functions

See [docs/spec/functions.md](docs/spec/functions.md) for the complete reference of all 72 built-in functions, organized by category:

- **I/O** (8): print, printErr, readLine, input, readFile, writeFile, arg, argCount
- **Strings** (17): len, substring, charAt, indexOf, contains, startsWith, endsWith, replace, trim, toLower, toUpper, repeat, padLeft, padRight, charCode, fromCharCode, splitBy, format
- **Numbers** (11): toInt, parseInt, abs, min, max, pow, sqrt, sign, clamp, hex, bin
- **Lists** (22): split, length, append, insertAt, removeAt, remove, replaceAt, slice, join, reverse, sort, unique, fill, zip, listIndexOf, every, some, countOf, sumList, maxList, minList, range
- **Maps** (3): keys, values, hasKey
- **Lines** (3): getLine, lineCount, count
- **Type/Conversion** (5): type, toStr, isTruthy, exit, assert
- **StringBuilder** (3): sbNew, sbAppend, sbToString
- **Environment** (8): envNew, envSet, envGet, makeResult, getResultTag, getResultVal, getResultEnv, getResultPos

---

## 8. Future Features

The following are reserved in the grammar but not yet implemented:

- **Quantum blocks** (`quantum`, `qpute`) — isolated quantum computations
- **Quantum operations** (`prepare`, `measure`) — qubit manipulation
- **Modules** (`module`) — namespace organization
- **Static typing** — optional type annotations
- **Structs and enums**
- **Pattern matching with destructuring**
- **Concurrency / process model**

---

## Appendix A: Grammar (EBNF)

```ebnf
program     ::= decl* entry_block

decl        ::= func_decl

func_decl   ::= ("func" | "fn") IDENT "(" params? ")" block

params      ::= IDENT ("," IDENT)*

entry_block ::= ("just" | "go") "run" block

block       ::= "{" stmt* "}"

stmt        ::= let_stmt
              | const_stmt
              | assign_stmt
              | compound_assign
              | if_stmt
              | while_stmt
              | do_while_stmt
              | for_in_stmt
              | match_stmt
              | break_stmt
              | continue_stmt
              | emit_stmt
              | expr_stmt

let_stmt        ::= "let" IDENT "=" expr ";"?
const_stmt      ::= "const" IDENT "=" expr ";"?
assign_stmt     ::= IDENT "=" expr ";"?
compound_assign ::= IDENT ("+=" | "-=" | "*=" | "/=" | "%=") expr ";"?
if_stmt         ::= "if" expr block ("else" if_stmt | "else" block)?
while_stmt      ::= "while" expr block
do_while_stmt   ::= "do" block "while" expr ";"?
for_in_stmt     ::= "for" IDENT "in" expr block
match_stmt      ::= "match" expr "{" match_arm* "}"
match_arm       ::= (expr | "else") block
break_stmt      ::= "break" ";"?
continue_stmt   ::= "continue" ";"?
emit_stmt       ::= ("emit" | "return") expr ";"?
expr_stmt       ::= expr ";"?

expr            ::= ternary_expr
ternary_expr    ::= or_expr ("?" expr ":" expr)?
or_expr         ::= and_expr ("||" and_expr)*
and_expr        ::= eq_expr ("&&" eq_expr)*
eq_expr         ::= rel_expr (("==" | "!=") rel_expr)*
rel_expr        ::= add_expr (("<" | ">" | "<=" | ">=") add_expr)*
add_expr        ::= mul_expr (("+" | "-") mul_expr)*
mul_expr        ::= unary_expr (("*" | "/" | "%") unary_expr)*
unary_expr      ::= ("-" | "!") unary_expr | postfix_expr
postfix_expr    ::= primary ("[" expr "]")*
primary         ::= INT | STRING | "true" | "false"
                   | IDENT "(" args? ")"
                   | IDENT
                   | "(" expr ")"

args            ::= expr ("," expr)*

INT             ::= [0-9]+
STRING          ::= '"' (char | escape)* '"'
IDENT           ::= [a-zA-Z_][a-zA-Z0-9_]*
escape          ::= "\\" | "\"" | "\n" | "\t" | "\r"
```

## Appendix B: Reserved Words

```
just  go  func  fn  let  const  emit  return  if  else  while
break  continue  for  in  match  do  module  true  false
quantum  qpute  process  prepare  measure
```
