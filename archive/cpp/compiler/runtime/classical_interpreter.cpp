#include "classical_interpreter.hpp"
#include <cctype>
#include <cstring>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <vector>

namespace k {

// ── Linked-list environment for O(1) envSet, O(depth) envGet ──
struct EnvNode {
    int parent;          // index of parent node, -1 for root
    std::string name;
    std::string value;
};
static std::vector<EnvNode> g_envNodes;

static inline bool isEnvHandle(const std::string &s) {
    return s.size() > 4 && s[0] == 'E' && s[1] == 'N' && s[2] == 'V' && s[3] == ':';
}

static inline int parseEnvHandle(const std::string &s) {
    // "ENV:123" -> 123
    int n = 0;
    for (size_t i = 4; i < s.size(); i++) {
        n = n * 10 + (s[i] - '0');
    }
    return n;
}

static bool isNumber(const std::string &s) {
    if (s.empty()) return false;
    size_t start = 0;
    if (s[0] == '-' && s.size() > 1) start = 1;
    for (size_t i = start; i < s.size(); i++) {
        if (!std::isdigit(s[i])) return false;
    }
    return true;
}

void ClassicalInterpreter::setFunctionTable(const FunctionIRTable *table) {
    functions = table;
}

Value ClassicalInterpreter::getValue(const Frame &frame, const std::string &arg) {
    if (!arg.empty() && (std::isdigit(arg[0]) || (arg[0] == '-' && arg.size() > 1))) {
        return Value(std::stoi(arg));
    }
    auto it = frame.vars.find(arg);
    if (it != frame.vars.end())
        return it->second;
    throw std::runtime_error("Unknown variable: " + arg);
}

std::optional<Value> ClassicalInterpreter::run(const ClassicalIR &entry) {
    if (!functions) {
        throw std::runtime_error("Function table not set in ClassicalInterpreter");
    }

    stack.clear();
    valueStack.clear();
    stack.push_back(Frame{&entry, 0, {}});

    std::optional<Value> retVal;

    while (!stack.empty()) {
        Frame &frame = stack.back();
        const auto &ir = *frame.ir;

        if (frame.ip >= (int)ir.instructions.size()) {
            stack.pop_back();
            continue;
        }

        const Instruction &inst = ir.instructions[frame.ip];

        switch (inst.op) {

        case OpCode::LOAD_CONST: {
            if (isNumber(inst.arg)) {
                push(Value(std::stoi(inst.arg)));
            } else {
                push(Value(inst.arg));
            }
            break;
        }

        case OpCode::LOAD_VAR: {
            push(getValue(frame, inst.arg));
            break;
        }

        case OpCode::STORE_VAR: {
            frame.vars[inst.arg] = pop();
            break;
        }

        case OpCode::ADD: {
            Value b = pop();
            Value a = pop();
            if (a.isNumber() && b.isNumber()) {
                push(Value(a.number + b.number));
            } else {
                // Move a's string buffer if it's already a string (avoids copy)
                std::string result = a.isNumber() ? a.toString() : std::move(a.str);
                result += b.toString();
                push(Value(std::move(result)));
            }
            break;
        }

        case OpCode::SUB: {
            Value b = pop();
            Value a = pop();
            push(Value(a.number - b.number));
            break;
        }

        case OpCode::MUL: {
            Value b = pop();
            Value a = pop();
            push(Value(a.number * b.number));
            break;
        }

        case OpCode::DIV: {
            Value b = pop();
            Value a = pop();
            if (b.number == 0) throw std::runtime_error("Division by zero");
            push(Value(a.number / b.number));
            break;
        }

        case OpCode::PRINT: {
            if (!inst.arg.empty()) {
                std::cout << inst.arg << std::endl;
            } else {
                Value v = pop();
                std::cout << v.toString() << std::endl;
            }
            break;
        }

        case OpCode::CALL: {
            auto fit = functions->find(inst.arg);
            if (fit == functions->end()) {
                throw std::runtime_error("Unknown function: " + inst.arg);
            }
            std::unordered_map<std::string, Value> calleeVars;
            for (auto it_param = fit->second.params.rbegin();
                 it_param != fit->second.params.rend(); ++it_param) {
                if (valueStack.empty()) {
                    throw std::runtime_error("Not enough arguments for function: " + inst.arg);
                }
                calleeVars[*it_param] = pop();
            }
            // Increment caller IP BEFORE push_back (push may invalidate frame ref)
            frame.ip++;
            stack.push_back(Frame{&fit->second, 0, std::move(calleeVars)});
            continue;
        }

        case OpCode::RETURN: {
            if (!valueStack.empty()) {
                retVal = valueStack.back();
            }
            stack.pop_back();
            continue;
        }

        case OpCode::LEN: {
            Value v = pop();
            int n = static_cast<int>(v.toString().size());
            push(Value(n));
            break;
        }

        case OpCode::SUBSTRING: {
            Value endV = pop();
            Value startV = pop();
            Value strV = pop();
            std::string s = strV.toString();
            int start = startV.number;
            int end = endV.number;
            if (start < 0) start = 0;
            if (end > (int)s.size()) end = (int)s.size();
            if (start > end) start = end;
            push(Value(s.substr(start, end - start)));
            break;
        }

        // ---- Control flow ----

        case OpCode::JUMP: {
            frame.ip = std::stoi(inst.arg);
            continue;
        }

        case OpCode::JUMP_IF_FALSE: {
            Value cond = pop();
            if (!cond.isTruthy()) {
                frame.ip = std::stoi(inst.arg);
                continue;
            }
            break;
        }

        // ---- Comparisons ----

        case OpCode::CMP_EQ: {
            Value b = pop();
            Value a = pop();
            if (a.isNumber() && b.isNumber())
                push(Value(a.number == b.number ? 1 : 0));
            else
                push(Value(a.toString() == b.toString() ? 1 : 0));
            break;
        }

        case OpCode::CMP_NEQ: {
            Value b = pop();
            Value a = pop();
            if (a.isNumber() && b.isNumber())
                push(Value(a.number != b.number ? 1 : 0));
            else
                push(Value(a.toString() != b.toString() ? 1 : 0));
            break;
        }

        case OpCode::CMP_LT: {
            Value b = pop();
            Value a = pop();
            if (a.isNumber() && b.isNumber())
                push(Value(a.number < b.number ? 1 : 0));
            else
                push(Value(a.toString() < b.toString() ? 1 : 0));
            break;
        }

        case OpCode::CMP_GT: {
            Value b = pop();
            Value a = pop();
            if (a.isNumber() && b.isNumber())
                push(Value(a.number > b.number ? 1 : 0));
            else
                push(Value(a.toString() > b.toString() ? 1 : 0));
            break;
        }

        case OpCode::CMP_LTE: {
            Value b = pop();
            Value a = pop();
            if (a.isNumber() && b.isNumber())
                push(Value(a.number <= b.number ? 1 : 0));
            else
                push(Value(a.toString() <= b.toString() ? 1 : 0));
            break;
        }

        case OpCode::CMP_GTE: {
            Value b = pop();
            Value a = pop();
            if (a.isNumber() && b.isNumber())
                push(Value(a.number >= b.number ? 1 : 0));
            else
                push(Value(a.toString() >= b.toString() ? 1 : 0));
            break;
        }

        // ---- Logical ----

        case OpCode::LOGIC_AND: {
            Value b = pop();
            Value a = pop();
            push(Value((a.isTruthy() && b.isTruthy()) ? 1 : 0));
            break;
        }

        case OpCode::LOGIC_OR: {
            Value b = pop();
            Value a = pop();
            push(Value((a.isTruthy() || b.isTruthy()) ? 1 : 0));
            break;
        }

        case OpCode::LOGIC_NOT: {
            Value a = pop();
            push(Value(a.isTruthy() ? 0 : 1));
            break;
        }

        // ---- String/collection ops ----

        case OpCode::INDEX: {
            Value idx = pop();
            Value obj = pop();
            std::string s = obj.toString();
            int i = idx.number;
            if (i < 0 || i >= (int)s.size()) {
                push(Value(""));
            } else {
                push(Value(std::string(1, s[i])));
            }
            break;
        }

        case OpCode::SPLIT: {
            // split(str, idx) - split comma-delimited string, return idx-th part
            Value idxV = pop();
            Value strV = pop();
            std::string s = strV.toString();
            int idx = idxV.number;
            std::vector<std::string> parts;
            std::string part;
            for (char c : s) {
                if (c == ',') {
                    parts.push_back(part);
                    part.clear();
                } else {
                    part += c;
                }
            }
            parts.push_back(part);
            if (idx >= 0 && idx < (int)parts.size()) {
                push(Value(parts[idx]));
            } else {
                push(Value(""));
            }
            break;
        }

        case OpCode::TO_INT: {
            Value v = pop();
            std::string s = v.toString();
            try {
                push(Value(std::stoi(s)));
            } catch (...) {
                push(Value(0));
            }
            break;
        }

        case OpCode::STARTS_WITH: {
            Value prefix = pop();
            Value str = pop();
            std::string s = str.toString();
            std::string p = prefix.toString();
            bool result = s.size() >= p.size() && s.compare(0, p.size(), p) == 0;
            push(Value(result ? 1 : 0));
            break;
        }

        case OpCode::COUNT: {
            // count newline-delimited entries
            Value v = pop();
            std::string s = v.toString();
            if (s.empty()) {
                push(Value(0));
            } else {
                int cnt = 1;
                for (char c : s) {
                    if (c == '\n') cnt++;
                }
                // Remove trailing empty entry
                if (!s.empty() && s.back() == '\n') cnt--;
                push(Value(cnt));
            }
            break;
        }

        case OpCode::EXTRACT: {
            // extract(sexp, offset) - extract balanced s-expression starting at offset
            Value offV = pop();
            Value strV = pop();
            std::string s = strV.toString();
            int off = offV.number;
            if (off >= (int)s.size()) {
                push(Value(""));
                break;
            }
            // If starts with '(', find matching ')'
            if (s[off] == '(') {
                int depth = 0;
                int end = off;
                for (int i = off; i < (int)s.size(); i++) {
                    if (s[i] == '(') depth++;
                    if (s[i] == ')') depth--;
                    if (depth == 0) { end = i + 1; break; }
                }
                push(Value(s.substr(off, end - off)));
            } else {
                // Read until space or end or ')'
                int end = off;
                while (end < (int)s.size() && s[end] != ' ' && s[end] != ')') end++;
                push(Value(s.substr(off, end - off)));
            }
            break;
        }

        case OpCode::FIND_SECOND: {
            // findSecond(sexp) - find start of second sub-expression in s-expr
            // e.g. "(add (num 1) (num 2))" -> find start of "(num 2)"
            Value strV = pop();
            std::string s = strV.toString();
            // Skip the opening tag like "(add "
            int i = 1; // skip '('
            while (i < (int)s.size() && s[i] != ' ') i++; // skip op name
            i++; // skip space
            // Now skip the first sub-expression
            if (i < (int)s.size() && s[i] == '(') {
                int depth = 0;
                for (; i < (int)s.size(); i++) {
                    if (s[i] == '(') depth++;
                    if (s[i] == ')') depth--;
                    if (depth == 0) { i++; break; }
                }
            } else {
                while (i < (int)s.size() && s[i] != ' ' && s[i] != ')') i++;
            }
            // Skip space
            if (i < (int)s.size() && s[i] == ' ') i++;
            push(Value(i));
            break;
        }

        case OpCode::READ_FILE: {
            Value pathV = pop();
            std::string path = pathV.toString();
            std::ifstream file(path);
            if (!file.is_open())
                throw std::runtime_error("Cannot open file: " + path);
            std::string content((std::istreambuf_iterator<char>(file)),
                                 std::istreambuf_iterator<char>());
            push(Value(content));
            break;
        }

        case OpCode::ARG: {
            Value idxV = pop();
            int idx = idxV.number;
            if (idx < 0 || idx >= (int)programArgs.size())
                throw std::runtime_error("Argument index out of range: " + std::to_string(idx));
            push(Value(programArgs[idx]));
            break;
        }

        case OpCode::ARG_COUNT: {
            push(Value((int)programArgs.size()));
            break;
        }

        case OpCode::GET_LINE: {
            Value idxV = pop();
            Value strV = pop();
            const std::string &s = strV.str;
            int target = idxV.number;
            int line = 0;
            size_t start = 0;
            for (size_t i = 0; i <= s.size(); i++) {
                if (i == s.size() || s[i] == '\n') {
                    if (line == target) {
                        push(Value(s.substr(start, i - start)));
                        goto getline_done;
                    }
                    line++;
                    start = i + 1;
                }
            }
            push(Value(""));
            getline_done:
            break;
        }

        case OpCode::LINE_COUNT: {
            Value v = pop();
            const std::string &s = v.str;
            if (s.empty()) {
                push(Value(0));
            } else {
                int cnt = 1;
                for (char c : s) {
                    if (c == '\n') cnt++;
                }
                if (s.back() == '\n') cnt--;
                push(Value(cnt));
            }
            break;
        }

        case OpCode::ENV_GET: {
            // envGet(env, name) - O(depth) lookup via linked-list nodes
            Value nameV = pop();
            Value envV = pop();
            std::string env = envV.toString();
            std::string name = nameV.toString();
            std::string result;
            if (isEnvHandle(env)) {
                int idx = parseEnvHandle(env);
                while (idx >= 0) {
                    const auto &node = g_envNodes[idx];
                    if (node.name == name) {
                        result = node.value;
                        break;
                    }
                    idx = node.parent;
                }
            }
            // empty env "" → result stays ""
            push(Value(result));
            break;
        }

        case OpCode::ENV_SET: {
            // envSet(env, name, val) - O(1) append to linked-list
            Value valV = pop();
            Value nameV = pop();
            Value envV = pop();
            int parent = -1;
            std::string envStr = envV.toString();
            if (isEnvHandle(envStr)) {
                parent = parseEnvHandle(envStr);
            }
            int idx = (int)g_envNodes.size();
            g_envNodes.push_back({parent, nameV.toString(), valV.toString()});
            std::string handle = "ENV:" + std::to_string(idx);
            push(Value(std::move(handle)));
            break;
        }

        case OpCode::FIND_LAST_COMMA: {
            Value v = pop();
            const std::string &s = v.str;
            int pos = -1;
            for (int i = (int)s.size() - 1; i >= 0; i--) {
                if (s[i] == ',') { pos = i; break; }
            }
            push(Value(pos));
            break;
        }

        case OpCode::PAIR_VAL: {
            // extract value before last comma
            Value v = pop();
            const std::string &s = v.str;
            int pos = -1;
            for (int i = (int)s.size() - 1; i >= 0; i--) {
                if (s[i] == ',') { pos = i; break; }
            }
            if (pos < 0) push(v);
            else push(Value(s.substr(0, pos)));
            break;
        }

        case OpCode::PAIR_POS: {
            // extract int after last comma
            Value v = pop();
            const std::string &s = v.str;
            int pos = -1;
            for (int i = (int)s.size() - 1; i >= 0; i--) {
                if (s[i] == ',') { pos = i; break; }
            }
            if (pos < 0) push(Value(0));
            else {
                try { push(Value(std::stoi(s.substr(pos + 1)))); }
                catch (...) { push(Value(0)); }
            }
            break;
        }

        case OpCode::TOK_TYPE: {
            // part before first ':'
            Value v = pop();
            const std::string &s = v.str;
            size_t cp = s.find(':');
            if (cp == std::string::npos) push(v);
            else push(Value(s.substr(0, cp)));
            break;
        }

        case OpCode::TOK_VAL: {
            // part after first ':'
            Value v = pop();
            const std::string &s = v.str;
            size_t cp = s.find(':');
            if (cp == std::string::npos) push(Value(""));
            else push(Value(s.substr(cp + 1)));
            break;
        }

        case OpCode::TOK_AT: {
            // tokAt(tokens, idx) - get line at index with cached offsets
            Value idxV = pop();
            Value tokV = pop();
            const std::string &s = tokV.str;
            int target = idxV.number;
            // Multi-slot cache keyed by string size
            static std::vector<std::pair<size_t, std::vector<size_t>>> tokAtCache;
            std::vector<size_t> *offsets = nullptr;
            for (auto &entry : tokAtCache) {
                if (entry.first == s.size()) { offsets = &entry.second; break; }
            }
            if (!offsets) {
                tokAtCache.push_back({s.size(), {}});
                offsets = &tokAtCache.back().second;
                offsets->push_back(0);
                for (size_t i = 0; i < s.size(); i++) {
                    if (s[i] == '\n') offsets->push_back(i + 1);
                }
            }
            if (target >= 0 && target < (int)offsets->size()) {
                size_t start = (*offsets)[target];
                size_t end = (target + 1 < (int)offsets->size())
                    ? (*offsets)[target + 1] - 1
                    : s.size();
                push(Value(s.substr(start, end - start)));
            } else {
                push(Value(""));
            }
            break;
        }

        case OpCode::TOKENIZE: {
            // Native tokenize(text) - replicates the Krypton tokenize function
            Value srcV = pop();
            const std::string &text = srcV.str;
            std::string out;
            out.reserve(text.size()); // rough estimate
            size_t i = 0;
            size_t tlen = text.size();

            auto isDigitC = [](char c) { return c >= '0' && c <= '9'; };
            auto isAlphaC = [](char c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'; };
            auto isAlphaNumC = [&](char c) { return isAlphaC(c) || isDigitC(c); };
            auto isKW = [](const std::string &w) {
                return w=="just"||w=="go"||w=="func"||w=="fn"||w=="let"||
                       w=="emit"||w=="return"||w=="if"||w=="else"||w=="while"||
                       w=="break"||w=="module"||w=="quantum"||w=="qpute"||
                       w=="process"||w=="true"||w=="false"||w=="measure"||w=="prepare";
            };

            while (i < tlen) {
                // skip whitespace
                while (i < tlen && (text[i]==' '||text[i]=='\n'||text[i]=='\t'||text[i]=='\r')) i++;
                if (i >= tlen) break;

                char c = text[i];
                // comments
                if (c == '/' && i+1 < tlen && text[i+1] == '/') {
                    while (i < tlen && text[i] != '\n') i++;
                    continue;
                }
                if (c == '/' && i+1 < tlen && text[i+1] == '*') {
                    i += 2;
                    while (i+1 < tlen && !(text[i]=='*' && text[i+1]=='/')) i++;
                    i += 2;
                    continue;
                }
                // number
                if (isDigitC(c)) {
                    out += "INT:";
                    while (i < tlen && isDigitC(text[i])) out += text[i++];
                    out += '\n';
                }
                // string
                else if (c == '"') {
                    out += "STR:";
                    i++; // skip opening quote
                    while (i < tlen && text[i] != '"') {
                        if (text[i] == '\\' && i+1 < tlen) {
                            // keep escape sequences raw
                            out += text[i]; out += text[i+1];
                            i += 2;
                        } else {
                            out += text[i++];
                        }
                    }
                    i++; // skip closing quote
                    out += '\n';
                }
                // ident/keyword
                else if (isAlphaC(c)) {
                    std::string id;
                    while (i < tlen && isAlphaNumC(text[i])) id += text[i++];
                    if (isKW(id)) { out += "KW:"; out += id; }
                    else { out += "ID:"; out += id; }
                    out += '\n';
                }
                // operators
                else if (c == '+') { out += "PLUS\n"; i++; }
                else if (c == '-') {
                    if (i+1<tlen && text[i+1]=='>') { out += "ARROW\n"; i+=2; }
                    else { out += "MINUS\n"; i++; }
                }
                else if (c == '*') { out += "STAR\n"; i++; }
                else if (c == '/') { out += "SLASH\n"; i++; }
                else if (c == '(') { out += "LPAREN\n"; i++; }
                else if (c == ')') { out += "RPAREN\n"; i++; }
                else if (c == '{') { out += "LBRACE\n"; i++; }
                else if (c == '}') { out += "RBRACE\n"; i++; }
                else if (c == '[') { out += "LBRACK\n"; i++; }
                else if (c == ']') { out += "RBRACK\n"; i++; }
                else if (c == ':') { out += "COLON\n"; i++; }
                else if (c == ';') { out += "SEMI\n"; i++; }
                else if (c == ',') { out += "COMMA\n"; i++; }
                else if (c == '=') {
                    if (i+1<tlen && text[i+1]=='=') { out += "EQ\n"; i+=2; }
                    else { out += "ASSIGN\n"; i++; }
                }
                else if (c == '!') {
                    if (i+1<tlen && text[i+1]=='=') { out += "NEQ\n"; i+=2; }
                    else { out += "BANG\n"; i++; }
                }
                else if (c == '<') {
                    if (i+1<tlen && text[i+1]=='=') { out += "LTE\n"; i+=2; }
                    else { out += "LT\n"; i++; }
                }
                else if (c == '>') {
                    if (i+1<tlen && text[i+1]=='=') { out += "GTE\n"; i+=2; }
                    else { out += "GT\n"; i++; }
                }
                else if (c == '&') {
                    if (i+1<tlen && text[i+1]=='&') { out += "AND\n"; i+=2; }
                    else i++;
                }
                else if (c == '|') {
                    if (i+1<tlen && text[i+1]=='|') { out += "OR\n"; i+=2; }
                    else i++;
                }
                else { i++; }
            }
            // Remove trailing newline if present
            if (!out.empty() && out.back() == '\n') out.pop_back();
            push(Value(std::move(out)));
            break;
        }

        case OpCode::SCAN_FUNCS: {
            // scanFunctions(tokens, ntoks) - native function table builder
            Value ntoksV = pop();
            Value toksV = pop();
            const std::string &toks = toksV.str;
            int ntoks = ntoksV.isNum ? ntoksV.number : std::stoi(ntoksV.str);

            // Build line offsets for fast access
            std::vector<size_t> offs;
            offs.reserve(ntoks + 1);
            offs.push_back(0);
            for (size_t j = 0; j < toks.size(); j++) {
                if (toks[j] == '\n') offs.push_back(j + 1);
            }

            auto getLine = [&](int idx) -> std::string {
                if (idx < 0 || idx >= (int)offs.size()) return "";
                size_t start = offs[idx];
                size_t end = (idx + 1 < (int)offs.size()) ? offs[idx+1] - 1 : toks.size();
                return toks.substr(start, end - start);
            };
            auto tokType = [](const std::string &tok) -> std::string {
                auto cp = tok.find(':');
                return (cp != std::string::npos) ? tok.substr(0, cp) : tok;
            };
            auto tokVal = [](const std::string &tok) -> std::string {
                auto cp = tok.find(':');
                return (cp != std::string::npos) ? tok.substr(cp + 1) : "";
            };

            std::string table;
            int i = 0;
            while (i < ntoks) {
                std::string tok = getLine(i);
                if (tok == "KW:func" || tok == "KW:fn") {
                    std::string nameTok = getLine(i + 1);
                    std::string fname = tokVal(nameTok);
                    int pi = i + 3;
                    std::string params;
                    int pc = 0;
                    while (getLine(pi) != "RPAREN") {
                        std::string ptok = getLine(pi);
                        if (tokType(ptok) == "ID") {
                            if (pc > 0) params += ',';
                            params += tokVal(ptok);
                            pc++;
                        }
                        pi++;
                    }
                    // skip past RPAREN, find LBRACE
                    pi++;
                    while (getLine(pi) != "LBRACE") pi++;
                    table += fname + '~' + std::to_string(pc) + '~' + params + '~' + std::to_string(pi) + '\n';
                    // skip past function body
                    i = pi;
                    int depth = 0;
                    while (i < ntoks) {
                        std::string t = getLine(i);
                        if (t == "LBRACE") depth++;
                        else if (t == "RBRACE") {
                            depth--;
                            if (depth == 0) { i++; break; }
                        }
                        i++;
                    }
                } else {
                    i++;
                }
            }
            // Remove trailing newline
            if (!table.empty() && table.back() == '\n') table.pop_back();
            push(Value(std::move(table)));
            break;
        }

        case OpCode::FIND_ENTRY: {
            // findEntry(tokens, ntoks) - find "just run {" or "go run {"
            Value ntoksV = pop();
            Value toksV = pop();
            const std::string &toks = toksV.str;
            int ntoks = ntoksV.isNum ? ntoksV.number : std::stoi(ntoksV.str);

            // Build line offsets
            std::vector<size_t> offs;
            offs.reserve(ntoks + 1);
            offs.push_back(0);
            for (size_t j = 0; j < toks.size(); j++) {
                if (toks[j] == '\n') offs.push_back(j + 1);
            }
            auto getLine = [&](int idx) -> std::string {
                if (idx < 0 || idx >= (int)offs.size()) return "";
                size_t start = offs[idx];
                size_t end = (idx + 1 < (int)offs.size()) ? offs[idx+1] - 1 : toks.size();
                return toks.substr(start, end - start);
            };

            int result = -1;
            for (int j = 0; j + 2 < ntoks; j++) {
                std::string t0 = getLine(j);
                if (t0 == "KW:go" || t0 == "KW:just") {
                    if (getLine(j+1) == "ID:run" && getLine(j+2) == "LBRACE") {
                        result = j + 2;
                        break;
                    }
                }
            }
            push(Value(result));
            break;
        }

        case OpCode::POP: {
            if (!valueStack.empty()) pop();
            break;
        }

        } // switch

        frame.ip++;
    }

    return retVal;
}

void ClassicalInterpreter::setArgs(const std::vector<std::string> &args) {
    programArgs = args;
}

} // namespace k