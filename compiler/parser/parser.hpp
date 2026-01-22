#pragma once
#include "ast/ast.hpp"
#include "lexer/tokens.hpp"
#include <vector>


namespace k {

class Parser {
public:
  explicit Parser(const std::vector<Token> &tokens);

  ModuleDecl parseProgram();

private:
  const std::vector<Token> &tokens;
  std::size_t current = 0;

  const Token &peek() const;
  const Token &previous() const;
  bool isAtEnd() const;
  bool match(TokenType type);
  const Token &consume(TokenType type, const char *message);

  // Declarations
  std::shared_ptr<void> parseDecl();
  FnDeclPtr parseFnDecl();
  QputeDeclPtr parseQputeDecl();
  ProcessDeclPtr parseProcessDecl();

  // Blocks & statements
  BlockPtr parseBlock();
  StmtPtr parseStmt();
  StmtPtr parseLetStmt();
  StmtPtr parseReturnStmt();
  StmtPtr parseIfStmt();
  StmtPtr parseExprStmt();

  // Expressions
  ExprPtr parseExpr();
  ExprPtr parseOrExpr();
  ExprPtr parseAndExpr();
  ExprPtr parseEqualityExpr();
  ExprPtr parseRelExpr();
  ExprPtr parseAddExpr();
  ExprPtr parseMulExpr();
  ExprPtr parseUnaryExpr();
  ExprPtr parsePrimaryExpr();

  // Helpers
  TypeNode parseType();
};

} // namespace k