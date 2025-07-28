#pragma once

#include "../lexer/token.h"
#include "../ast/ast_node.h"
#include <vector>
#include <memory>

namespace zen
{
    class Parser
    {
    private:
        std::vector<std::unique_ptr<Token>> tokens;
        size_t current;

        Token* peek(size_t offset = 0) const;
        Token* advance();
        bool isAtEnd() const;
        bool check(TokenType type) const;
        bool match(std::initializer_list<TokenType> types);
        Token* consume(TokenType type, const std::string& message);

        void synchronize();
        void error(const std::string& message);

        // Grammar rules
        std::unique_ptr<ASTNode> program();
        std::unique_ptr<ASTNode> declaration();
        std::unique_ptr<ASTNode> functionDeclaration();
        std::unique_ptr<ASTNode> variableDeclaration();
        std::unique_ptr<ASTNode> statement();
        std::unique_ptr<ASTNode> blockStatement();
        std::unique_ptr<ASTNode> expressionStatement();
        std::unique_ptr<ASTNode> ifStatement();
        std::unique_ptr<ASTNode> whileStatement();
        std::unique_ptr<ASTNode> returnStatement();

        std::unique_ptr<ASTNode> expression();
        std::unique_ptr<ASTNode> assignment();
        std::unique_ptr<ASTNode> logicalOr();
        std::unique_ptr<ASTNode> logicalAnd();
        std::unique_ptr<ASTNode> equality();
        std::unique_ptr<ASTNode> comparison();
        std::unique_ptr<ASTNode> term();
        std::unique_ptr<ASTNode> factor();
        std::unique_ptr<ASTNode> unary();
        std::unique_ptr<ASTNode> call();
        std::unique_ptr<ASTNode> primary();

        std::unique_ptr<ASTNode> finishCall(std::unique_ptr<ASTNode> callee);

        std::string parseType();
        std::vector<Parameter> parseParameters();

    public:
        Parser(std::vector<std::unique_ptr<Token>> tokens);
        ~Parser() = default;

        std::unique_ptr<ASTNode> parse();
    };
} // namespace zen
