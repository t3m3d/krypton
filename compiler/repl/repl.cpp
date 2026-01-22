#include "repl.hpp"
#include "compiler/frontend/driver.hpp"
#include "compiler/runtime/runtime.hpp"
#include <iostream>

namespace k {

void REPL::start() {
  std::cout << "Krypton REPL\n";

  Driver driver;
  Runtime runtime;

  while (true) {
    std::cout << ">>> ";
    std::string line;
    if (!std::getline(std::cin, line))
      break;

    if (line == ":quit")
      break;

    std::string temp = "module repl\n"
                       "process main { " +
                       line + " }";

    try {
      Lexer lex(temp);
      auto tokens = lex.tokenize();
      Parser parser(tokens);
      ModuleDecl mod = parser.parseProgram();

      runtime.runModule(mod);
    } catch (const std::exception &e) {
      std::cout << "Error: " << e.what() << "\n";
    }
  }
}

} // namespace k