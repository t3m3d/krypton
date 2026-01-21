#include "ast.hpp"
#include "../lexer/tokens.hpp"
#include <vector>

class Parser {
public:
    explicit Parser(const std::vector<Token>& t) : tokens(t) {}

    std::unique_ptr<Expr> parse() {
        return nullptr; // stub
    }

private:
    std::vector<Token> tokens;
};