#include "lexer.hpp"
#include <cctype>
#include <stdexcept>
#include <iostream>

namespace k {

Lexer::Lexer(const std::string &src) : source(src) {}

bool Lexer::isAtEnd() const { return current >= source.size(); }

char Lexer::advance() {
    char c = source[current++];

    if (c == '\n' || c == '\r') {
        line++;
        column = 1;
    } else {
        column++;
    }

    return c;
}

char Lexer::peek() const {
  if (isAtEnd())
    return '\0';
  return source[current];
}

char Lexer::peekNext() const {
  if (current + 1 >= source.size())
    return '\0';
  return source[current + 1];
}

void Lexer::addToken(std::vector<Token> &tokens, TokenType type,
                     const std::string &lexeme) {

 ///  debug tokens  std::cout << "TOKEN: " << lexeme
 ///           << " (" << static_cast<int>(type) << ")\n";

  tokens.push_back(
      Token{type, lexeme, line, column - static_cast<int>(lexeme.size())});
}

void Lexer::skipWhitespace() {
  while (!isAtEnd()) {
    char c = peek();
    if (c == ' ' || c == '\r' || c == '\t' || c == '\n') {
      advance();
    } else {
      break;
    }
  }
}

void Lexer::skipComment() {
    if (peek() == '/' && peekNext() == '/') {
        while (!isAtEnd() && peek() != '\n' && peek() != '\r') {
            advance();
        }
    }
}

TokenType Lexer::keywordOrIdentifier(const std::string &text) const {
  if (text == "module")
    return TokenType::MODULE;
  if (text == "fn")
    return TokenType::FN;
  if (text == "quantum")
    return TokenType::QUANTUM;
  if (text == "qpute")
    return TokenType::QPUTE;
  if (text == "go")
    return TokenType::PROCESS;
  if (text == "let")
    return TokenType::LET;
  if (text == "return")
    return TokenType::RETURN;
  if (text == "if")
    return TokenType::IF;
  if (text == "else")
    return TokenType::ELSE;
  if (text == "measure")
    return TokenType::MEASURE;
  if (text == "prepare")
    return TokenType::PREPARE;
  if (text == "true")
    return TokenType::TRUE_;
  if (text == "false")
    return TokenType::FALSE_;
  return TokenType::IDENTIFIER;
}

void Lexer::identifier(std::vector<Token> &tokens) {
  std::size_t start = current - 1;
  while (!isAtEnd() && (std::isalnum(peek()) || peek() == '_')) {
    advance();
  }
  std::string text = source.substr(start, current - start);
  TokenType type = keywordOrIdentifier(text);
  addToken(tokens, type, text);
}

void Lexer::number(std::vector<Token> &tokens) {
  std::size_t start = current - 1;
  bool isFloat = false;

  while (!isAtEnd() && std::isdigit(peek())) {
    advance();
  }

  if (!isAtEnd() && peek() == '.' && std::isdigit(peekNext())) {
    isFloat = true;
    advance(); // consume '.'
    while (!isAtEnd() && std::isdigit(peek())) {
      advance();
    }
  }

  std::string text = source.substr(start, current - start);
  addToken(tokens, isFloat ? TokenType::FLOAT_LITERAL : TokenType::INT_LITERAL,
           text);
}

void Lexer::stringLiteral(std::vector<Token> &tokens) {
  std::size_t start = current; // after opening quote
  while (!isAtEnd() && peek() != '"') {
    advance();
  }
  if (isAtEnd()) {
    throw std::runtime_error("Unterminated string literal");
  }
  advance(); // closing quote
  std::string text = source.substr(start, current - start - 1);
  addToken(tokens, TokenType::STRING_LITERAL, text);
}

std::vector<Token> Lexer::tokenize() {
    std::vector<Token> tokens;


    while (!isAtEnd()) {
        skipWhitespace();
        skipComment();
        if (isAtEnd())
            break;

        char c = advance();

switch (c) {
    case '(':
        addToken(tokens, TokenType::LPAREN, "(");
        break;
    case ')':
        addToken(tokens, TokenType::RPAREN, ")");
        break;
    case '{':
        addToken(tokens, TokenType::LBRACE, "{");
        break;
    case '}':
        addToken(tokens, TokenType::RBRACE, "}");
        break;
    case ',':
        addToken(tokens, TokenType::COMMA, ",");
        break;
    case ':':
        addToken(tokens, TokenType::COLON, ":");
        break;

    case ';':
        addToken(tokens, TokenType::SEMICOLON, ";");
        break;

    case '=':
        if (peek() == '=') {
            advance();
            addToken(tokens, TokenType::EQEQ, "==");
        } else {
            addToken(tokens, TokenType::EQUAL, "=");
        }
        break;
    case '!':
        if (peek() == '=') {
            advance();
            addToken(tokens, TokenType::BANGEQ, "!=");
        } else {
            addToken(tokens, TokenType::BANG, "!");
        }
        break;
    case '<':
        if (peek() == '=') {
            advance();
            addToken(tokens, TokenType::LTE, "<=");
        } else {
            addToken(tokens, TokenType::LT, "<");
        }
        break;
    case '>':
        if (peek() == '=') {
            advance();
            addToken(tokens, TokenType::GTE, ">=");
        } else {
            addToken(tokens, TokenType::GT, ">");
        }
        break;
    case '+':
        addToken(tokens, TokenType::PLUS, "+");
        break;
    case '-':
        if (peek() == '>') {
            advance();
            addToken(tokens, TokenType::ARROW, "->");
        } else {
            addToken(tokens, TokenType::MINUS, "-");
        }
        break;
    case '*':
        addToken(tokens, TokenType::STAR, "*");
        break;

    case '/':
        addToken(tokens, TokenType::SLASH, "/");
        break;

    case '&':
        if (peek() == '&') {
            advance();
            addToken(tokens, TokenType::ANDAND, "&&");
        } else {
            throw std::runtime_error("Unexpected '&'");
        }
        break;
    case '|':
        if (peek() == '|') {
            advance();
            addToken(tokens, TokenType::OROR, "||");
        } else {
            throw std::runtime_error("Unexpected '|'");
        }
        break;
    case '"':
        stringLiteral(tokens);
        break;

    default:
        if (std::isalpha(c) || c == '_') {
            identifier(tokens);
        } else if (std::isdigit(c)) {
            number(tokens);
        } else {
            throw std::runtime_error(std::string("Unexpected character: ") + c);
        }
        break;
}
    }

    addToken(tokens, TokenType::END_OF_FILE, "");
    return tokens;

}
} // namespace k