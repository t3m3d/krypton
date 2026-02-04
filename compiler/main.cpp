#include <fstream>
#include <iostream>
#include <sstream>

#include "lexer.hpp"
#include "parser.hpp"
#include "lowerer.hpp"
#include "classical_interpreter.hpp"

std::string readFile(const std::string &path) {
    std::ifstream file(path);
    if (!file.is_open()) {
        throw std::runtime_error("Could not open file: " + path);
    }
    std::stringstream buffer;
    buffer << file.rdbuf();
    return buffer.str();
}

int main(int argc, char **argv) {
    if (argc < 2) {
        std::cout << "Usage: kcc <file.k>\n";
        return 1;
    }

    std::string path = argv[1];
    std::string source = readFile(path);

    k::Lexer lexer(source);
    auto tokens = lexer.tokenize();

    k::Parser parser(tokens);
    k::ModuleDecl module = parser.parseProgram();

    // Lower to IR
    k::Lowerer lowerer;
    auto processes = lowerer.lowerModule(module);
    auto functions = lowerer.lowerFunctions(module);

    // Run the "main" process
    auto it = processes.find("main");
    if (it == processes.end()) {
        std::cerr << "No main process found.\n";
        return 1;
    }

    k::ClassicalInterpreter interp;
    interp.setFunctionTable(&functions);
    interp.run(it->second.classical);

    return 0;
}