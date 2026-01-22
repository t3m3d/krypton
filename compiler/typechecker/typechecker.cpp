#include "typechecker.hpp"
#include <stdexcept>

namespace k {

// -------------------------
// Helpers
// -------------------------

TypeNode TypeChecker::boolType() const {
  return TypeNode::primitiveType(PrimitiveTypeKind::Bool);
}

TypeNode TypeChecker::intType() const {
  return TypeNode::primitiveType(PrimitiveTypeKind::Int);
}

TypeNode TypeChecker::floatType() const {
  return TypeNode::primitiveType(PrimitiveTypeKind::Float);
}

TypeNode TypeChecker::stringType() const {
  return TypeNode::primitiveType(PrimitiveTypeKind::String);
}

TypeNode TypeChecker::qbitType() const { return TypeNode::quantumQbit(); }

bool TypeChecker::isBool(const TypeNode &t) const {
  return t.kind == TypeKind::Primitive &&
         t.primitive == PrimitiveTypeKind::Bool;
}

bool TypeChecker::isInt(const TypeNode &t) const {
  return t.kind == TypeKind::Primitive && t.primitive == PrimitiveTypeKind::Int;
}

bool TypeChecker::isFloat(const TypeNode &t) const {
  return t.kind == TypeKind::Primitive &&
         t.primitive == PrimitiveTypeKind::Float;
}

bool TypeChecker::isNumeric(const TypeNode &t) const {
  return isInt(t) || isFloat(t);
}

bool TypeChecker::isQbit(const TypeNode &t) const {
  return t.kind == TypeKind::Quantum && t.isQuantum;
}

// -------------------------
// Module
// -------------------------

void TypeChecker::checkModule(const ModuleDecl &module) {
  // For now, we just walk decls in order.
  for (const auto &v : module.decls) {
    if (std::holds_alternative<FnDeclPtr>(v)) {
      checkFn(*std::get<FnDeclPtr>(v));
    } else if (std::holds_alternative<QputeDeclPtr>(v)) {
      checkQpute(*std::get<QputeDeclPtr>(v));
    } else if (std::holds_alternative<ProcessDeclPtr>(v)) {
      checkProcess(*std::get<ProcessDeclPtr>(v));
    }
  }
}

// -------------------------
// Declarations
// -------------------------

void TypeChecker::checkFn(const FnDecl &fn) {
  // Classical function: no quantum params allowed
  for (const auto &p : fn.params) {
    if (isQbit(p.type)) {
      throw std::runtime_error("Quantum parameter in classical function: " +
                               p.name);
    }
    env.define(p.name, p.type);
  }

  checkBlock(fn.body);
}

void TypeChecker::checkQpute(const QputeDecl &qp) {
  // Quantum block: params must be qbit
  for (const auto &p : qp.params) {
    if (!isQbit(p.type)) {
      throw std::runtime_error("Non-quantum parameter in qpute: " + p.name);
    }
    env.define(p.name, p.type);
  }

  // Enforce quantum-only rules at expression level
  checkBlock(qp.body);
}

void TypeChecker::checkProcess(const ProcessDecl &proc) {
  // Processes can mix classical + quantum orchestration
  checkBlock(proc.body);
}

// -------------------------
// Blocks & statements
// -------------------------

void TypeChecker::checkBlock(const BlockPtr &block) {
  for (const auto &stmt : block->statements) {
    checkStmt(stmt);
  }
}

void TypeChecker::checkStmt(const StmtPtr &stmt) {
  switch (stmt->kind) {
  case StmtKind::Let: {
    TypeNode t = checkExpr(stmt->expr);
    env.define(stmt->name, t);
    break;
  }
  case StmtKind::Return: {
    (void)checkExpr(stmt->expr);
    break;
  }
  case StmtKind::If: {
    TypeNode condType = checkExpr(stmt->condition);
    if (!isBool(condType)) {
      throw std::runtime_error("If condition must be bool");
    }
    checkBlock(stmt->thenBlock);
    break;
  }
  case StmtKind::Expr: {
    (void)checkExpr(stmt->expr);
    break;
  }
  }
}

// -------------------------
// Expressions
// -------------------------

TypeNode TypeChecker::checkExpr(const ExprPtr &expr) {
  switch (expr->kind) {
  case ExprKind::Literal: {
    // crude: infer type from content
    const std::string &v = expr->literalValue;
    if (v == "true" || v == "false")
      return boolType();
    bool isFloatLit = v.find('.') != std::string::npos;
    if (isFloatLit)
      return floatType();
    // fallback: int
    return intType();
  }

  case ExprKind::Identifier: {
    TypeNode t;
    if (!env.lookup(expr->identifier, t)) {
      throw std::runtime_error("Use of undeclared variable: " +
                               expr->identifier);
    }
    return t;
  }

  case ExprKind::Binary: {
    TypeNode leftT = checkExpr(expr->left);
    TypeNode rightT = checkExpr(expr->right);

    const std::string &op = expr->op;

    if (op == "==" || op == "!=") {
      // allow any comparable types for now
      return boolType();
    }

    if (op == "&&" || op == "||") {
      if (!isBool(leftT) || !isBool(rightT)) {
        throw std::runtime_error("Logical operators require bool operands");
      }
      return boolType();
    }

    if (op == "<" || op == ">" || op == "<=" || op == ">=") {
      if (!isNumeric(leftT) || !isNumeric(rightT)) {
        throw std::runtime_error(
            "Comparison operators require numeric operands");
      }
      return boolType();
    }

    if (op == "+" || op == "-" || op == "*" || op == "/") {
      if (!isNumeric(leftT) || !isNumeric(rightT)) {
        throw std::runtime_error(
            "Arithmetic operators require numeric operands");
      }
      // simple rule: if either is float, result is float
      if (isFloat(leftT) || isFloat(rightT))
        return floatType();
      return intType();
    }

    throw std::runtime_error("Unknown binary operator: " + op);
  }

  case ExprKind::Unary: {
    TypeNode t = checkExpr(expr->right);
    const std::string &op = expr->op;

    if (op == "!") {
      if (!isBool(t)) {
        throw std::runtime_error("Unary '!' requires bool operand");
      }
      return boolType();
    }

    if (op == "+" || op == "-") {
      if (!isNumeric(t)) {
        throw std::runtime_error("Unary '+'/'-' require numeric operand");
      }
      return t;
    }

    throw std::runtime_error("Unknown unary operator: " + op);
  }

  case ExprKind::Call: {
    // For now, we don't have function type info stored.
    // Minimal check: arguments are well-typed.
    for (const auto &arg : expr->args) {
      (void)checkExpr(arg);
    }
    // Return type unknown -> treat as int for now (placeholder).
    return intType();
  }

  case ExprKind::Prepare: {
    // prepare qbit -> qbit
    return qbitType();
  }

  case ExprKind::Measure: {
    // measure qbit -> bool (bit)
    TypeNode t;
    if (!env.lookup(expr->identifier, t)) {
      throw std::runtime_error("Measure of undeclared variable: " +
                               expr->identifier);
    }
    if (!isQbit(t)) {
      throw std::runtime_error("Can only measure qbit");
    }
    return boolType();
  }

  case ExprKind::Grouping: {
    return checkExpr(expr->inner);
  }
  }

  throw std::runtime_error("Unknown expression kind");
}

// -------------------------
// Quantum context enforcement (placeholder)
// -------------------------

void TypeChecker::ensureQuantumContext(const ExprPtr & /*expr*/) {
  // Future: enforce that certain expressions only appear in qpute blocks.
}

} // namespace k