#ifndef ZEN_CODEGEN_H
#define ZEN_CODEGEN_H

#include "ast.h"
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

// Target platforms
typedef enum {
    TARGET_NATIVE,
    TARGET_WASM
} CompileTarget;

// Code generation context
typedef struct {
    CompileTarget target;
    char* output_buffer;
    size_t buffer_size;
    size_t buffer_capacity;
    int indent_level;
    bool had_error;
    char* error_message;
} CodeGen;

// Symbol table for variables and functions
typedef struct Symbol {
    char* name;
    ZenType type;
    bool is_function;
    bool is_const;
    int stack_offset; // For native code generation
    struct Symbol* next;
} Symbol;

typedef struct SymbolTable {
    Symbol* symbols;
    struct SymbolTable* parent; // For nested scopes
} SymbolTable;

// Code generation functions
CodeGen* codegen_create(CompileTarget target);
void codegen_destroy(CodeGen* codegen);

// Main code generation entry point
bool codegen_generate(CodeGen* codegen, ASTNode* program);

// Node-specific code generation
bool codegen_program(CodeGen* codegen, ASTProgram* program);
bool codegen_function_declaration(CodeGen* codegen, ASTFunctionDeclaration* func);
bool codegen_variable_declaration(CodeGen* codegen, ASTVarDeclaration* var);
bool codegen_statement(CodeGen* codegen, ASTNode* stmt);
bool codegen_expression(CodeGen* codegen, ASTNode* expr);

// Expression code generation
bool codegen_literal(CodeGen* codegen, ASTLiteralExpr* literal);
bool codegen_identifier(CodeGen* codegen, ASTIdentifierExpr* ident);
bool codegen_binary_expr(CodeGen* codegen, ASTBinaryExpr* binary);
bool codegen_unary_expr(CodeGen* codegen, ASTUnaryExpr* unary);
bool codegen_call_expr(CodeGen* codegen, ASTCallExpr* call);

// Statement code generation
bool codegen_block_stmt(CodeGen* codegen, ASTBlockStmt* block);
bool codegen_expression_stmt(CodeGen* codegen, ASTExpressionStmt* expr_stmt);
bool codegen_return_stmt(CodeGen* codegen, ASTReturnStmt* ret_stmt);
bool codegen_if_stmt(CodeGen* codegen, ASTIfStmt* if_stmt);

// Symbol table management
SymbolTable* symbol_table_create(SymbolTable* parent);
void symbol_table_destroy(SymbolTable* table);
Symbol* symbol_table_add(SymbolTable* table, const char* name, ZenType type, bool is_function, bool is_const);
Symbol* symbol_table_lookup(SymbolTable* table, const char* name);

// Output buffer management
bool codegen_append(CodeGen* codegen, const char* code);
bool codegen_append_formatted(CodeGen* codegen, const char* format, ...);
void codegen_indent(CodeGen* codegen);
void codegen_newline(CodeGen* codegen);

// Error handling
void codegen_error(CodeGen* codegen, const char* message);
void codegen_error_formatted(CodeGen* codegen, const char* format, ...);

// Utility functions
const char* codegen_get_c_type(ZenType type);
const char* codegen_get_binary_operator(BinaryOperator op);
const char* codegen_get_unary_operator(UnaryOperator op);

// Built-in functions
bool codegen_builtin_print(CodeGen* codegen, ASTCallExpr* call);

#endif // ZEN_CODEGEN_H