#include <string>
#include <unordered_map>

class SymbolTable {
public:
    void define(const std::string& name) {
        table[name] = true;
    }

    bool exists(const std::string& name) {
        return table.contains(name);
    }

private:
    std::unordered_map<std::string, bool> table;
};