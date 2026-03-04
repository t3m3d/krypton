#include "driver.hpp"
#include "compiler/lexer/lexer.hpp"
#include "compiler/parser/parser.hpp"
#include <fstream>
#include <sstream>
#include <stdexcept>

namespace k {

ModuleDecl Driver::loadAndParse(const std::string &path) {
    std::ifstream file(path);
    if (!file) {
        throw std::runtime_error("File Invalid: " + path);
    }

    std::stringstream buffer;
    buffer << file.rdbuf();
    try {
        Lexer lex(buffer.str());
        auto tokens = lex.tokenize();
        Parser parser(tokens);
        return parser.parseProgram();
    } catch (const std::exception &e) {
        throw std::runtime_error(
            "Error compiling -drv '" + path + "': " + e.what()
        );
    }
}

} // namespace k