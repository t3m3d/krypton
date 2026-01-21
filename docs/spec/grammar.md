# Krypton Grammar (v0.1 Draft)

program     ::= statement*
statement   ::= let_decl | fn_decl | expr
let_decl    ::= "let" IDENT "=" expr
fn_decl     ::= "fn" IDENT "(" params? ")" block
expr        ::= literal | IDENT | call | binary