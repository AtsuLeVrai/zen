#ifndef ZEN_AST_H
#define ZEN_AST_H

#include "lexer.h"
#include <stdbool.h>

// Forward declarations
typedef struct ASTNode ASTNode;
typedef struct ASTExpression ASTExpression;
typedef struct ASTStatement ASTStatement;

// AST Node Types
typedef enum {
    // Expressions
    AST_LITERAL_EXPR,
    AST_IDENTIFIER_EXPR,
    AST_BINARY_EXPR,
    AST_UNARY_EXPR,
    AST_CALL_EXPR,
    AST_INTERPOLATION_EXPR,
    
    // Statements
    AST_EXPRESSION_STMT,
    AST_VAR_DECLARATION,
    AST_FUNCTION_DECLARATION,
    AST_RETURN_STMT,
    AST_BLOCK_STMT,
    AST_IF_STMT,
    AST_WHILE_STMT,
    AST_FOR_STMT,
    
    // Program
    AST_PROGRAM
} ASTNodeType;

// Literal types
typedef enum {
    LITERAL_NUMBER,
    LITERAL_STRING,
    LITERAL_BOOLEAN,
    LITERAL_NULL
} LiteralType;

// Binary operators
typedef enum {
    BINARY_ADD,
    BINARY_SUBTRACT,
    BINARY_MULTIPLY,
    BINARY_DIVIDE,
    BINARY_MODULO,
    BINARY_EQUAL,
    BINARY_NOT_EQUAL,
    BINARY_LESS,
    BINARY_LESS_EQUAL,
    BINARY_GREATER,
    BINARY_GREATER_EQUAL,
    BINARY_AND,
    BINARY_OR,
    BINARY_IS
} BinaryOperator;

// Unary operators
typedef enum {
    UNARY_MINUS,
    UNARY_NOT
} UnaryOperator;

// Type representations
typedef enum {
    TYPE_I32,
    TYPE_F64,
    TYPE_STRING,
    TYPE_BOOL,
    TYPE_VOID,
    TYPE_UNKNOWN
} ZenType;

// Base AST node structure
struct ASTNode {
    ASTNodeType type;
    Token token; // Token that created this node (for error reporting)
    int line;
    int column;
};

// Literal expression
typedef struct {
    ASTNode base;
    LiteralType literal_type;
    union {
        double number_value;
        char* string_value;
        bool boolean_value;
    } value;
} ASTLiteralExpr;

// Identifier expression
typedef struct {
    ASTNode base;
    char* name;
} ASTIdentifierExpr;

// Binary expression
typedef struct {
    ASTNode base;
    BinaryOperator operator;
    ASTNode* left;
    ASTNode* right;
} ASTBinaryExpr;

// Unary expression
typedef struct {
    ASTNode base;
    UnaryOperator operator;
    ASTNode* operand;
} ASTUnaryExpr;

// Function call expression
typedef struct {
    ASTNode base;
    ASTNode* callee;
    ASTNode** arguments;
    int argument_count;
} ASTCallExpr;

// Variable declaration
typedef struct {
    ASTNode base;
    char* name;
    ZenType var_type;
    bool is_const;
    ASTNode* initializer;
} ASTVarDeclaration;

// Function parameter
typedef struct {
    char* name;
    ZenType param_type;
} FunctionParameter;

// Function declaration
typedef struct {
    ASTNode base;
    char* name;
    FunctionParameter* parameters;
    int parameter_count;
    ZenType return_type;
    ASTNode* body;
} ASTFunctionDeclaration;

// Return statement
typedef struct {
    ASTNode base;
    ASTNode* value; // Can be NULL for void returns
} ASTReturnStmt;

// Block statement
typedef struct {
    ASTNode base;
    ASTNode** statements;
    int statement_count;
} ASTBlockStmt;

// Expression statement
typedef struct {
    ASTNode base;
    ASTNode* expression;
} ASTExpressionStmt;

// If statement
typedef struct {
    ASTNode base;
    ASTNode* condition;
    ASTNode* then_branch;
    ASTNode* else_branch; // Can be NULL
} ASTIfStmt;

// While statement
typedef struct {
    ASTNode base;
    ASTNode* condition;
    ASTNode* body;
} ASTWhileStmt;

// For statement
typedef struct {
    ASTNode base;
    char* variable;
    ASTNode* iterable;
    ASTNode* body;
} ASTForStmt;

// Program (root node)
typedef struct {
    ASTNode base;
    ASTNode** declarations;
    int declaration_count;
} ASTProgram;

// Memory management
typedef struct {
    ASTNode** nodes;
    int count;
    int capacity;
} ASTArena;

// Function declarations
ASTArena* ast_arena_create(void);
void ast_arena_destroy(ASTArena* arena);
void ast_arena_add(ASTArena* arena, ASTNode* node);

// Node creation functions
ASTNode* ast_create_literal_number(ASTArena* arena, double value, Token token);
ASTNode* ast_create_literal_string(ASTArena* arena, const char* value, Token token);
ASTNode* ast_create_literal_boolean(ASTArena* arena, bool value, Token token);
ASTNode* ast_create_literal_null(ASTArena* arena, Token token);
ASTNode* ast_create_identifier(ASTArena* arena, const char* name, Token token);
ASTNode* ast_create_binary_expr(ASTArena* arena, BinaryOperator op, ASTNode* left, ASTNode* right, Token token);
ASTNode* ast_create_unary_expr(ASTArena* arena, UnaryOperator op, ASTNode* operand, Token token);
ASTNode* ast_create_call_expr(ASTArena* arena, ASTNode* callee, ASTNode** args, int arg_count, Token token);
ASTNode* ast_create_var_declaration(ASTArena* arena, const char* name, ZenType type, bool is_const, ASTNode* init, Token token);
ASTNode* ast_create_function_declaration(ASTArena* arena, const char* name, FunctionParameter* params, int param_count, ZenType return_type, ASTNode* body, Token token);
ASTNode* ast_create_return_stmt(ASTArena* arena, ASTNode* value, Token token);
ASTNode* ast_create_block_stmt(ASTArena* arena, ASTNode** statements, int count, Token token);
ASTNode* ast_create_expression_stmt(ASTArena* arena, ASTNode* expr, Token token);
ASTNode* ast_create_if_stmt(ASTArena* arena, ASTNode* condition, ASTNode* then_branch, ASTNode* else_branch, Token token);
ASTNode* ast_create_while_stmt(ASTArena* arena, ASTNode* condition, ASTNode* body, Token token);
ASTNode* ast_create_for_stmt(ASTArena* arena, const char* variable, ASTNode* iterable, ASTNode* body, Token token);
ASTNode* ast_create_program(ASTArena* arena, ASTNode** declarations, int count);

// Utility functions
const char* ast_node_type_to_string(ASTNodeType type);
const char* binary_operator_to_string(BinaryOperator op);
const char* unary_operator_to_string(UnaryOperator op);
const char* zen_type_to_string(ZenType type);
ZenType token_type_to_zen_type(TokenType token_type);
BinaryOperator token_type_to_binary_operator(TokenType token_type);
UnaryOperator token_type_to_unary_operator(TokenType token_type);

// AST traversal and printing
void ast_print(ASTNode* node, int indent);

#endif // ZEN_AST_H