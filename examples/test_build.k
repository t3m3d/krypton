func build() {
    let r = ""
    r = r + "#include <stdio.h>\n"
    r = r + "#include <stdlib.h>\n"
    r = r + "#include <string.h>\n\n"
    r = r + "static int _argc; static char** _argv;\n\n"
    r = r + "static char* _alloc(int n) {\n"
    r = r + "    char* p = (char*)malloc(n);\n"
    r = r + "    if (!p) { fprintf(stderr, \"out of memory\\n\"); exit(1); }\n"
    r = r + "    return p;\n"
    r = r + "}\n\n"
    r = r + "static char* kr_str(const char* s) {\n"
    r = r + "    int n = (int)strlen(s) + 1;\n"
    r = r + "    char* p = _alloc(n);\n"
    r = r + "    memcpy(p, s, n);\n"
    r = r + "    return p;\n"
    r = r + "}\n\n"
    emit r
}

just run {
    let file = arg(0)
    let source = readFile(file)
    let tokens = "tok1\ntok2\ntok3\n"
    let ntoks = 3
    let ftable = ""
    let result = build()
    kp(result)
    emit "ok"
}
