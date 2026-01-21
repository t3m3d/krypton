#include <iostream>
#include <string>

void repl() {
    std::string line;
    while (true) {
        std::cout << "k> ";
        if (!std::getline(std::cin, line)) break;
        // stub
    }
}