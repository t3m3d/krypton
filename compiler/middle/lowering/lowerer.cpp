#include "lowerer.hpp"
#include <stdexcept>

namespace k {

std::unordered_map<std::string, LoweredProcess>
Lowerer::lowerModule(const ModuleDecl &module) {
  std::unordered_map<std::string, LoweredProcess> result;

  for (const auto &v : module.decls) {
    // We only lower processes here; functions/qputes can be added later.
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

void Lowerer::lowerProcess(const ProcessDecl &proc, LoweredProcess & /*out*/) {
  lowerBlock(proc.body);
}

void Lowerer::lowerBlock(const BlockPtr &block) {
  for (const auto &stmt : block->statements) {
    lowerStmt(stmt);
  }
}

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
    // Minimal lowering: evaluate condition, ignore branching for now
    lowerExpr(stmt->condition);
    // Future: emit JUMP_IF_FALSE + labels
    lowerBlock(stmt->thenBlock);
    break;
  }
  case StmtKind::Expr: {
    lowerExpr(stmt->expr);
    break;
  }
  }
}

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

void Lowerer::lowerBinary(const ExprPtr &expr) {
  // Simple accumulator model:
  // left -> _tmp, then apply op with right as arg
  lowerExpr(expr->left);

  if (expr->op == "+") {
    // ADD right
    if (expr->right->kind == ExprKind::Literal) {
      curClassical->emit(OpCode::ADD, expr->right->literalValue);
    } else if (expr->right->kind == ExprKind::Identifier) {
      curClassical->emit(OpCode::ADD, expr->right->identifier);
    } else {
      throw std::runtime_error("Unsupported RHS in binary '+' lowering");
    }
  } else if (expr->op == "-") {
    if (expr->right->kind == ExprKind::Literal) {
      curClassical->emit(OpCode::SUB, expr->right->literalValue);
    } else if (expr->right->kind == ExprKind::Identifier) {
      curClassical->emit(OpCode::SUB, expr->right->identifier);
    } else {
      throw std::runtime_error("Unsupported RHS in binary '-' lowering");
    }
  } else if (expr->op == "*") {
    if (expr->right->kind == ExprKind::Literal) {
      curClassical->emit(OpCode::MUL, expr->right->literalValue);
    } else if (expr->right->kind == ExprKind::Identifier) {
      curClassical->emit(OpCode::MUL, expr->right->identifier);
    } else {
      throw std::runtime_error("Unsupported RHS in binary '*' lowering");
    }
  } else if (expr->op == "/") {
    if (expr->right->kind == ExprKind::Literal) {
      curClassical->emit(OpCode::DIV, expr->right->literalValue);
    } else if (expr->right->kind == ExprKind::Identifier) {
      curClassical->emit(OpCode::DIV, expr->right->identifier);
    } else {
      throw std::runtime_error("Unsupported RHS in binary '/' lowering");
    }
  } else {
    // For now, other operators are not lowered to IR
    throw std::runtime_error("Unsupported binary operator in lowering: " +
                             expr->op);
  }
}

void Lowerer::lowerUnary(const ExprPtr &expr) {
  // Minimal: just lower inner and rely on runtime to interpret sign/negation
  // later
  lowerExpr(expr->right);
  // Could emit dedicated unary ops if you extend ClassicalIR
}

void Lowerer::lowerCall(const ExprPtr &expr) {
  // For now, just lower arguments; no CALL opcode semantics yet.
  for (const auto &arg : expr->args) {
    lowerExpr(arg);
  }
  // Future: emit OpCode::CALL with expr->identifier as target
}

void Lowerer::lowerPrepare(const ExprPtr & /*expr*/) {
  // Allocate a new qbit with a synthetic name or managed externally.
  // For now, just emit a placeholder.
  curQuantum->emit(QOpCode::ALLOC_QBIT, "q");
}

void Lowerer::lowerMeasure(const ExprPtr &expr) {
  curQuantum->emit(QOpCode::MEASURE, expr->identifier);
}

} // namespace k