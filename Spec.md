# Krypton Language Specification

**Version 1.0.3** — March 2026

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

```
let x = 10 + 20              // "30" (numeric addition)
let y = "hello" + " world"   // "hello world" (concatenation)
let z = "10" + "20"          // "30" (both are numeric → addition)
```

Truthiness: `""`, `"0"`, and `"false"` are falsy. Everything else is truthy.

---

## 2. Lexical Structure

### 2.1 Character Set

Krypton source files use UTF-8 encoding.

### 2.2 Comments

```
// Single-line comment
/* Multi-line
   comment */
```

### 2.3 Keywords

```
just  go  func  fn  let  const  emit  return
if  else  while  break  continue  for  in
match  do  struct  class  type  try  catch  throw
module  import  export  true  false
```

Reserved for future use:
```
quantum  qpute  process  prepare  measure
```

### 2.4 Identifiers

Start with a letter or underscore, followed by letters, digits, or underscores. Case-sensitive.

> **Convention:** struct names must start with an uppercase letter — `Point`, `Person`, `Rect`. This is how the compiler distinguishes a struct literal from a block statement.

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
.
```

### 2.7 Punctuation

```
(  )  {  }  [  ]  ,  ;  ->
```

---

## 3. Declarations

### 3.1 Variables

```
let name = expr
```

Declares a mutable variable initialized to the value of `expr`.

### 3.2 Constants

```
const name = expr
```

Semantically identical to `let` at the compiler level. Immutability is not enforced yet.

### 3.3 Functions

```
func name(param1, param2) {
    // body
    emit value
}
```

- `func` and `fn` are interchangeable keywords
- Parameters are untyped (all values are strings)
- `emit` or `return` returns a value from the function
- Functions without an explicit `emit` return `""`

### 3.4 Structs

```
struct Point {
    let x
    let y
}
```

Declares a named struct type with zero or more string fields. The compiler generates a C `typedef struct` and a zero-argument constructor.

**Constructor:**
```
let p = Point()
```

**Struct literal** (inline initialization):
```
let p = Point { x: "10", y: "20" }
```

**Field access:**
```
let val = p.x
```

**Field assignment:**
```
p.x = "42"
```

**Dynamic struct** (no declaration needed):
```
let obj = structNew()
setField(obj, "lang", "Krypton")
let lang = getField(obj, "lang")
```

### 3.5 Type Annotations (Optional)

Type annotations are optional and non-enforced. They are parsed and discarded by the
compiler — the generated C always uses `char*` for all values. Annotations exist
purely for documentation and tooling support.

**Variable annotations:**
```
let x: int = 42
let name: string = "hello"
let items: list = "a,b,c"
```

**Function parameter and return type annotations:**
```
func add(a: int, b: int) -> int {
    emit toInt(a) + toInt(b) + ""
}

