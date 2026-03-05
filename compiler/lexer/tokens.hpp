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
  EMIT,
  RETURN,
  MEASURE,
  PREPARE,
  TRUE_,
  FALSE_,
  WITH,
<<<<<<< HEAD
=======

>>>>>>> 55f12d0ac9096b1e646be66ac223353da7762815
  IDENTIFIER,
  INT_LITERAL,
  FLOAT_LITERAL,
  STRING_LITERAL,
  BOOL_LITERAL,
<<<<<<< HEAD
  // Operators
=======

>>>>>>> 55f12d0ac9096b1e646be66ac223353da7762815
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
<<<<<<< HEAD
  // Punctuation
=======

>>>>>>> 55f12d0ac9096b1e646be66ac223353da7762815
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