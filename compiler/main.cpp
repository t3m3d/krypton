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
    std::cout << "MAIN START\n";

    if (argc < 2) {
        std::cout << "Usage: kcc <file.k>\n";
        return 1;
    }

    std::string path = argv[1];
<<<<<<< HEAD
    std::string source = readFile(path);
    std::cerr << "read file\n";
=======

    if (path == "--help" || path == "-h") {
        std::cout << "Krypton Compiler (kcc)\n";
        std::cout << "Usage: kcc <file.k>\n";
        return 0;
    }

    std::string source;
    try {
        source = readFile(path);
    } catch (const std::exception &e) {
        std::cerr << e.what() << "\n";
        return 1;
    }
>>>>>>> 55f12d0ac9096b1e646be66ac223353da7762815

    k::Lexer lexer(source);
    auto tokens = lexer.tokenize();
    std::cerr << "tokenized\n";

    k::Parser parser(tokens);
    k::ModuleDecl module;
    try {
        module = parser.parseProgram();
    } catch (const std::exception &e) {
<<<<<<< HEAD
        std::cerr << "parse error: " << e.what() << "\n";
        return 1;
    }
    std::cerr << "parsed module\n";
    std::cerr << "parsed module\n";
=======
        std::cerr << "Parse error: " << e.what() << "\n";
        return 1;
    }
>>>>>>> 55f12d0ac9096b1e646be66ac223353da7762815

    k::Lowerer lowerer;
    auto processes = lowerer.lowerModule(module);
    auto functions = lowerer.lowerFunctions(module);
    std::cerr << "lowered\n";

    auto it = processes.find("run");
    if (it == processes.end()) {
        std::cerr << "No go run found.\n";
        return 1;
    }
    std::cerr << "found run process\n";

    k::ClassicalInterpreter interp;
    interp.setFunctionTable(&functions);
<<<<<<< HEAD
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
=======

    try {
        interp.run(it->second.classical);
    } catch (const std::exception &e) {
        std::cerr << "Runtime error: " << e.what() << "\n";
>>>>>>> 55f12d0ac9096b1e646be66ac223353da7762815
        return 1;
    }

    std::cerr << "interpreter finished normally\n";
    return 0;
}