#pragma once
#include <string>

enum class TokenType {
    Identifier,
    Number,
    String,
    Let,
    Fn,
    LParen, RParen,
    LBrace, RBrace,
    Equals,
    Comma,
    EndOfFile,
    Unknown
};

struct Token {
    TokenType type;
    std::string lexeme;
    int line;
};