#pragma once

#include <memory>
#include <vector>
#include <string>
#include "../lexer/token.h"

namespace zen {

enum class ASTNodeType {
    // Expressions
    LITERAL,
    IDENTIFIER,
    BINARY_OP,
    UNARY_OP,
    ASSIGNMENT,
    FUNCTION_CALL,
    ARRAY_ACCESS,
    MEMBER_ACCESS,
    
    // Statements
    EXPRESSION_STMT,
    VARIABLE_DECLARATION,
    FUNCTION_DECLARATION,
    TYPE_DECLARATION,
    IF_STATEMENT,
    WHILE_STATEMENT,
    FOR_STATEMENT,
    RETURN_STATEMENT,
    BLOCK_STATEMENT,
    
    // Program
    PROGRAM
};

class ASTNode {
public:
    ASTNodeType type;
    int line;
    int column;
    
    ASTNode(ASTNodeType t, int ln = 0, int col = 0) 
        : type(t), line(ln), column(col) {}
    
    virtual ~ASTNode() = default;
};

// Expressions
class LiteralNode : public ASTNode {
public:
    std::string value;
    TokenType literal_type;
    
    LiteralNode(const std::string& val, TokenType type, int ln = 0, int col = 0)
        : ASTNode(ASTNodeType::LITERAL, ln, col), value(val), literal_type(type) {}
};

class IdentifierNode : public ASTNode {
public:
    std::string name;
    
    IdentifierNode(const std::string& n, int ln = 0, int col = 0)
        : ASTNode(ASTNodeType::IDENTIFIER, ln, col), name(n) {}
};

class BinaryOpNode : public ASTNode {
public:
    std::unique_ptr<ASTNode> left;
    std::unique_ptr<ASTNode> right;
    TokenType operator_type;
    
    BinaryOpNode(std::unique_ptr<ASTNode> l, std::unique_ptr<ASTNode> r, 
                 TokenType op, int ln = 0, int col = 0)
        : ASTNode(ASTNodeType::BINARY_OP, ln, col), left(std::move(l)), 
          right(std::move(r)), operator_type(op) {}
};

class UnaryOpNode : public ASTNode {
public:
    std::unique_ptr<ASTNode> operand;
    TokenType operator_type;
    
    UnaryOpNode(std::unique_ptr<ASTNode> op, TokenType oper, int ln = 0, int col = 0)
        : ASTNode(ASTNodeType::UNARY_OP, ln, col), operand(std::move(op)), operator_type(oper) {}
};

class AssignmentNode : public ASTNode {
public:
    std::unique_ptr<ASTNode> target;
    std::unique_ptr<ASTNode> value;
    TokenType assignment_type;
    
    AssignmentNode(std::unique_ptr<ASTNode> t, std::unique_ptr<ASTNode> v, 
                   TokenType type, int ln = 0, int col = 0)
        : ASTNode(ASTNodeType::ASSIGNMENT, ln, col), target(std::move(t)), 
          value(std::move(v)), assignment_type(type) {}
};

class FunctionCallNode : public ASTNode {
public:
    std::unique_ptr<ASTNode> function;
    std::vector<std::unique_ptr<ASTNode>> arguments;
    
    FunctionCallNode(std::unique_ptr<ASTNode> func, int ln = 0, int col = 0)
        : ASTNode(ASTNodeType::FUNCTION_CALL, ln, col), function(std::move(func)) {}
};

// Statements
class ExpressionStmtNode : public ASTNode {
public:
    std::unique_ptr<ASTNode> expression;
    
    ExpressionStmtNode(std::unique_ptr<ASTNode> expr, int ln = 0, int col = 0)
        : ASTNode(ASTNodeType::EXPRESSION_STMT, ln, col), expression(std::move(expr)) {}
};

class VariableDeclarationNode : public ASTNode {
public:
    std::string name;
    std::string type_name;
    std::unique_ptr<ASTNode> initializer;
    bool is_constant;
    bool is_optional;
    
    VariableDeclarationNode(const std::string& n, const std::string& t, 
                           std::unique_ptr<ASTNode> init, bool constant = false,
                           bool optional = false, int ln = 0, int col = 0)
        : ASTNode(ASTNodeType::VARIABLE_DECLARATION, ln, col), name(n), type_name(t),
          initializer(std::move(init)), is_constant(constant), is_optional(optional) {}
};

struct Parameter {
    std::string name;
    std::string type_name;
    bool is_optional;
    
    Parameter(const std::string& n, const std::string& t, bool opt = false)
        : name(n), type_name(t), is_optional(opt) {}
};

class FunctionDeclarationNode : public ASTNode {
public:
    std::string name;
    std::vector<Parameter> parameters;
    std::string return_type;
    std::unique_ptr<ASTNode> body;
    bool is_async;
    std::vector<std::string> target_annotations;
    
    FunctionDeclarationNode(const std::string& n, const std::string& ret_type,
                           std::unique_ptr<ASTNode> b, bool async = false,
                           int ln = 0, int col = 0)
        : ASTNode(ASTNodeType::FUNCTION_DECLARATION, ln, col), name(n), 
          return_type(ret_type), body(std::move(b)), is_async(async) {}
};

class BlockStatementNode : public ASTNode {
public:
    std::vector<std::unique_ptr<ASTNode>> statements;
    
    BlockStatementNode(int ln = 0, int col = 0)
        : ASTNode(ASTNodeType::BLOCK_STATEMENT, ln, col) {}
};

class IfStatementNode : public ASTNode {
public:
    std::unique_ptr<ASTNode> condition;
    std::unique_ptr<ASTNode> then_branch;
    std::unique_ptr<ASTNode> else_branch;
    
    IfStatementNode(std::unique_ptr<ASTNode> cond, std::unique_ptr<ASTNode> then_stmt,
                    std::unique_ptr<ASTNode> else_stmt = nullptr, int ln = 0, int col = 0)
        : ASTNode(ASTNodeType::IF_STATEMENT, ln, col), condition(std::move(cond)),
          then_branch(std::move(then_stmt)), else_branch(std::move(else_stmt)) {}
};

class ReturnStatementNode : public ASTNode {
public:
    std::unique_ptr<ASTNode> value;
    
    ReturnStatementNode(std::unique_ptr<ASTNode> val = nullptr, int ln = 0, int col = 0)
        : ASTNode(ASTNodeType::RETURN_STATEMENT, ln, col), value(std::move(val)) {}
};

class ProgramNode : public ASTNode {
public:
    std::vector<std::unique_ptr<ASTNode>> declarations;
    
    ProgramNode(int ln = 0, int col = 0)
        : ASTNode(ASTNodeType::PROGRAM, ln, col) {}
};

} // namespace zen