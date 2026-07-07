# Krypton Grammar

**Version 2.3.0** — EBNF grammar for the Krypton language and KryptScript.

```ebnf
(* ===== Top-Level ===== *)

(* A `.ks` (KryptScript) file may begin with a POSIX shebang. The tokenizer
   strips the first line when it starts with `#!`. Both `.k` and `.ks`
   share the rest of the grammar; the extension is a naming convention,
   not a parser switch. *)
program     ::= shebang? module_decl? top_level* entry_block?
shebang     ::= "#!" [^\n]* "\n"

top_level   ::= func_decl
              | callback_decl
              | struct_decl
              | import_stmt
              | export_decl
              | jxt_block
              | global_let

module_decl ::= "module" IDENT

(* Import paths support 2.0 prefixes — `k:`/`core:` resolve to
   `<KRYPTON_ROOT>/stdlib/`, `head:`/`headers:` to `<KRYPTON_ROOT>/headers/`. *)
import_stmt ::= "import" STRING
export_decl ::= "export" (func_decl | struct_decl | IDENT)

func_decl     ::= ("func" | "fn") IDENT "(" params? ")" ("->" type)? block
callback_decl ::= "callback" func_decl

struct_decl ::= ("struct" | "class" | "type") UPPER_IDENT "{" struct_field* "}"
struct_field ::= "let" IDENT (":" type)? ("=" expr)?

params      ::= param ("," param)*
param       ::= IDENT (":" type)?

(* Type grammar (2.0 typed pointers).
     IDENT             - dynamic / opaque (the default)
     "*" type          - typed pointer (Phase C — *u8/u16/u32/u64/i32/i64/Vec3/...)
     "[" type "]"      - homogenous list
     "[" "*" type "]"  - list of typed pointers
     "fp" / "closure"  - function-pointer / closure receivers (2.0 alpha-1+)
     "do"              - action-only / no-result return contract
*)
type        ::= "*" type
              | "[" type "]"
              | "do"
              | IDENT

global_let  ::= ("let" | "const") IDENT "=" expr ";"?

entry_block ::= ("just" | "go") "run" block

(* `jxt` is a header-include block. The classic form uses braces;
   the bracketless form (1.4.0+) treats successive `inc "..."` lines
   as members until the first non-`inc` token. *)
jxt_block   ::= "jxt" "{" jxt_item* "}"
              | "jxt" jxt_inc_line+
jxt_item    ::= ("k" | "c" | "t") STRING
jxt_inc_line ::= "inc" STRING


(* ===== Blocks ===== *)

block       ::= "{" stmt* "}"


(* ===== Statements ===== *)

stmt        ::= let_stmt
              | const_stmt
              | nested_func_decl
              | field_assign_stmt
              | index_assign_stmt
              | assign_stmt
              | compound_assign
              | inc_dec_stmt
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

let_stmt          ::= "let" "local"? IDENT (":" type)? "=" expr ";"?
                    | "let" "local" type IDENT       (* 2.0 stack-shape alloc — see note below *)
const_stmt        ::= "const" IDENT (":" type)? "=" expr ";"?
nested_func_decl  ::= func_decl   (* hoisted to file scope as a sibling *)

assign_stmt       ::= IDENT "=" expr ";"?
field_assign_stmt ::= IDENT "." IDENT "=" expr ";"?
index_assign_stmt ::= IDENT "[" expr "]" "=" expr ";"?
compound_assign   ::= IDENT ("+=" | "-=" | "*=" | "/=" | "%=") expr ";"?
inc_dec_stmt      ::= IDENT ("++" | "--") ";"?
                    | ("++" | "--") IDENT ";"?

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
emit_stmt         ::= ("emit" | "return") expr? ";"?
expr_stmt         ::= expr ";"?


(* ===== Expressions ===== *)

