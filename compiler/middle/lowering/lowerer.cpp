#include "lowerer.hpp"
#include <stdexcept>

namespace k {

// ------------------------------------------------------------
//  lowerModule — unchanged from your version
// ------------------------------------------------------------
std::unordered_map<std::string, LoweredProcess>
Lowerer::lowerModule(const ModuleDecl &module) {
  std::unordered_map<std::string, LoweredProcess> result;

  for (const auto &v : module.decls) {
    if (std::holds_alternative<ProcessDeclPtr>(v)) {
      auto proc = std::get<ProcessDeclPtr>(v);
      LoweredProcess lp;
      curClassical = &lp.classical;
      curQuantum = &lp.quantum;

      lowerProcess(*proc, lp);

      result[proc->name] = std::move(lp);
      curClassical = nullptr;
      curQuantum = nullptr;
    }
  }

  return result;
}

// ------------------------------------------------------------
//  NEW: lowerFunctions — lowers all fn declarations
// ------------------------------------------------------------
FunctionIRTable Lowerer::lowerFunctions(const ModuleDecl &module) {
  FunctionIRTable table;

  for (const auto &v : module.decls) {
    if (std::holds_alternative<FnDeclPtr>(v)) {
      auto fn = std::get<FnDeclPtr>(v);

      ClassicalIR ir;
      curClassical = &ir;
      curQuantum = nullptr;

      lowerFunction(*fn, ir);

      table[fn->name] = std::move(ir);
      curClassical = nullptr;
    }
  }

  return table;
}

// ------------------------------------------------------------
//  NEW: lowerFunction — lowers a single fn body
// ------------------------------------------------------------
void Lowerer::lowerFunction(const FnDecl &fn, ClassicalIR &out) {
  curClassical = &out;
  lowerBlock(fn.body);

  // Ensure a RETURN exists
  out.emit(OpCode::RETURN);
}

// ------------------------------------------------------------
//  lowerProcess — unchanged
// ------------------------------------------------------------
void Lowerer::lowerProcess(const ProcessDecl &proc, LoweredProcess & /*out*/) {
  lowerBlock(proc.body);
}

// ------------------------------------------------------------
//  lowerBlock — unchanged
// ------------------------------------------------------------
void Lowerer::lowerBlock(const BlockPtr &block) {
  for (const auto &stmt : block->statements) {
    lowerStmt(stmt);
  }
}

// ------------------------------------------------------------
//  lowerStmt — unchanged except CALL support is in lowerCall()
// ------------------------------------------------------------
void Lowerer::lowerStmt(const StmtPtr &stmt) {
  switch (stmt->kind) {
  case StmtKind::Let: {
    lowerExpr(stmt->expr);
    curClassical->emit(OpCode::STORE_VAR, stmt->name);
    break;
  }
  case StmtKind::Return: {
    lowerExpr(stmt->expr);
    curClassical->emit(OpCode::RETURN);
    break;
  }
  case StmtKind::If: {
    lowerExpr(stmt->condition);
    lowerBlock(stmt->thenBlock);
    break;
  }
  case StmtKind::Expr: {
    lowerExpr(stmt->expr);
    break;
  }
  }
}

// ------------------------------------------------------------
//  lowerExpr — unchanged except CALL now emits CALL opcode
// ------------------------------------------------------------
void Lowerer::lowerExpr(const ExprPtr &expr) {
  switch (expr->kind) {
  case ExprKind::Literal: {
    curClassical->emit(OpCode::LOAD_CONST, expr->literalValue);
    break;
  }
  case ExprKind::Identifier: {
    curClassical->emit(OpCode::LOAD_VAR, expr->identifier);
    break;
  }
  case ExprKind::Binary: {
    lowerBinary(expr);
    break;
  }
  case ExprKind::Unary: {
    lowerUnary(expr);
    break;
  }
  case ExprKind::Call: {
    lowerCall(expr);
    break;
  }
  case ExprKind::Prepare: {
    lowerPrepare(expr);
    break;
  }
  case ExprKind::Measure: {
    lowerMeasure(expr);
    break;
  }
  case ExprKind::Grouping: {
    lowerExpr(expr->inner);
    break;
  }
  }
}

// ------------------------------------------------------------
//  lowerBinary — unchanged
// ------------------------------------------------------------
void Lowerer::lowerBinary(const ExprPtr &expr) {
  lowerExpr(expr->left);

  if (expr->op == "+") {
    if (expr->right->kind == ExprKind::Literal)
      curClassical->emit(OpCode::ADD, expr->right->literalValue);
    else if (expr->right->kind == ExprKind::Identifier)
      curClassical->emit(OpCode::ADD, expr->right->identifier);
    else
      throw std::runtime_error("Unsupported RHS in binary '+' lowering");

  } else if (expr->op == "-") {
    if (expr->right->kind == ExprKind::Literal)
      curClassical->emit(OpCode::SUB, expr->right->literalValue);
    else if (expr->right->kind == ExprKind::Identifier)
      curClassical->emit(OpCode::SUB, expr->right->identifier);
    else
      throw std::runtime_error("Unsupported RHS in binary '-' lowering");

  } else if (expr->op == "*") {
    if (expr->right->kind == ExprKind::Literal)
      curClassical->emit(OpCode::MUL, expr->right->literalValue);
    else if (expr->right->kind == ExprKind::Identifier)
      curClassical->emit(OpCode::MUL, expr->right->identifier);
    else
      throw std::runtime_error("Unsupported RHS in binary '*' lowering");

  } else if (expr->op == "/") {
    if (expr->right->kind == ExprKind::Literal)
      curClassical->emit(OpCode::DIV, expr->right->literalValue);
    else if (expr->right->kind == ExprKind::Identifier)
      curClassical->emit(OpCode::DIV, expr->right->identifier);
    else
      throw std::runtime_error("Unsupported RHS in binary '/' lowering");

  } else {
    throw std::runtime_error("Unsupported binary operator in lowering: " +
                             expr->op);
  }
}

// ------------------------------------------------------------
//  lowerUnary — unchanged
// ------------------------------------------------------------
void Lowerer::lowerUnary(const ExprPtr &expr) { lowerExpr(expr->right); }

// ------------------------------------------------------------
//  NEW: lowerCall — now emits CALL opcode
// ------------------------------------------------------------
void Lowerer::lowerCall(const ExprPtr &expr) {
  // Lower arguments first
  for (const auto &arg : expr->args) {
    lowerExpr(arg);
  }

  // Emit CALL <function_name>
  curClassical->emit(OpCode::CALL, expr->identifier);
}

// ------------------------------------------------------------
//  lowerPrepare — unchanged
// ------------------------------------------------------------
void Lowerer::lowerPrepare(const ExprPtr & /*expr*/) {
  curQuantum->emit(QOpCode::ALLOC_QBIT, "q");
}

// ------------------------------------------------------------
//  lowerMeasure — unchanged
// ------------------------------------------------------------
void Lowerer::lowerMeasure(const ExprPtr &expr) {
  curQuantum->emit(QOpCode::MEASURE, expr->identifier);
}

} // namespace k