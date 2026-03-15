# Krypton Grammar

**Version 0.7.2** — Complete EBNF grammar for the Krypton language.

```ebnf
(* ===== Top-Level ===== *)

program     ::= decl* entry_block

decl        ::= func_decl | struct_decl

func_decl   ::= ("func" | "fn") IDENT "(" params? ")" block

struct_decl ::= ("struct" | "class" | "type") UPPER_IDENT "{" struct_field* "}"

struct_field ::= "let" IDENT ("=" expr)?

params      ::= IDENT ("," IDENT)*

entry_block ::= ("just" | "go") "run" block


(* ===== Blocks ===== *)

block       ::= "{" stmt* "}"


(* ===== Statements ===== *)

stmt        ::= let_stmt
              | const_stmt
              | field_assign_stmt
              | assign_stmt
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
postfix_expr    ::= primary ("[" expr "]" | "." IDENT)*
primary         ::= INT
                   | STRING
                   | INTERP_STRING
                   | "true"
                   | "false"
                   | UPPER_IDENT "(" args? ")"
                   | UPPER_IDENT "{" field_inits? "}"
                   | IDENT "(" args? ")"
                   | IDENT
                   | "(" expr ")"

field_inits     ::= field_init ("," field_init)*
field_init      ::= IDENT ":" expr
args            ::= expr ("," expr)*


(* ===== Tokens ===== *)

INT             ::= [0-9]+
STRING          ::= '"' (char | escape)* '"'
INTERP_STRING   ::= '`' (char | '{' IDENT '}')* '`'
IDENT           ::= [a-zA-Z_][a-zA-Z0-9_]*
UPPER_IDENT     ::= [A-Z][a-zA-Z0-9_]*
escape          ::= "\\" | "\"" | "\n" | "\t" | "\r"

COMMENT         ::= "//" [^\n]* | "/*" .* "*/"
WHITESPACE      ::= [ \t\n\r]+
```

## Operator Precedence

From highest to lowest:

| Precedence | Category | Operators | Associativity |
|------------|----------|-----------|---------------|
| 1 | Postfix | `[i]`, `f()`, `.field` | Left-to-right |
| 2 | Unary | `-`, `!` | Right-to-left |
| 3 | Multiplicative | `*`, `/`, `%` | Left-to-right |
| 4 | Additive | `+`, `-` | Left-to-right |
| 5 | Relational | `<`, `>`, `<=`, `>=` | Left-to-right |
| 6 | Equality | `==`, `!=` | Left-to-right |
| 7 | Logical AND | `&&` | Left-to-right |
| 8 | Logical OR | `\|\|` | Left-to-right |
| 9 | Ternary | `? :` | Right-to-left |
| 10 | Assignment | `=`, `+=`, `-=`, `*=`, `/=`, `%=` | Right-to-left |

## Keywords

```
just  go  func  fn  let  const  emit  return
if  else  while  break  continue  for  in
match  do  struct  class  type  try  catch  throw
module  import  export  true  false
```

### Reserved (future)
```
quantum  qpute  process  prepare  measure
```

## Token Types

| Token | Pattern |
|-------|---------|
| `INT:n` | Integer literal |
| `STR:s` | String literal (contents, no quotes) |
| `INTERP:s` | Backtick interpolation string (raw contents) |
| `KW:word` | Keyword |
| `ID:name` | Identifier |
| `PLUS` | `+` |
| `MINUS` | `-` |
| `STAR` | `*` |
| `SLASH` | `/` |
| `MOD` | `%` |
| `ASSIGN` | `=` |
| `EQ` | `==` |
| `NEQ` | `!=` |
| `LT` | `<` |
| `GT` | `>` |
| `LTE` | `<=` |
| `GTE` | `>=` |
| `AND` | `&&` |
| `OR` | `\|\|` |
| `BANG` | `!` |
| `PLUSEQ` | `+=` |
| `MINUSEQ` | `-=` |
| `STAREQ` | `*=` |
| `SLASHEQ` | `/=` |
| `MODEQ` | `%=` |
| `QUESTION` | `?` |
| `COLON` | `:` |
| `DOT` | `.` |
| `COMMA` | `,` |
| `SEMI` | `;` |
| `ARROW` | `->` |
| `LPAREN` | `(` |
| `RPAREN` | `)` |
| `LBRACE` | `{` |
| `RBRACE` | `}` |
| `LBRACK` | `[` |
| `RBRACK` | `]` |