expr            ::= ternary_expr
ternary_expr    ::= or_expr ("?" expr ":" expr)?
or_expr         ::= and_expr ("||" and_expr)*
and_expr        ::= eq_expr ("&&" eq_expr)*
eq_expr         ::= rel_expr (("==" | "!=") rel_expr)*
rel_expr        ::= add_expr (("<" | ">" | "<=" | ">=") add_expr)*
add_expr        ::= mul_expr (("+" | "-") mul_expr)*
mul_expr        ::= unary_expr (("*" | "/" | "%") unary_expr)*
unary_expr      ::= ("-" | "!") unary_expr | postfix_expr
postfix_expr    ::= primary ("[" expr "]" | "." IDENT | "(" args? ")")*
primary         ::= INT
                   | STRING
                   | INTERP_STRING
                   | "true"
                   | "false"
                   | "null"
                   | list_literal
                   | lambda
                   | UPPER_IDENT "(" args? ")"
                   | UPPER_IDENT "{" field_inits? "}"
                   | IDENT "(" args? ")"
                   | IDENT
                   | "(" expr ")"

list_literal    ::= "[" (expr ("," expr)*)? "]"

(* A lambda is a `func`/`fn` literal as an expression. In 2.0+ lambdas
   are closures: free variables in `block` (those not declared inside
   it or in its `params`) are snapshot-captured by value. Capture-free
   lambdas (and named nested funcs hoisted to file scope) avoid the
   closure header entirely and dispatch as plain function pointers. *)
lambda          ::= ("func" | "fn") "(" params? ")" ("->" type)? block

field_inits     ::= field_init ("," field_init)*
field_init      ::= IDENT ":" expr
args            ::= expr ("," expr)*


(* ===== Tokens ===== *)

INT             ::= [0-9]+
                  | "0x" [0-9a-fA-F]+
STRING          ::= '"' (char | escape)* '"'
INTERP_STRING   ::= '`' (char | '{' expr '}')* '`'
IDENT           ::= [a-zA-Z_][a-zA-Z0-9_]*
UPPER_IDENT     ::= [A-Z][a-zA-Z0-9_]*
escape          ::= "\\" | "\"" | "\n" | "\t" | "\r"

COMMENT         ::= "//" [^\n]* | "/*" .* "*/"
WHITESPACE      ::= [ \t\n\r]+
```

## Operator Precedence

From highest to lowest:

| Precedence | Category       | Operators                         | Associativity  |
|------------|----------------|-----------------------------------|----------------|
| 1          | Postfix        | `[i]`, `f()`, `.field`            | Left-to-right  |
| 2          | Unary          | `-`, `!`                          | Right-to-left  |
| 3          | Multiplicative | `*`, `/`, `%`                     | Left-to-right  |
| 4          | Additive       | `+`, `-`                          | Left-to-right  |
| 5          | Relational     | `<`, `>`, `<=`, `>=`              | Left-to-right  |
| 6          | Equality       | `==`, `!=`                        | Left-to-right  |
| 7          | Logical AND    | `&&`                              | Left-to-right  |
| 8          | Logical OR     | `\|\|`                            | Left-to-right  |
| 9          | Ternary        | `? :`                             | Right-to-left  |
| 10         | Assignment     | `=`, `+=`, `-=`, `*=`, `/=`, `%=` | Right-to-left  |

## Keywords

```
just  go  func  fn  let  local  const  emit  return
if  else  while  do  loop  until  break  continue
for  in  match  struct  class  type  callback
try  catch  throw
module  import  export  jxt
true  false  null
```

`local` is only meaningful immediately after `let` (`let local TYPE
name`). Elsewhere it can be used as a regular identifier.

### Reserved (future)
```
quantum  qpute  process  prepare  measure
```

These are reserved by the tokenizer for the eventual quantum-computing
backend; using any as an identifier is a tokenization error today.

## Notes on the grammar

- **`.k` vs `.ks`.** Both extensions go through the same tokenizer and
  parser. `.k` is the default; `.ks` (KryptScript, 2.2+) signals "script"
  and is what installer associations / VS Code activation patterns key on.
  Either may begin with a `#!/usr/bin/env kr` shebang — the tokenizer
  drops the first line when it starts with `#!`. On Windows the installer
  associates `.ks` with `kr.exe` (a tiny native PE wrapper that runs
  `kcc -r` internally), so cmd.exe `myscript.ks args` and Explorer
  double-click both invoke the script directly — the Windows equivalent
  of a `.bat`.
