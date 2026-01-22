// ===============================
// Krypton AST Node Definitions v1
// ===============================

AstNode = 
      ModuleDecl
    | FnDecl
    | QputeDecl
    | ProcessDecl
    | Block
    | Stmt
    | Expr
    ;

// -------------------------------
// Module
// -------------------------------

ModuleDecl {
    name: Identifier
    decls: List<AstNode>
}

// -------------------------------
// Declarations
// -------------------------------

FnDecl {
    name: Identifier
    params: List<Param>
    return_type: TypeNode
    body: Block
}

QputeDecl {
    name: Identifier
    params: List<QParam>
    return_type: TypeNode
    body: Block
}

ProcessDecl {
    name: Identifier
    body: Block
}

// -------------------------------
// Parameters
// -------------------------------

Param {
    name: Identifier
    type: TypeNode
}

QParam {
    name: Identifier
    type: QTypeNode   // restricted to qbit for v1
}

// -------------------------------
// Types
// -------------------------------

TypeNode =
      PrimitiveTypeNode
    | QTypeNode
    | NamedTypeNode
    ;

PrimitiveTypeNode {
    kind: "int" | "float" | "bool" | "string"
}

QTypeNode {
    kind: "qbit"
}

NamedTypeNode {
    name: Identifier
}

// -------------------------------
// Blocks & Statements
// -------------------------------

Block {
    statements: List<Stmt>
}

Stmt =
      LetStmt
    | ReturnStmt
    | IfStmt
    | ExprStmt
    ;

LetStmt {
    name: Identifier
    value: Expr
}

ReturnStmt {
    value: Expr
}

IfStmt {
    condition: Expr
    then_block: Block
}

ExprStmt {
    expr: Expr
}

// -------------------------------
// Expressions
// -------------------------------

Expr =
      LiteralExpr
    | IdentifierExpr
    | BinaryExpr
    | UnaryExpr
    | CallExpr
    | PrepareExpr
    | MeasureExpr
    | GroupingExpr
    ;

LiteralExpr {
    value: Literal
}

IdentifierExpr {
    name: Identifier
}

BinaryExpr {
    left: Expr
    operator: BinaryOperator
    right: Expr
}

UnaryExpr {
    operator: UnaryOperator
    operand: Expr
}

CallExpr {
    callee: Identifier
    args: List<Expr>
}

PrepareExpr {
    // prepare qbit
}

MeasureExpr {
    target: Identifier
}

GroupingExpr {
    expr: Expr
}

// -------------------------------
// Operators
// -------------------------------

BinaryOperator =
      "+"
    | "-"
    | "*"
    | "/"
    | "=="
    | "!="
    | "<"
    | ">"
    | "<="
    | ">="
    | "&&"
    | "||"
    ;

UnaryOperator =
      "+"
    | "-"
    | "!"
    ;

// -------------------------------
// Lexical Elements
// -------------------------------

Identifier = string

Literal =
      IntLiteral
    | FloatLiteral
    | BoolLiteral
    | StringLiteral
    ;