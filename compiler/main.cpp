#include <fstream>
#include <iostream>
#include <sstream>

#include "lexer.hpp"
#include "parser.hpp"
#include "middle/lowering/lowerer.hpp"
#include "runtime/classical_interpreter.hpp"

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
    std::cerr << "read file\n";

    k::Lexer lexer(source);
    auto tokens = lexer.tokenize();
    std::cerr << "tokenized\n";

    k::Parser parser(tokens);
    k::ModuleDecl module;
    try {
        module = parser.parseProgram();
    } catch (const std::exception &e) {
        std::cerr << "parse error: " << e.what() << "\n";
        return 1;
    }
    std::cerr << "parsed module\n";
    std::cerr << "parsed module\n";

    // Lower to IR
    k::Lowerer lowerer;
    auto processes = lowerer.lowerModule(module);
    auto functions = lowerer.lowerFunctions(module);
    std::cerr << "lowered\n";

    // Run the "main" process
    auto it = processes.find("run");
    if (it == processes.end()) {
        std::cerr << "No go run found.\n";
        return 1;
    }
    std::cerr << "found run process\n";

    k::ClassicalInterpreter interp;
    interp.setFunctionTable(&functions);
    std::cerr << "about to run interpreter\n";
    std::cerr << "about to run interpreter\n";
    try {
        auto maybe = interp.run(it->second.classical);
        std::cerr << "run returned\n";
        std::cerr << "about to print result\n";
        if (maybe.has_value()) {
            std::cerr << "result: " << maybe->toString() << "\n";
            // use numeric value as exit code if available
            if (maybe->isNumber())
                return maybe->number;
        }
    } catch (const std::exception &e) {
        std::cerr << "runtime error: " << e.what() << "\n";
        return 1;
    }

    std::cerr << "interpreter finished normally\n";
    return 0;
}