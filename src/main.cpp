#include "compiler/lexer/lexer.hpp"
#include "compiler/parser/parser.hpp"
#include <fstream>
#include <iostream>
#include <sstream>


int main(int argc, char **argv) {
  if (argc < 2) {
    std::cerr << "Usage: kcc <file.k>\n";
    return 1;
  }

  std::ifstream in(argv[1]);
  if (!in) {
    std::cerr << "Could not open file: " << argv[1] << "\n";
    return 1;
  }

  std::stringstream buffer;
  buffer << in.rdbuf();
  std::string source = buffer.str();

  try {
    k::Lexer lexer(source);
    auto tokens = lexer.tokenize();

    k::Parser parser(tokens);
    k::ModuleDecl module = parser.parseProgram();

    std::cout << "Parsed module: " << module.name << "\n";
  } catch (const std::exception &ex) {
    std::cerr << "Error: " << ex.what() << "\n";
    return 1;
  }

  return 0;
}