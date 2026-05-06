# Krypton Grammar

**Version 1.8.0** — EBNF grammar for the Krypton language.

```ebnf
(* ===== Top-Level ===== *)

program     ::= module_decl? top_level* entry_block?

top_level   ::= func_decl
              | callback_decl
              | struct_decl
              | import_stmt
              | export_decl
              | jxt_block
              | global_let

module_decl ::= "module" IDENT
import_stmt ::= "import" STRING
export_decl ::= "export" (func_decl | struct_decl | IDENT)

func_decl     ::= ("func" | "fn") IDENT "(" params? ")" ("->" type)? block
callback_decl ::= "callback" func_decl

struct_decl ::= ("struct" | "class" | "type") UPPER_IDENT "{" struct_field* "}"
struct_field ::= "let" IDENT (":" type)? ("=" expr)?

params      ::= param ("," param)*
param       ::= IDENT (":" type)?
type        ::= IDENT ("[" type "]")?

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

let_stmt          ::= "let" IDENT (":" type)? "=" expr ";"?
const_stmt        ::= "const" IDENT (":" type)? "=" expr ";"?
nested_func_decl  ::= func_decl   (* hoisted to file scope; no closures *)

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
just  go  func  fn  let  const  emit  return
if  else  while  do  loop  until  break  continue
for  in  match  struct  class  type  callback
try  catch  throw
module  import  export  jxt
true  false  null
```

### Reserved (future)
```
quantum  qpute  process  prepare  measure
```

These are reserved by the tokenizer for the eventual quantum-computing
backend; using any as an identifier is a tokenization error today.

## Notes on the grammar

- **Nested function declarations.** A `func name(...) { ... }` inside a `just run`
  block (or any block, in principle) is hoisted to file scope by the IR walk.
  Krypton has no closures, so a nested `func` is semantically a sibling.
- **`jxt` bracketless form (1.4.0+).** When `jxt` is followed by anything other
  than `{`, the tokenizer rewrites successive `inc "path"` lines into the
  classic brace form, with the include type inferred from the file extension
  (`.k` → Krypton module, `.h`/`.krh` → C header).
- **`emit` vs `return`.** The two keywords are interchangeable. Idiomatic
  Krypton uses `emit` for value-producing functions and `return` for void
  returns; the parser doesn't distinguish.
- **Backtick strings** support `{expr}` interpolation; in 1.4.0+ the embedded
  expression can be any expression (not just a bare identifier).

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
