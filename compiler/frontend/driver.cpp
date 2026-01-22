#include "driver.hpp"
#include "compiler/lexer/lexer.hpp"
#include "compiler/parser/parser.hpp"
#include <fstream>
#include <sstream>

namespace k {

ModuleDecl Driver::loadAndParse(const std::string &path) {
  std::ifstream file(path);
  if (!file) {
    throw std::runtime_error("Cannot open file: " + path);
  }

  std::stringstream buffer;
  buffer << file.rdbuf();

  Lexer lex(buffer.str());
  auto tokens = lex.tokenize();

  Parser parser(tokens);
  return parser.parseProgram();
}

} // namespace k