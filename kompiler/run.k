go run {

    let source = "1 + 2 * 3";

    let tokens = lexer.tokenize(source);
    print("Tokens:");
    print(tokens);

    let ast = parser.parse(tokens);
    print("AST:");
    print(ast);

    let result = eval.eval(ast);
    print("Result:");
    print(result);
}