- **`run.k` convention.** For projects that span more than one file
  (signalled by an explicit `module <name>` decl on any file), the
  `just run { ... }` entry block must live in a file literally named
  `run.k` (or `run.ks`). The compiler emits a warning today when it
  doesn't; the warning becomes a hard error in the next major release.
  Single-file scripts (no `module` decl) are exempt — they can keep
  the `just run { ... }` body in any filename.
- **Nested function declarations.** A `func name(...) { ... }` inside a
  block is hoisted to file-scope by the IR walk and dispatches as a
  plain function pointer. Anonymous `func(...) { ... }` lambdas in
  expression position are closures (2.0+) when they reference free
  variables, and plain function pointers otherwise — the pre-scan in
  `compile.k` (`irScanFuncTypes`) decides per-lambda.
- **`let local TYPE name`** desugars to
  `let name: *TYPE = bufNew(sizeof(TYPE))` and gives `name` the same
  `*TYPE` typed-pointer semantics as a `bufNew` result — so
  `let local Vec3 v` lets `v.x = 5` and `v.x` lower to direct typed
  buffer reads/writes at the struct field's offset. Heap-backed today;
  real stack allocation is a future codegen optimisation, but the
  user-facing syntax already matches.
- **`jxt` bracketless form (1.4.0+).** When `jxt` is followed by anything
  other than `{`, the tokenizer rewrites successive `inc "path"` lines
  into the classic brace form, with the include type inferred from the
  file extension (`.k` → Krypton module, `.h`/`.krh` → C header).
- **`emit` vs `return`.** The two keywords are interchangeable. Idiomatic
  Krypton uses `emit` for value-producing functions. `do` is the action-only
  / no-result return contract: `func log(x) -> do { print(x) }`. A function
  that only does work can fall through without emitting a value; the parser
  accepts `return` as a synonym for `emit` for compatibility.
- **Backtick strings** support `{expr}` interpolation; in 1.4.0+ the
  embedded expression can be any expression (not just a bare identifier).

## Token Types

| Token        | Pattern               |
|--------------|-----------------------|
| `INT:n`      | Integer literal       |
| `STR:s`      | String literal (contents, no quotes) |
| `INTERP:s`   | Backtick interpolation string (raw contents) |
| `KW:word`    | Keyword               |
| `ID:name`    | Identifier            |
| `CBLOCK`     | Inline `cfunc { ... }` C block |
| `PLUS`       | `+`                   |
| `MINUS`      | `-`                   |
| `STAR`       | `*`                   |
| `SLASH`      | `/`                   |
| `MOD`        | `%`                   |
| `ASSIGN`     | `=`                   |
| `EQ`         | `==`                  |
| `NEQ`        | `!=`                  |
| `LT`         | `<`                   |
| `GT`         | `>`                   |
| `LTE`        | `<=`                  |
| `GTE`        | `>=`                  |
| `AND`        | `&&`                  |
| `OR`         | `\|\|`                |
| `BANG`       | `!`                   |
| `PLUSEQ`     | `+=`                  |
| `MINUSEQ`    | `-=`                  |
| `STAREQ`     | `*=`                  |
| `SLASHEQ`    | `/=`                  |
| `MODEQ`      | `%=`                  |
| `PLUSPLUS`   | `++`                  |
| `MINUSMINUS` | `--`                  |
| `QUESTION`   | `?`                   |
| `COLON`      | `:`                   |
| `DOT`        | `.`                   |
| `COMMA`      | `,`                   |
| `SEMI`       | `;`                   |
| `ARROW`      | `->`                  |
| `LPAREN`     | `(`                   |
| `RPAREN`     | `)`                   |
| `LBRACE`     | `{`                   |
| `RBRACE`     | `}`                   |
| `LBRACK`     | `[`                   |
| `RBRACK`     | `]`                   |
