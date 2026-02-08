program ::= module_decl? decl*

module_decl ::= "module" IDENT

decl ::= fn_decl
       | qpute_decl
       | process_decl
       | main_decl

fn_decl ::= "fn" IDENT "(" params? ")" "->" type block

qpute_decl ::= "quantum" "qpute" IDENT "(" params? ")" block

process_decl ::= "go" IDENT block

main_decl ::= "run" block

params ::= param ("," param)*
param  ::= IDENT ":" type

block ::= "{" statement* "}"

statement ::= let_stmt
            | emit_stmt
            | kp_stmt
            | if_stmt
            | expr_stmt

let_stmt ::= "let" IDENT "=" expr ";"

emit_stmt ::= "emit" expr ";"

kp_stmt ::= "kp" expr ";"

if_stmt ::= "if" "(" expr ")" block ("else" block)?

expr_stmt ::= expr ";"

expr ::= or_expr

or_expr ::= and_expr ("||" and_expr)*

and_expr ::= equality_expr ("&&" equality_expr)*

equality_expr ::= rel_expr (("==" | "!=") rel_expr)*

rel_expr ::= add_expr (("<" | ">" | "<=" | ">=") add_expr)*

add_expr ::= mul_expr (("+" | "-") mul_expr)*

mul_expr ::= unary_expr (("*" | "/") unary_expr)*

unary_expr ::= ("!" | "+" | "-") unary_expr
             | primary

primary ::= literal
          | IDENT
          | call
          | "(" expr ")"
          | "prepare" IDENT
          | "measure" IDENT

call ::= IDENT "(" args? ")"

args ::= expr ("," expr)*

literal ::= INT | FLOAT | STRING | "true" | "false"
