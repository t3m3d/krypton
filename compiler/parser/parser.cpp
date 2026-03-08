#include "parser.hpp"
#include <memory>
#include <stdexcept>

namespace k {


Parser::Parser(const std::vector<Token> &toks) : tokens(toks) {}

const Token &Parser::peek() const { return tokens[current]; }

const Token &Parser::previous() const { return tokens[current - 1]; }

bool Parser::isAtEnd() const { return peek().type == TokenType::END_OF_FILE; }

bool Parser::match(TokenType type) {
  if (isAtEnd())
    return false;
  if (peek().type != type)
    return false;
  current++;
  return true;
}

const Token &Parser::consume(TokenType type, const char *message) {
  if (peek().type == type) {
    current++;
    return previous();
  }
  throw std::runtime_error(message);
}


ModuleDecl Parser::parseProgram() {
    ModuleDecl module;

    if (match(TokenType::MODULE)) {
        consume(TokenType::IDENTIFIER, "Expected module name");
    }

    while (!isAtEnd()) {
        module.decls.push_back(parseDecl());
    }

    return module;
}


std::variant<FnDeclPtr, QputeDeclPtr, ProcessDeclPtr> Parser::parseDecl() {
  if (match(TokenType::FN)) {
    return parseFnDecl();
  }
  if (match(TokenType::QUANTUM)) {
    consume(TokenType::QPUTE, "Expected 'qpute' after 'quantum'");
    return parseQputeDecl();
  }
  if (match(TokenType::PROCESS) || match(TokenType::GO)) {
    return parseProcessDecl();
  }

  throw std::runtime_error("Unexpected declaration");
}

FnDeclPtr Parser::parseFnDecl() {
  FnDeclPtr fn = std::make_shared<FnDecl>();

  const Token &nameTok =
      consume(TokenType::IDENTIFIER, "Expected function name");
  fn->name = nameTok.lexeme;

  consume(TokenType::LPAREN, "Expected '(' after function name");

  if (peek().type != TokenType::RPAREN) {
    while (true) {
      Param p;
      const Token &paramName =
          consume(TokenType::IDENTIFIER, "Expected parameter name");
      p.name = paramName.lexeme;

      // Optional type annotation with colon
      if (match(TokenType::COLON)) {
        p.type = parseType();
      } else {
        // Default to dynamic/any (use Named with empty string)
        p.type = TypeNode::named("any");
      }

      fn->params.push_back(p);

      if (!match(TokenType::COMMA))
        break;
    }
  }

  consume(TokenType::RPAREN, "Expected ')' after parameters");

  // Optional return type
  if (match(TokenType::ARROW)) {
    fn->returnType = parseType();
  } else {
    fn->returnType = TypeNode::named("any");
  }

  fn->body = parseBlock();

  return fn;
}

QputeDeclPtr Parser::parseQputeDecl() {
  QputeDeclPtr qp = std::make_shared<QputeDecl>();

  const Token &nameTok = consume(TokenType::IDENTIFIER, "Expected qpute name");
  qp->name = nameTok.lexeme;

  consume(TokenType::LPAREN, "Expected '(' after qpute name");

  if (peek().type != TokenType::RPAREN) {
    while (true) {
      QParam p;
      const Token &paramName =
          consume(TokenType::IDENTIFIER, "Expected parameter name");
      p.name = paramName.lexeme;

      consume(TokenType::COLON, "Expected ':' after parameter name");
      p.type = parseType();

      qp->params.push_back(p);

      if (!match(TokenType::COMMA))
        break;
    }
  }

  consume(TokenType::RPAREN, "Expected ')' after parameters");

  qp->body = parseBlock();

  return qp;
}

ProcessDeclPtr Parser::parseProcessDecl() {
  ProcessDeclPtr proc = std::make_shared<ProcessDecl>();

  const Token &nameTok =
      consume(TokenType::IDENTIFIER, "Expected process name");
  proc->name = nameTok.lexeme;

  proc->body = parseBlock();
  return proc;
}

TypeNode Parser::parseType() {
  const Token &t = peek();

  if (t.type == TokenType::IDENTIFIER) {
    if (t.lexeme == "qbit") {
      current++;
      return TypeNode::quantumQbit();
    }
    if (t.lexeme == "int") {
      current++;
      return TypeNode::primitiveType(PrimitiveTypeKind::Int);
    }
    if (t.lexeme == "float") {
      current++;
      return TypeNode::primitiveType(PrimitiveTypeKind::Float);
    }
    if (t.lexeme == "bool") {
      current++;
      return TypeNode::primitiveType(PrimitiveTypeKind::Bool);
    }
    if (t.lexeme == "string") {
      current++;
      return TypeNode::primitiveType(PrimitiveTypeKind::String);
    }

    current++;
    return TypeNode::named(t.lexeme);
  }

  throw std::runtime_error("Expected type");
}

BlockPtr Parser::parseBlock() {
  consume(TokenType::LBRACE, "Expected '{' to start block");

  BlockPtr block = std::make_shared<Block>();

  while (!isAtEnd() && peek().type != TokenType::RBRACE) {
    block->statements.push_back(parseStmt());
  }

  consume(TokenType::RBRACE, "Expected '}' to end block");
  return block;
}

StmtPtr Parser::parseStmt() {
  if (match(TokenType::LET))
    return parseLetStmt();
  if (match(TokenType::EMIT))
    return parseEmitStmt();
  if (match(TokenType::RETURN))
    return parseReturnStmt();
  if (match(TokenType::IF))
    return parseIfStmt();
  if (match(TokenType::WHILE))
    return parseWhileStmt();
  if (match(TokenType::BREAK)) {
    match(TokenType::SEMICOLON); // optional semicolon
    return Stmt::breakStmt();
  }
  return parseExprStmt();
}

StmtPtr Parser::parseLetStmt() {
  const Token &nameTok =
      consume(TokenType::IDENTIFIER, "Expected variable name after 'let'");
  consume(TokenType::EQUAL, "Expected '=' after variable name");
  ExprPtr value = parseExpr();
  match(TokenType::SEMICOLON); // optional semicolon
  return Stmt::letStmt(nameTok.lexeme, value);
}

StmtPtr Parser::parseEmitStmt() {
  ExprPtr value = parseExpr();
  match(TokenType::SEMICOLON); // optional semicolon
  return Stmt::emitStmt(value);
}

StmtPtr Parser::parseReturnStmt() {
  ExprPtr value = parseExpr();
  match(TokenType::SEMICOLON); // optional semicolon
  return Stmt::returnStmt(value);
}

StmtPtr Parser::parseIfStmt() {
    ExprPtr cond = parseExpr();

    BlockPtr thenBlock = parseBlock();

    BlockPtr elseBlock = nullptr;
    if (match(TokenType::ELSE)) {
        if (peek().type == TokenType::IF) {
            // else if => wrap in a block containing one if-stmt
            auto innerIf = parseStmt(); // will match IF and recurse
            elseBlock = std::make_shared<Block>();
            elseBlock->statements.push_back(innerIf);
        } else {
            elseBlock = parseBlock();
        }
    }

    if (elseBlock)
        return Stmt::ifElseStmt(cond, thenBlock, elseBlock);
    else
        return Stmt::ifStmt(cond, thenBlock);
}

StmtPtr Parser::parseExprStmt() {
    // Check for assignment: identifier = expr
    if (peek().type == TokenType::IDENTIFIER) {
        // Look ahead for '='
        std::size_t saved = current;
        std::string name = peek().lexeme;
        current++;
        if (!isAtEnd() && peek().type == TokenType::EQUAL) {
            current++; // consume '='
            ExprPtr value = parseExpr();
            match(TokenType::SEMICOLON); // optional semicolon
            return Stmt::assignStmt(name, value);
        }
        current = saved; // backtrack
    }
    ExprPtr expr = parseExpr();
    match(TokenType::SEMICOLON); // optional semicolon
    return Stmt::exprStmt(expr);
}

StmtPtr Parser::parseWhileStmt() {
    ExprPtr cond = parseExpr();
    BlockPtr body = parseBlock();
    return Stmt::whileStmt(cond, body);
}

ExprPtr Parser::parseExpr() { return parseOrExpr(); }

ExprPtr Parser::parseOrExpr() {
  ExprPtr expr = parseAndExpr();

  while (match(TokenType::OROR)) {
    ExprPtr right = parseAndExpr();
    expr = Expr::binary("||", expr, right);
  }

  return expr;
}

ExprPtr Parser::parseAndExpr() {
  ExprPtr expr = parseEqualityExpr();

  while (match(TokenType::ANDAND)) {
    ExprPtr right = parseEqualityExpr();
    expr = Expr::binary("&&", expr, right);
  }

  return expr;
}

ExprPtr Parser::parseEqualityExpr() {
  ExprPtr expr = parseRelExpr();

  while (true) {
    if (match(TokenType::EQEQ)) {
      ExprPtr right = parseRelExpr();
      expr = Expr::binary("==", expr, right);
    } else if (match(TokenType::BANGEQ)) {
      ExprPtr right = parseRelExpr();
      expr = Expr::binary("!=", expr, right);
    } else
      break;
  }

  return expr;
}

ExprPtr Parser::parseRelExpr() {
  ExprPtr expr = parseAddExpr();

  while (true) {
    if (match(TokenType::LT)) {
      ExprPtr right = parseAddExpr();
      expr = Expr::binary("<", expr, right);
    } else if (match(TokenType::GT)) {
      ExprPtr right = parseAddExpr();
      expr = Expr::binary(">", expr, right);
    } else if (match(TokenType::LTE)) {
      ExprPtr right = parseAddExpr();
      expr = Expr::binary("<=", expr, right);
    } else if (match(TokenType::GTE)) {
      ExprPtr right = parseAddExpr();
      expr = Expr::binary(">=", expr, right);
    } else
      break;
  }

  return expr;
}

ExprPtr Parser::parseAddExpr() {
  ExprPtr expr = parseMulExpr();

  while (true) {
    if (match(TokenType::PLUS)) {
      ExprPtr right = parseMulExpr();
      expr = Expr::binary("+", expr, right);
    } else if (match(TokenType::MINUS)) {
      ExprPtr right = parseMulExpr();
      expr = Expr::binary("-", expr, right);
    } else
      break;
  }

  return expr;
}

ExprPtr Parser::parseMulExpr() {
  ExprPtr expr = parseUnaryExpr();

  while (true) {
    if (match(TokenType::STAR)) {
      ExprPtr right = parseUnaryExpr();
      expr = Expr::binary("*", expr, right);
    } else if (match(TokenType::SLASH)) {
      ExprPtr right = parseUnaryExpr();
      expr = Expr::binary("/", expr, right);
    } else
      break;
  }

  return expr;
}

ExprPtr Parser::parseUnaryExpr() {
  if (match(TokenType::BANG)) {
    return Expr::unary("!", parseUnaryExpr());
  }
  if (match(TokenType::PLUS)) {
    return Expr::unary("+", parseUnaryExpr());
  }
  if (match(TokenType::MINUS)) {
    return Expr::unary("-", parseUnaryExpr());
  }
  return parsePostfixExpr();
}

ExprPtr Parser::parsePostfixExpr() {
  ExprPtr expr = parsePrimaryExpr();

  // Handle postfix indexing: expr[index]
  while (match(TokenType::LBRACKET)) {
    ExprPtr idx = parseExpr();
    consume(TokenType::RBRACKET, "Expected ']' after index");
    expr = Expr::index(expr, idx);
  }

  return expr;
}

ExprPtr Parser::parsePrimaryExpr() {

  if (match(TokenType::INT_LITERAL)) {
    auto e = std::make_shared<Expr>();
    e->kind = ExprKind::Literal;
    e->litKind = LiteralKind::Int;
    e->litInt = std::stoi(previous().lexeme);
    return e;
  }

  if (match(TokenType::FLOAT_LITERAL)) {
    auto e = std::make_shared<Expr>();
    e->kind = ExprKind::Literal;
    e->litKind = LiteralKind::Float;
    e->litFloat = std::stod(previous().lexeme);
    return e;
  }

  if (match(TokenType::STRING_LITERAL)) {
    auto e = std::make_shared<Expr>();
    e->kind = ExprKind::Literal;
    e->litKind = LiteralKind::String;
    e->litString = previous().lexeme;
    return e;
  }

  if (match(TokenType::TRUE_)) {
    auto e = std::make_shared<Expr>();
    e->kind = ExprKind::Literal;
    e->litKind = LiteralKind::Bool;
    e->litBool = true;
    return e;
  }

  if (match(TokenType::FALSE_)) {
    auto e = std::make_shared<Expr>();
    e->kind = ExprKind::Literal;
    e->litKind = LiteralKind::Bool;
    e->litBool = false;
    return e;
  }

  if (match(TokenType::PREPARE)) {
    const Token &qtok =
        consume(TokenType::IDENTIFIER, "Expected 'qbit' after 'prepare'");
    if (qtok.lexeme != "qbit") {
      throw std::runtime_error("Expected 'qbit' after 'prepare'");
    }
    return Expr::prepare();
  }

  if (match(TokenType::MEASURE)) {
    const Token &target =
        consume(TokenType::IDENTIFIER, "Expected identifier after 'measure'");
    return Expr::measure(target.lexeme);
  }

  if (match(TokenType::LPAREN)) {
    ExprPtr inner = parseExpr();
    consume(TokenType::RPAREN, "Expected ')' after expression");
    return Expr::grouping(inner);
  }

  if (match(TokenType::IDENTIFIER)) {
    std::string name = previous().lexeme;

    if (match(TokenType::LPAREN)) {
      std::vector<ExprPtr> args;

      if (peek().type != TokenType::RPAREN) {
        while (true) {
          args.push_back(parseExpr());
          if (!match(TokenType::COMMA))
            break;
        }
      }

      consume(TokenType::RPAREN, "Expected ')' after arguments");
      return Expr::call(name, args);
    }

    return Expr::identifierExpr(name);
  }

  throw std::runtime_error("Unexpected expression");
}

} // namespace k