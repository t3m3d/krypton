#pragma once
#include "ast/ast.hpp"
#include <string>
#include <unordered_map>
#include <vector>


namespace k {

struct TypeEnv {
  std::unordered_map<std::string, TypeNode> vars;

  void define(const std::string &name, const TypeNode &t) { vars[name] = t; }

  bool lookup(const std::string &name, TypeNode &out) const {
    auto it = vars.find(name);
    if (it == vars.end())
      return false;
    out = it->second;
    return true;
  }
};

class TypeChecker {
public:
  void checkModule(const ModuleDecl &module);

private:
  // Environments
  TypeEnv env;

  // Decls
  void checkFn(const FnDecl &fn);
  void checkQpute(const QputeDecl &qp);
  void checkProcess(const ProcessDecl &proc);

  // Blocks & statements
  void checkBlock(const BlockPtr &block);
  void checkStmt(const StmtPtr &stmt);

  // Expressions
  TypeNode checkExpr(const ExprPtr &expr);

  // Helpers
  TypeNode boolType() const;
  TypeNode intType() const;
  TypeNode floatType() const;
  TypeNode stringType() const;
  TypeNode qbitType() const;

  bool isBool(const TypeNode &t) const;
  bool isInt(const TypeNode &t) const;
  bool isFloat(const TypeNode &t) const;
  bool isNumeric(const TypeNode &t) const;
  bool isQbit(const TypeNode &t) const;

  void ensureQuantumContext(const ExprPtr &expr);
};

} // namespace k