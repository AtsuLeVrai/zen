#include "parser.h"
#include <iostream>
#include <stdexcept>

namespace zen {

Parser::Parser(std::vector<std::unique_ptr<Token>> tokens) 
    : tokens(std::move(tokens)), current(0) {}

std::unique_ptr<ASTNode> Parser::parse() {
    try {
        return program();
    } catch (const std::exception& e) {
        std::cerr << "Parse error: " << e.what() << std::endl;
        return nullptr;
    }
}

Token* Parser::peek(size_t offset) const {
    size_t index = current + offset;
    if (index >= tokens.size()) {
        return tokens.back().get(); // EOF token
    }
    return tokens[index].get();
}

Token* Parser::advance() {
    if (!isAtEnd()) current++;
    return tokens[current - 1].get();
}

bool Parser::isAtEnd() const {
    return peek()->type == TokenType::END_OF_FILE;
}

bool Parser::check(TokenType type) const {
    if (isAtEnd()) return false;
    return peek()->type == type;
}

bool Parser::match(std::initializer_list<TokenType> types) {
    for (TokenType type : types) {
        if (check(type)) {
            advance();
            return true;
        }
    }
    return false;
}

Token* Parser::consume(TokenType type, const std::string& message) {
    if (check(type)) return advance();
    
    error(message);
    throw std::runtime_error(message);
}

void Parser::synchronize() {
    advance();
    
    while (!isAtEnd()) {
        if (tokens[current - 1]->type == TokenType::SEMICOLON) return;
        
        switch (peek()->type) {
            case TokenType::FUNC:
            case TokenType::LET:
            case TokenType::CONST:
            case TokenType::IF:
            case TokenType::WHILE:
            case TokenType::FOR:
            case TokenType::RETURN:
                return;
            default:
                break;
        }
        
        advance();
    }
}

void Parser::error(const std::string& message) {
    Token* token = peek();
    std::cerr << "Error at line " << token->line << ", column " << token->column 
              << ": " << message << std::endl;
}

std::unique_ptr<ASTNode> Parser::program() {
    auto program = std::make_unique<ProgramNode>();
    
    while (!isAtEnd()) {
        if (match({TokenType::NEWLINE})) {
            continue; // Skip newlines at top level
        }
        
        auto decl = declaration();
        if (decl) {
            program->declarations.push_back(std::move(decl));
        }
    }
    
    return std::move(program);
}

std::unique_ptr<ASTNode> Parser::declaration() {
    try {
        if (match({TokenType::FUNC})) return functionDeclaration();
        if (match({TokenType::LET, TokenType::CONST})) return variableDeclaration();
        
        return statement();
    } catch (const std::exception& e) {
        synchronize();
        return nullptr;
    }
}

std::unique_ptr<ASTNode> Parser::functionDeclaration() {
    Token* name = consume(TokenType::IDENTIFIER, "Expected function name");
    
    consume(TokenType::LEFT_PAREN, "Expected '(' after function name");
    std::vector<Parameter> parameters = parseParameters();
    consume(TokenType::RIGHT_PAREN, "Expected ')' after parameters");
    
    std::string return_type = "void";
    if (match({TokenType::ARROW})) {
        return_type = parseType();
    }
    
    consume(TokenType::LEFT_BRACE, "Expected '{' before function body");
    auto body = blockStatement();
    
    auto func = std::make_unique<FunctionDeclarationNode>(
        name->lexeme, return_type, std::move(body), false, name->line, name->column
    );
    func->parameters = std::move(parameters);
    
    return std::move(func);
}

std::unique_ptr<ASTNode> Parser::variableDeclaration() {
    bool is_constant = tokens[current - 1]->type == TokenType::CONST;
    
    Token* name = consume(TokenType::IDENTIFIER, "Expected variable name");
    
    consume(TokenType::COLON, "Expected ':' after variable name");
    std::string type_name = parseType();
    
    std::unique_ptr<ASTNode> initializer = nullptr;
    if (match({TokenType::ASSIGN})) {
        initializer = expression();
    }
    
    if (!is_constant && !initializer) {
        error("Variable declaration requires initializer");
    }
    
    consume(TokenType::SEMICOLON, "Expected ';' after variable declaration");
    
    return std::make_unique<VariableDeclarationNode>(
        name->lexeme, type_name, std::move(initializer), is_constant,
        false, name->line, name->column
    );
}

std::unique_ptr<ASTNode> Parser::statement() {
    if (match({TokenType::IF})) return ifStatement();
    if (match({TokenType::WHILE})) return whileStatement();
    if (match({TokenType::RETURN})) return returnStatement();
    if (match({TokenType::LEFT_BRACE})) return blockStatement();
    
    return expressionStatement();
}

std::unique_ptr<ASTNode> Parser::blockStatement() {
    auto block = std::make_unique<BlockStatementNode>();
    
    while (!check(TokenType::RIGHT_BRACE) && !isAtEnd()) {
        if (match({TokenType::NEWLINE})) {
            continue; // Skip newlines in blocks
        }
        
        auto stmt = declaration();
        if (stmt) {
            block->statements.push_back(std::move(stmt));
        }
    }
    
    consume(TokenType::RIGHT_BRACE, "Expected '}' after block");
    return std::move(block);
}

std::unique_ptr<ASTNode> Parser::expressionStatement() {
    auto expr = expression();
    consume(TokenType::SEMICOLON, "Expected ';' after expression");
    return std::make_unique<ExpressionStmtNode>(std::move(expr));
}

std::unique_ptr<ASTNode> Parser::ifStatement() {
    consume(TokenType::LEFT_PAREN, "Expected '(' after 'if'");
    auto condition = expression();
    consume(TokenType::RIGHT_PAREN, "Expected ')' after if condition");
    
    auto then_branch = statement();
    std::unique_ptr<ASTNode> else_branch = nullptr;
    
    if (match({TokenType::ELSE})) {
        else_branch = statement();
    }
    
    return std::make_unique<IfStatementNode>(
        std::move(condition), std::move(then_branch), std::move(else_branch)
    );
}

std::unique_ptr<ASTNode> Parser::whileStatement() {
    consume(TokenType::LEFT_PAREN, "Expected '(' after 'while'");
    auto condition = expression();
    consume(TokenType::RIGHT_PAREN, "Expected ')' after while condition");
    
    auto body = statement();
    
    // For now, create a simple while node (would need WhileStatementNode in AST)
    return std::make_unique<BlockStatementNode>();
}

std::unique_ptr<ASTNode> Parser::returnStatement() {
    Token* keyword = tokens[current - 1].get();
    std::unique_ptr<ASTNode> value = nullptr;
    
    if (!check(TokenType::SEMICOLON)) {
        value = expression();
    }
    
    consume(TokenType::SEMICOLON, "Expected ';' after return value");
    return std::make_unique<ReturnStatementNode>(std::move(value), keyword->line, keyword->column);
}

std::unique_ptr<ASTNode> Parser::expression() {
    return assignment();
}

std::unique_ptr<ASTNode> Parser::assignment() {
    auto expr = logicalOr();
    
    if (match({TokenType::ASSIGN, TokenType::PLUS_ASSIGN, TokenType::MINUS_ASSIGN,
               TokenType::MULTIPLY_ASSIGN, TokenType::DIVIDE_ASSIGN})) {
        Token* operator_token = tokens[current - 1].get();
        auto value = assignment();
        
        return std::make_unique<AssignmentNode>(
            std::move(expr), std::move(value), operator_token->type,
            operator_token->line, operator_token->column
        );
    }
    
    return expr;
}

std::unique_ptr<ASTNode> Parser::logicalOr() {
    auto expr = logicalAnd();
    
    while (match({TokenType::OR})) {
        Token* operator_token = tokens[current - 1].get();
        auto right = logicalAnd();
        expr = std::make_unique<BinaryOpNode>(
            std::move(expr), std::move(right), operator_token->type,
            operator_token->line, operator_token->column
        );
    }
    
    return expr;
}

std::unique_ptr<ASTNode> Parser::logicalAnd() {
    auto expr = equality();
    
    while (match({TokenType::AND})) {
        Token* operator_token = tokens[current - 1].get();
        auto right = equality();
        expr = std::make_unique<BinaryOpNode>(
            std::move(expr), std::move(right), operator_token->type,
            operator_token->line, operator_token->column
        );
    }
    
    return expr;
}

std::unique_ptr<ASTNode> Parser::equality() {
    auto expr = comparison();
    
    while (match({TokenType::NOT_EQUAL, TokenType::EQUAL})) {
        Token* operator_token = tokens[current - 1].get();
        auto right = comparison();
        expr = std::make_unique<BinaryOpNode>(
            std::move(expr), std::move(right), operator_token->type,
            operator_token->line, operator_token->column
        );
    }
    
    return expr;
}

std::unique_ptr<ASTNode> Parser::comparison() {
    auto expr = term();
    
    while (match({TokenType::GREATER_THAN, TokenType::GREATER_EQUAL,
                  TokenType::LESS_THAN, TokenType::LESS_EQUAL})) {
        Token* operator_token = tokens[current - 1].get();
        auto right = term();
        expr = std::make_unique<BinaryOpNode>(
            std::move(expr), std::move(right), operator_token->type,
            operator_token->line, operator_token->column
        );
    }
    
    return expr;
}

std::unique_ptr<ASTNode> Parser::term() {
    auto expr = factor();
    
    while (match({TokenType::MINUS, TokenType::PLUS})) {
        Token* operator_token = tokens[current - 1].get();
        auto right = factor();
        expr = std::make_unique<BinaryOpNode>(
            std::move(expr), std::move(right), operator_token->type,
            operator_token->line, operator_token->column
        );
    }
    
    return expr;
}

std::unique_ptr<ASTNode> Parser::factor() {
    auto expr = unary();
    
    while (match({TokenType::DIVIDE, TokenType::MULTIPLY, TokenType::MODULO})) {
        Token* operator_token = tokens[current - 1].get();
        auto right = unary();
        expr = std::make_unique<BinaryOpNode>(
            std::move(expr), std::move(right), operator_token->type,
            operator_token->line, operator_token->column
        );
    }
    
    return expr;
}

std::unique_ptr<ASTNode> Parser::unary() {
    if (match({TokenType::NOT, TokenType::MINUS})) {
        Token* operator_token = tokens[current - 1].get();
        auto right = unary();
        return std::make_unique<UnaryOpNode>(
            std::move(right), operator_token->type,
            operator_token->line, operator_token->column
        );
    }
    
    return call();
}

std::unique_ptr<ASTNode> Parser::call() {
    auto expr = primary();
    
    while (true) {
        if (match({TokenType::LEFT_PAREN})) {
            expr = finishCall(std::move(expr));
        } else {
            break;
        }
    }
    
    return expr;
}

std::unique_ptr<ASTNode> Parser::finishCall(std::unique_ptr<ASTNode> callee) {
    auto call_node = std::make_unique<FunctionCallNode>(std::move(callee));
    
    if (!check(TokenType::RIGHT_PAREN)) {
        do {
            call_node->arguments.push_back(expression());
        } while (match({TokenType::COMMA}));
    }
    
    consume(TokenType::RIGHT_PAREN, "Expected ')' after arguments");
    return std::move(call_node);
}

std::unique_ptr<ASTNode> Parser::primary() {
    if (match({TokenType::NUMBER})) {
        Token* token = tokens[current - 1].get();
        return std::make_unique<LiteralNode>(token->lexeme, TokenType::NUMBER, 
                                           token->line, token->column);
    }
    
    if (match({TokenType::STRING})) {
        Token* token = tokens[current - 1].get();
        return std::make_unique<LiteralNode>(token->lexeme, TokenType::STRING,
                                           token->line, token->column);
    }
    
    if (match({TokenType::IDENTIFIER})) {
        Token* token = tokens[current - 1].get();
        return std::make_unique<IdentifierNode>(token->lexeme, token->line, token->column);
    }
    
    if (match({TokenType::LEFT_PAREN})) {
        auto expr = expression();
        consume(TokenType::RIGHT_PAREN, "Expected ')' after expression");
        return expr;
    }
    
    error("Expected expression");
    throw std::runtime_error("Expected expression");
}

std::string Parser::parseType() {
    bool is_optional = match({TokenType::QUESTION});
    
    if (match({TokenType::I32})) return is_optional ? "?i32" : "i32";
    if (match({TokenType::F64})) return is_optional ? "?f64" : "f64";
    if (match({TokenType::STRING_TYPE})) return is_optional ? "?string" : "string";
    if (match({TokenType::BOOL})) return is_optional ? "?bool" : "bool";
    if (match({TokenType::VOID})) return "void";
    
    if (match({TokenType::IDENTIFIER})) {
        std::string type_name = tokens[current - 1]->lexeme;
        
        // Check for array syntax
        if (match({TokenType::LEFT_BRACKET})) {
            consume(TokenType::RIGHT_BRACKET, "Expected ']' after '['");
            type_name += "[]";
        }
        
        return is_optional ? "?" + type_name : type_name;
    }
    
    error("Expected type");
    throw std::runtime_error("Expected type");
}

std::vector<Parameter> Parser::parseParameters() {
    std::vector<Parameter> parameters;
    
    if (!check(TokenType::RIGHT_PAREN)) {
        do {
            Token* name = consume(TokenType::IDENTIFIER, "Expected parameter name");
            consume(TokenType::COLON, "Expected ':' after parameter name");
            std::string type = parseType();
            
            parameters.emplace_back(name->lexeme, type, type[0] == '?');
        } while (match({TokenType::COMMA}));
    }
    
    return parameters;
}

} // namespace zen