#pragma once
#include <memory>
#include <string>
#include <variant>
#include <vector>

namespace k {

// Forward declarations
struct Expr;
struct Stmt;
struct Block;
struct FnDecl;
struct QputeDecl;
struct ProcessDecl;
struct ModuleDecl;
struct ImportDecl;

// Shared pointer aliases
using ExprPtr = std::shared_ptr<Expr>;
using StmtPtr = std::shared_ptr<Stmt>;
using BlockPtr = std::shared_ptr<Block>;
using FnDeclPtr = std::shared_ptr<FnDecl>;
using QputeDeclPtr = std::shared_ptr<QputeDecl>;
using ProcessDeclPtr = std::shared_ptr<ProcessDecl>;
using ModuleDeclPtr = std::shared_ptr<ModuleDecl>;

// ===============================
// Types
// ===============================

enum class TypeKind { Primitive, Quantum, Named };
enum class PrimitiveTypeKind { Int, Float, Bool, String };

struct TypeNode {
  TypeKind kind;

  PrimitiveTypeKind primitive;
  std::string name;
  bool isQuantum = false;

  static TypeNode primitiveType(PrimitiveTypeKind p) {
    TypeNode t;
    t.kind = TypeKind::Primitive;
    t.primitive = p;
    return t;
  }

  static TypeNode quantumQbit() {
    TypeNode t;
    t.kind = TypeKind::Quantum;
    t.isQuantum = true;
    return t;
  }

  static TypeNode named(const std::string &n) {
    TypeNode t;
    t.kind = TypeKind::Named;
    t.name = n;
    return t;
  }
};

// ===============================
// Parameters
// ===============================

struct Param {
  std::string name;
  TypeNode type;
};

struct QParam {
  std::string name;
  TypeNode type;
};

// ===============================
// Import Declarations
// ===============================

struct ImportDecl {
  std::vector<std::string> path;
};

// ===============================
// Expressions
// ===============================

enum class ExprKind {
  Literal,
  Identifier,
  Binary,
  Unary,
  Call,
  Prepare,
  Measure,
  Grouping
};

struct Expr {
  ExprKind kind;

  std::string literalValue;
  std::string identifier;

  std::string op;
  ExprPtr left;
  ExprPtr right;

  std::vector<ExprPtr> args;

  ExprPtr inner;

  static ExprPtr literal(const std::string &v) {
    auto e = std::make_shared<Expr>();
    e->kind = ExprKind::Literal;
    e->literalValue = v;
    return e;
  }

  static ExprPtr identifierExpr(const std::string &name) {
    auto e = std::make_shared<Expr>();
    e->kind = ExprKind::Identifier;
    e->identifier = name;
    return e;
  }

  static ExprPtr binary(const std::string &op, ExprPtr l, ExprPtr r) {
    auto e = std::make_shared<Expr>();
    e->kind = ExprKind::Binary;
    e->op = op;
    e->left = l;
    e->right = r;
    return e;
  }

  static ExprPtr unary(const std::string &op, ExprPtr r) {
    auto e = std::make_shared<Expr>();
    e->kind = ExprKind::Unary;
    e->op = op;
    e->right = r;
    return e;
  }

  static ExprPtr call(const std::string &name,
                      const std::vector<ExprPtr> &args) {
    auto e = std::make_shared<Expr>();
    e->kind = ExprKind::Call;
    e->identifier = name;
    e->args = args;
    return e;
  }

  static ExprPtr prepare() {
    auto e = std::make_shared<Expr>();
    e->kind = ExprKind::Prepare;
    return e;
  }

  static ExprPtr measure(const std::string &target) {
    auto e = std::make_shared<Expr>();
    e->kind = ExprKind::Measure;
    e->identifier = target;
    return e;
  }

  static ExprPtr grouping(ExprPtr inner) {
    auto e = std::make_shared<Expr>();
    e->kind = ExprKind::Grouping;
    e->inner = inner;
    return e;
  }
};

// ===============================
// Statements
// ===============================

enum class StmtKind { Let, Return, If, Expr };

struct Stmt {
  StmtKind kind;

  std::string name;
  ExprPtr expr;

  ExprPtr condition;
  BlockPtr thenBlock;

  static StmtPtr letStmt(const std::string &name, ExprPtr value) {
    auto s = std::make_shared<Stmt>();
    s->kind = StmtKind::Let;
    s->name = name;
    s->expr = value;
    return s;
  }

  static StmtPtr returnStmt(ExprPtr value) {
    auto s = std::make_shared<Stmt>();
    s->kind = StmtKind::Return;
    s->expr = value;
    return s;
  }

  static StmtPtr ifStmt(ExprPtr cond, BlockPtr block) {
    auto s = std::make_shared<Stmt>();
    s->kind = StmtKind::If;
    s->condition = cond;
    s->thenBlock = block;
    return s;
  }

  static StmtPtr exprStmt(ExprPtr value) {
    auto s = std::make_shared<Stmt>();
    s->kind = StmtKind::Expr;
    s->expr = value;
    return s;
  }
};

// ===============================
// Blocks
// ===============================

struct Block {
  std::vector<StmtPtr> statements;

  // Required by parser.cpp
  static BlockPtr create() { return std::make_shared<Block>(); }

  static BlockPtr make(const std::vector<StmtPtr> &stmts) {
    auto b = std::make_shared<Block>();
    b->statements = stmts;
    return b;
  }
};

// ===============================
// Function Declarations
// ===============================

struct FnDecl {
  std::string name;
  std::vector<Param> params;
  TypeNode returnType;
  BlockPtr body;

  static FnDeclPtr make(const std::string &name,
                        const std::vector<Param> &params, const TypeNode &ret,
                        BlockPtr body) {
    auto f = std::make_shared<FnDecl>();
    f->name = name;
    f->params = params;
    f->returnType = ret;
    f->body = body;
    return f;
  }
};

// ===============================
// Qpute Declarations
// ===============================

struct QputeDecl {
  std::string name;
  std::vector<QParam> params;
  BlockPtr body;

  static QputeDeclPtr make(const std::string &name,
                           const std::vector<QParam> &params, BlockPtr body) {
    auto q = std::make_shared<QputeDecl>();
    q->name = name;
    q->params = params;
    q->body = body;
    return q;
  }
};

// ===============================
// Process Declarations
// ===============================

struct ProcessDecl {
  std::string name;
  BlockPtr body;

  static ProcessDeclPtr make(const std::string &name, BlockPtr body) {
    auto p = std::make_shared<ProcessDecl>();
    p->name = name;
    p->body = body;
    return p;
  }
};

// ===============================
// Module
// ===============================

struct ModuleDecl {
  std::vector<std::variant<FnDeclPtr, QputeDeclPtr, ProcessDeclPtr>> decls;

  static ModuleDeclPtr
  make(const std::vector<std::variant<FnDeclPtr, QputeDeclPtr, ProcessDeclPtr>>
           &decls) {
    auto m = std::make_shared<ModuleDecl>();
    m->decls = decls;
    return m;
  }
};

}