func greet(name: string) -> string {
    emit "Hello " + name
}
```

**Struct field annotations:**
```
struct Point {
    let x: float
    let y: float
}
```

**Supported type names:** `int`, `float`, `bool`, `string`, `list`, `map`, `any`, `void`, `num`

**Compound types:** `list[int]`, `map[string, int]` — brackets are parsed and skipped.

### 3.6 Entry Point

Every program must have exactly one entry block:

```
just run {
    // program body
}
```

`go run { ... }` is also accepted.

---

## 4. Statements

### 4.1 Variable Declaration

```
let x = 42
const y = "hello"
```

### 4.2 Assignment

```
x = newValue
```

### 4.3 Field Assignment

```
p.field = newValue
```

Assigns a value to a named field on a struct.

### 4.4 Compound Assignment

```
x += 10
x -= 5
x *= 2
x /= 3
x %= 7
```

### 4.5 If / Else

```
if condition {
    // ...
} else if otherCondition {
    // ...
} else {
    // ...
}
```

### 4.6 While Loop

```
while condition {
    // body
}
```

### 4.7 Do-While Loop

```
do {
    // body runs at least once
} while condition
```

### 4.8 For-In Loop

```
for item in collection {
    // item is bound to each element
}
```

`collection` is a comma-separated list string. Nesting is supported — loop variables are depth-scoped to prevent collision.

### 4.9 Break and Continue

```
while condition {
    if done { break }
    if skip { continue }
}
```

### 4.10 Match

```
match expr {
    "value1" { /* ... */ }
    "value2" { /* ... */ }
    else     { /* default */ }
}
```

Compares `expr` against each case using string equality. Only the first matching branch executes.

### 4.11 Try / Catch / Throw

```
try {
    throw "something went wrong"
} catch e {
    kp("caught: " + e)
}
```

- The catch variable is optional — `catch { }` is valid
- `throw` works as both a statement and a function call: `throw("msg")`
- Nesting and rethrowing are supported
- Uncaught exceptions print to stderr and exit with code 1
- Implemented via `setjmp`/`longjmp` in the generated C runtime (256-deep stack)

### 4.12 Emit / Return

```
emit value
return value
```

Returns `value` from the current function. In the entry block, causes program exit.

### 4.13 Expression Statement

```
print("hello")
myFunction(arg1, arg2)
```

---

## 5. Expressions

### 5.1 Precedence (highest to lowest)

| Precedence | Operators | Associativity |
|------------|-----------|---------------|
| 1 | Postfix: `[i]`, `f()`, `.field` | Left |
| 2 | Unary: `-`, `!` | Right |
| 3 | Multiplicative: `*`, `/`, `%` | Left |
| 4 | Additive: `+`, `-` | Left |
| 5 | Relational: `<`, `>`, `<=`, `>=` | Left |
| 6 | Equality: `==`, `!=` | Left |
| 7 | Logical AND: `&&` | Left |
| 8 | Logical OR: `\|\|` | Left |
| 9 | Ternary: `? :` | Right |

### 5.2 Arithmetic

```
a + b    // addition if both numeric, concatenation otherwise
a - b    // subtraction
a * b    // multiplication
a / b    // integer division
a % b    // modulo
-a       // negation
```

### 5.3 Comparison

```
a == b    // string equality → "1" or "0"
a != b    // string inequality
a < b     // numeric if both numeric, lexicographic otherwise
a > b
a <= b
a >= b
```

### 5.4 Logical

```
a && b    // logical AND → "1" or "0"
a || b    // logical OR  → "1" or "0"
!a        // logical NOT
```

### 5.5 Ternary

```
condition ? trueExpr : falseExpr
```

Nestable:

```
x > 0 ? "positive" : x == 0 ? "zero" : "negative"
```

### 5.6 String Indexing

```
s[i]    // returns single character at index i
```

### 5.7 Field Access

```
obj.field    // returns the string value of the named field
```

### 5.8 Function Calls

```
functionName(arg1, arg2, arg3)
```

---

## 6. Compilation Model

### 6.1 Pipeline

```
source.k → kcc → output.c → gcc → native executable
```

1. Krypton source is tokenized and parsed
2. The compiler emits C source with an embedded runtime
3. GCC (or compatible C compiler) produces the final binary

### 6.2 C Runtime

The generated C includes a complete runtime:

- **Arena allocator** — 256 MB bump-allocation blocks
- **String constants** — `""`, `"0"`, `"1"` are pre-allocated
- **127 built-in functions** — `kr_*` prefixed C functions
- **Handle-based StringBuilder** — mutable buffers for efficient string building
- **Linked-list environments** — for variable binding in interpreter mode
- **Exception stack** — 256-deep `setjmp`/`longjmp` stack for try/catch/throw
- **Dynamic struct system** — field name/value pairs stored in arena memory

### 6.3 Self-Hosting

The compiler (`kompiler/compile.k`) compiles itself. The bootstrap chain is:

```
kcc (C++) → v010 → v020 → v030 → v040 → v050 → v060 → v070 → v071
```

---

## 7. Built-in Functions

127 built-in functions across 10 categories.

### I/O (8)
`print` / `kp`, `printErr`, `readLine`, `input`, `readFile`, `writeFile`, `arg`, `argCount`

### Strings (19)
`len`, `substring`, `charAt`, `indexOf`, `contains`, `startsWith`, `endsWith`, `replace`,
`trim`, `lstrip`, `rstrip`, `toLower`, `toUpper`, `repeat`, `padLeft`, `padRight`, `center`,
`charCode`, `fromCharCode`

### String Formatting (3)
`splitBy`, `format`, `strReverse`

### String Testing (3)
`isAlpha`, `isDigit`, `isSpace`

### Numbers (14)
`toInt`, `parseInt`, `abs`, `min`, `max`, `pow`, `sqrt`, `sign`, `clamp`,
`hex`, `bin`, `floor`, `ceil`, `round`

### Lists (24)
`split`, `length`, `append`, `insertAt`, `removeAt`, `remove`, `replaceAt`, `slice`,
`join`, `reverse`, `sort`, `unique`, `fill`, `zip`, `listIndexOf`, `every`, `some`,
`countOf`, `sumList`, `maxList`, `minList`, `range`, `first`, `last`

### List Navigation (4)
`head`, `tail`, `words`, `lines`

### Maps (3)
`keys`, `values`, `hasKey`

### Lines (3)
`getLine`, `lineCount`, `count`

### Structs (5)
`structNew`, `getField`, `setField`, `hasField`, `structFields`

### Type / Conversion (5)
`type`, `toStr`, `isTruthy`, `exit`, `assert`

### System (4)
`random`, `timestamp`, `environ`, `throw`

### StringBuilder (3)
`sbNew`, `sbAppend`, `sbToString`

### Environment (8)
`envNew`, `envSet`, `envGet`, `makeResult`, `getResultTag`, `getResultVal`, `getResultEnv`, `getResultPos`

---

## 8. Future Features

- **String interpolation** — `"Hello {name}!"`
- **Typed struct fields** — fields with declared types beyond `char*`
- **Struct nesting** — structs as field values
- **Float support** — floating-point arithmetic
- **Modules** — `module` / `import` / `export` (currently parsed, emits stubs)
- **List and map literals** — `[1, 2, 3]` syntax
- **Pattern matching with destructuring**
- **Quantum blocks** — `quantum`, `qpute`, `prepare`, `measure`
- **Concurrency / process model**

---

## Appendix A: Grammar (EBNF)

```ebnf
program     ::= decl* entry_block

