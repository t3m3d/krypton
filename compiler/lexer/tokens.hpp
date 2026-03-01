#pragma once
#include <string>

namespace k {

enum class TokenType {
  MODULE,
  FN,
  QUANTUM,
  QPUTE,
  PROCESS,
  LET,
  IF,
  ELSE,
  RETURN,
  MEASURE,
  PREPARE,
  TRUE_,
  FALSE_,
  WITH,

  IDENTIFIER,
  INT_LITERAL,
  FLOAT_LITERAL,
  STRING_LITERAL,
  BOOL_LITERAL,

  PLUS,
  MINUS,
  STAR,
  SLASH,
  EQEQ,
  BANGEQ,
  LT,
  GT,
  LTE,
  GTE,
  ANDAND,
  OROR,
  BANG,

  LPAREN,
  RPAREN,
  LBRACE,
  RBRACE,
  COMMA,
  COLON,
  SEMICOLON,
  ARROW,
  EQUAL,

  END_OF_FILE
};

struct Token {
  TokenType type;
  std::string lexeme;
  int line;
  int column;
};

}