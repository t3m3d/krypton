#pragma once
#include "tokens.hpp"
#include <string>
#include <vector>

namespace k {

class Lexer {
public:
  explicit Lexer(const std::string &source);

  std::vector<Token> tokenize();

private:
  const std::string &source;
  std::size_t current = 0;
  int line = 1;
  int column = 1;

  bool isAtEnd() const;
  char advance();
  char peek() const;
  char peekNext() const;

  void addToken(std::vector<Token> &tokens, TokenType type,
                const std::string &lexeme);

  void skipWhitespace();
  void skipComment();

  void identifier(std::vector<Token> &tokens);
  void number(std::vector<Token> &tokens);
  void stringLiteral(std::vector<Token> &tokens);

  TokenType keywordOrIdentifier(const std::string &text) const;
};

} // namespace k