decl        ::= func_decl | struct_decl

func_decl   ::= ("func" | "fn") IDENT "(" params? ")" block

struct_decl ::= ("struct" | "class" | "type") IDENT "{" struct_field* "}"

struct_field ::= "let" IDENT ("=" expr)?

params      ::= IDENT ("," IDENT)*

entry_block ::= ("just" | "go") "run" block

block       ::= "{" stmt* "}"

stmt        ::= let_stmt
              | const_stmt
              | assign_stmt
              | field_assign_stmt
              | compound_assign
              | if_stmt
              | while_stmt
              | do_while_stmt
              | for_in_stmt
              | match_stmt
              | try_stmt
              | throw_stmt
              | break_stmt
              | continue_stmt
              | emit_stmt
              | expr_stmt

let_stmt          ::= "let" IDENT "=" expr ";"?
const_stmt        ::= "const" IDENT "=" expr ";"?
assign_stmt       ::= IDENT "=" expr ";"?
field_assign_stmt ::= IDENT "." IDENT "=" expr ";"?
compound_assign   ::= IDENT ("+=" | "-=" | "*=" | "/=" | "%=") expr ";"?
if_stmt           ::= "if" expr block ("else" if_stmt | "else" block)?
while_stmt        ::= "while" expr block
do_while_stmt     ::= "do" block "while" expr ";"?
for_in_stmt       ::= "for" IDENT "in" expr block
match_stmt        ::= "match" expr "{" match_arm* "}"
match_arm         ::= (expr | "else") block
try_stmt          ::= "try" block ("catch" IDENT? block)?
throw_stmt        ::= "throw" expr ";"?
break_stmt        ::= "break" ";"?
continue_stmt     ::= "continue" ";"?
emit_stmt         ::= ("emit" | "return") expr ";"?
expr_stmt         ::= expr ";"?

expr            ::= ternary_expr
ternary_expr    ::= or_expr ("?" expr ":" expr)?
or_expr         ::= and_expr ("||" and_expr)*
and_expr        ::= eq_expr ("&&" eq_expr)*
eq_expr         ::= rel_expr (("==" | "!=") rel_expr)*
rel_expr        ::= add_expr (("<" | ">" | "<=" | ">=") add_expr)*
add_expr        ::= mul_expr (("+" | "-") mul_expr)*
mul_expr        ::= unary_expr (("*" | "/" | "%") unary_expr)*
unary_expr      ::= ("-" | "!") unary_expr | postfix_expr
postfix_expr    ::= primary ("[" expr "]" | "." IDENT)*
primary         ::= INT
                  | STRING
                  | "true" | "false"
                  | UPPER_IDENT "(" args? ")"
                  | UPPER_IDENT "{" field_inits? "}"
                  | IDENT "(" args? ")"
                  | IDENT
                  | "(" expr ")"

field_inits     ::= field_init ("," field_init)*
field_init      ::= IDENT ":" expr

args            ::= expr ("," expr)*

INT             ::= [0-9]+
STRING          ::= '"' (char | escape)* '"'
IDENT           ::= [a-zA-Z_][a-zA-Z0-9_]*
UPPER_IDENT     ::= [A-Z][a-zA-Z0-9_]*
escape          ::= "\\" | "\"" | "\n" | "\t" | "\r"
```

## Appendix B: Reserved Words

```
just  go  func  fn  let  const  emit  return  if  else  while
break  continue  for  in  match  do  struct  class  type
try  catch  throw  module  import  export  true  false
quantum  qpute  process  prepare  measure
```
