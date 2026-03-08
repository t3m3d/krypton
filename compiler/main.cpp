
#include <fstream>
#include <iostream>
#include <sstream>

#include "lexer.hpp"
#include "parser.hpp"
#include "middle/lowering/lowerer.hpp"
#include "value.hpp"
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

	std::string path;
	if (argc < 2) {
		std::cout << "Usage: kcc <file.k>\n";
		std::cout << "Defaulting to run.k\n";
		path = "run.k";
	} else {
		path = argv[1];
	}
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

	k::Lexer lexer(source);
	std::vector<k::Token> tokens;
	try {
		tokens = lexer.tokenize();
	} catch (const std::exception &e) {
		std::cerr << "Lexer error: " << e.what() << "\n";
		return 1;
	}
	std::cerr << "tokenized\n";

	k::Parser parser(tokens);
	k::ModuleDecl module;
	try {
		module = parser.parseProgram();
	} catch (const std::exception &e) {
		std::cerr << "Parse error: " << e.what() << "\n";
		return 1;
	}
	std::cerr << "parsed module\n";

	k::Lowerer lowerer;
	auto processes = lowerer.lowerModule(module);
	auto functions = lowerer.lowerFunctions(module);
	std::cerr << "lowered\n";

	auto it = processes.find("run");
	if (it == processes.end()) {
		std::cerr << "No run process found.\n";
		return 1;
	}
	std::cerr << "found run process\n";

	k::ClassicalInterpreter interp;
	interp.setFunctionTable(&functions);
	std::vector<std::string> extraArgs;
	for (int i = 2; i < argc; i++) {
		extraArgs.push_back(argv[i]);
	}
	interp.setArgs(extraArgs);
	std::cerr << "about to run interpreter\n";
	try {
		auto maybe = interp.run(it->second.classical);
		std::cerr << "run returned\n";
		if (maybe.has_value()) {
			std::cerr << "result: " << maybe->toString() << "\n";
			if (maybe->isNumber())
				return maybe->number;
		}
	} catch (const std::exception &e) {
		std::cerr << "Runtime error: " << e.what() << "\n";
		return 1;
	}

	std::cerr << "interpreter finished normally\n";
	return 0;
}