#include "tokens.hpp"
#include <vector>

class Lexer {
public:
    explicit Lexer(const std::string& src) : source(src) {}

    std::vector<Token> tokenize() {
        return {}; // stub
    }

private:
    std::string source;
};