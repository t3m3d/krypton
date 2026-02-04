#pragma once
#include "compiler/ast/ast.hpp"
#include "compiler/lexer/tokens.hpp"
#include <variant>
#include <vector>

namespace k {

class Parser {
public:
  explicit Parser(const std::vector<Token> &tokens);

  // Matches: ModuleDecl Parser::parseProgram()
  ModuleDecl parseProgram();

private:
  const std::vector<Token> &tokens;
  std::size_t current = 0;

  // Core helpers
  const Token &peek() const;
  const Token &previous() const;
  bool isAtEnd() const;
  bool match(TokenType type);
  const Token &consume(TokenType type, const char *message);

  // Declarations
  std::variant<FnDeclPtr, QputeDeclPtr, ProcessDeclPtr> parseDecl();
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

  // Types
  TypeNode parseType();
};

}